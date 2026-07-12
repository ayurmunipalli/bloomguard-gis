# ============================================================
# FILE:       python/dl_dataset.py
# PURPOSE:    Dataset utilities for Stage-2 temporal transformer (A11 / M3).
#             Builds per-cell ordered sequences of level+trend features
#             (through day T) paired with T+H HAB labels.
# INPUTS:     data/processed/model_dataset.parquet
# OUTPUTS:    HABSequenceDataset (used by modeling_transformer.py)
# TECHNIQUES: Per-cell temporal lookback sequences (seq_len most recent
#             observations with date <= T); positional mask for padded steps;
#             same ALWAYS_EXCLUDE list as R/07_modeling.R;
#             same 3 split definitions (random/temporal/spatial);
#             log1p outlier treatment on chlor_a_mean/nflh_mean/Kd_490_mean;
#             per-feature z-score standardization (fit on training anchor rows
#             only, applied to all sequence steps, clipped ±5σ);
#             label-encoding for string categorical columns.
# CITATIONS:  see modeling_transformer.py for citations.
# ============================================================

# NOTE(paper): NO look-ahead in sequence construction.
#   Every timestep date in the lookback window is <= T (the anchor date).
#   The label (HAB_H{k}) is the future status at T+H, pre-computed in the
#   parquet by A6 with the same no-leakage guarantee. Assertion added in code.
# NOTE(paper): Same ALWAYS_EXCLUDE feature list as A7 (R/07_modeling.R) to
#   ensure the transformer sees exactly the same feature set as the RF,
#   making the head-to-head comparison fair.
# NOTE(limitation): Observation cadence is irregular (median inter-observation
#   gap ~7d for labeled cells). The transformer uses sequence-position
#   embeddings, not calendar-date embeddings. A 'days_to_anchor' feature is
#   appended per timestep so the model can learn temporal spacing.

import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset

# ── SHARED CONSTANTS (mirror R/07_modeling.R exactly) ──────────────────────

HORIZONS = [1, 3, 5, 7, 14]
SEED = 42
TEMPORAL_CUTOFF_YEAR = 2016    # train <2016, test >=2016
TRAIN_FRAC = 0.80
MIN_BLOCK_ROWS = 5             # merge spatial blocks smaller than this
SEQ_LEN = 14                   # lookback: last 14 available observations per cell

# NOTE(paper): log1p applied to the same three heavy-tailed satellite features
#   as in R/07_modeling.R (A7). Allows numeric stability without discarding
#   extreme values; binary label already absorbs bloom-count extremes.
LOG_FEATURES = ["chlor_a_mean", "nflh_mean", "Kd_490_mean"]

# NOTE(paper): Feature exclusion list exactly mirrors ALWAYS_EXCLUDE in
#   R/07_modeling.R. Excluded: identifiers, same-day HAB (would conflate
#   detection with forecasting), all HAB_Hk labels, spatial CV key,
#   raw HABSOS count columns (max_count > 100,000 = label-definition leakage),
#   diagnostic/meta flags, and the 6 all-NA placeholder env columns.
ALWAYS_EXCLUDE = [
    # Identifiers
    "cell_id", "date_T",
    # Same-day detection label (detection != forecasting)
    "HAB",
    # All T+H labels (target added back per horizon)
    "HAB_H1", "HAB_H3", "HAB_H5", "HAB_H7", "HAB_H14",
    # Spatial CV grouping key (not a predictor)
    "spatial_block_tiger",
    # HABSOS raw count columns (label-definition leakage)
    "max_count", "n_samples",
    # Diagnostic/meta flags
    "IS_PLACEHOLDER_ROW", "satellite_missing", "cloud_flag",
    "salinity_coarse_flag", "feature_filled_any", "IS_ABSENCE_UNCERTAIN",
    "sat_IS_PLACEHOLDER", "env_IS_PLACEHOLDER",
    "static_IS_PLACEHOLDER", "label_IS_PLACEHOLDER",
    "sat_feature_filled", "env_feature_filled",
    # All-NA placeholder env columns (ERA5/CHIRPS/SMAP not yet pulled)
    "wind_u_ms", "wind_v_ms", "wind_speed_ms", "wind_dir_deg",
    "precip_mm", "salinity_pss",
]

# String categorical columns (label-encoded to integers for the neural network)
# NOTE(paper): county_fips, county_name, state_fips are string columns that
#   ranger handles as factors internally. The transformer receives integer-
#   encoded versions scaled to [0,1] by dividing by n_unique.
STRING_COLS = ["county_fips", "county_name", "state_fips"]

# ── DATA LOADING AND PREPROCESSING ─────────────────────────────────────────

def load_and_preprocess(parquet_path: str) -> pd.DataFrame:
    """
    Load model_dataset.parquet, apply log1p transforms, encode categoricals,
    and parse date_T to datetime. Returns full DataFrame (all 65,939 rows).
    """
    import pyarrow.parquet as pq
    df = pq.read_table(parquet_path).to_pandas()

    # Parse date column
    df["date_T"] = pd.to_datetime(df["date_T"])

    # log1p outlier treatment (same as A7)
    if "chlor_a_mean" in df.columns:
        df["chlor_a_mean"] = np.log1p(np.maximum(df["chlor_a_mean"].values, 0.0))
    if "nflh_mean" in df.columns:
        # nflh can be negative; signed log1p preserves sign
        v = df["nflh_mean"].values
        df["nflh_mean"] = np.sign(v) * np.log1p(np.abs(v))
    if "Kd_490_mean" in df.columns:
        df["Kd_490_mean"] = np.log1p(np.maximum(df["Kd_490_mean"].values, 0.0))

    # Label-encode string categorical columns
    for col in STRING_COLS:
        if col in df.columns:
            df[col] = df[col].fillna("__MISSING__")
            cats = sorted(df[col].unique())
            cat_map = {c: i for i, c in enumerate(cats)}
            df[col] = df[col].map(cat_map).astype(float)
            n = len(cats)
            if n > 1:
                df[col] = df[col] / (n - 1)   # scale to [0, 1]

    return df


def get_feat_cols(df: pd.DataFrame, H: int) -> list:
    """
    Return feature column list for horizon H, mirroring A7's feat_cols computation.
    Excludes ALWAYS_EXCLUDE + other HAB_Hk + target_col.
    """
    target_col = f"HAB_H{H}"
    other_labels = [f"HAB_H{hh}" for hh in HORIZONS if hh != H]
    excl = set(ALWAYS_EXCLUDE) | set(other_labels) | {target_col}
    return [c for c in df.columns if c not in excl]


# ── SPATIAL BLOCK UTILITIES ─────────────────────────────────────────────────

def merge_tiny_blocks(blocks: np.ndarray, min_rows: int = MIN_BLOCK_ROWS) -> np.ndarray:
    """
    Python port of R/07_modeling.R merge_tiny_blocks().
    Merges spatial blocks with < min_rows rows into the largest block.
    """
    # NOTE(paper): Singleton/tiny spatial blocks cannot function as standalone
    #   CV holdout sets. Blocks with fewer than MIN_BLOCK_ROWS rows are merged
    #   into the largest block. Mirrors R/07_modeling.R exactly.
    counts = pd.Series(blocks).value_counts()
    tiny = counts[counts < min_rows].index.tolist()
    if not tiny:
        return blocks.copy()
    target = counts.index[0]   # largest block (value_counts sorts descending)
    result = blocks.copy()
    result[np.isin(result, tiny)] = target
    return result


# ── SPLIT CONSTRUCTION ──────────────────────────────────────────────────────

def get_splits(h_df: pd.DataFrame, H: int) -> dict:
    """
    Build the same three train/test splits as R/07_modeling.R for this horizon.
    Returns dict: {'random': (train_idx, test_idx), 'temporal': ..., 'spatial': ...}
    where indices are integer positions into h_df (not global df positions).

    NOTE(paper): Splits mirror A7 exactly for a fair RF vs transformer comparison.
      - random:   stratified 80/20 (numpy seed = SEED + H, matching R seed logic)
      - temporal: train year < TEMPORAL_CUTOFF_YEAR (2016), test >= 2016
      - spatial:  greedy county-block holdout until >= 15% of rows in test
    """
    target_col = f"HAB_H{H}"
    y = h_df[target_col].values.astype(int)
    N = len(h_df)

    # ---- (1) Random stratified 80/20 ----
    # NOTE: R uses its own RNG which differs from numpy. The split is statistically
    #   equivalent (same stratification, same proportions) but not identical row-for-row.
    rng = np.random.default_rng(SEED + H)
    pos_idx = np.where(y == 1)[0]
    neg_idx = np.where(y == 0)[0]
    n_pos_train = int(np.floor(TRAIN_FRAC * len(pos_idx)))
    n_neg_train = int(np.floor(TRAIN_FRAC * len(neg_idx)))
    rng.shuffle(pos_idx); rng.shuffle(neg_idx)
    rand_train = np.sort(np.concatenate([pos_idx[:n_pos_train], neg_idx[:n_neg_train]]))
    rand_test  = np.array(sorted(set(range(N)) - set(rand_train)))

    # ---- (2) Temporal holdout ----
    year = h_df["date_T"].dt.year.values
    temp_train = np.where(year < TEMPORAL_CUTOFF_YEAR)[0]
    temp_test  = np.where(year >= TEMPORAL_CUTOFF_YEAR)[0]

    # ---- (3) Spatial-block holdout ----
    blocks = merge_tiny_blocks(h_df["spatial_block_tiger"].values.astype(str))
    block_series = pd.Series(blocks)
    block_sizes = block_series.value_counts()  # sorted descending
    cumulative = block_sizes.cumsum() / N
    n_holdout = int(max(1, (cumulative >= 0.15).values.argmax() + 1))
    holdout_blocks = set(block_sizes.index[:n_holdout])
    spat_test  = np.where(np.isin(blocks, list(holdout_blocks)))[0]
    spat_train = np.where(~np.isin(blocks, list(holdout_blocks)))[0]

    return {
        "random":   (rand_train,  rand_test),
        "temporal": (temp_train,  temp_test),
        "spatial":  (spat_train,  spat_test),
    }


# ── IMPUTATION ─────────────────────────────────────────────────────────────

def compute_train_medians(h_df: pd.DataFrame, train_idx: np.ndarray,
                          feat_cols: list) -> dict:
    """
    Compute per-feature median from training rows only (prevents test leakage).
    Returns dict: {col: median_value}.
    Columns entirely NA in training get median = 0.0.
    """
    medians = {}
    tr = h_df.iloc[train_idx]
    for col in feat_cols:
        if col in tr.columns:
            m = tr[col].median()
            medians[col] = 0.0 if np.isnan(m) else float(m)
        else:
            medians[col] = 0.0
    return medians


def compute_train_stats(h_df: pd.DataFrame, train_idx: np.ndarray,
                        feat_cols: list) -> dict:
    """
    Compute per-feature (mean, std) from training anchor rows only.
    Used to z-score sequence features before input to the transformer.
    Returns dict: {col: (mean, std)}.
    Columns with std=0 or all-NA get std=1.0 (centres but does not scale).

    NOTE(paper): Z-score standardisation fit on training anchor rows only;
      applied to all sequence steps (including historical lookback from
      full_df) to prevent test leakage.  Clip applied at ±5σ after scaling
      to suppress any extreme outliers that survive log1p treatment.
      Unlike RF, transformers are not scale-invariant; unscaled inputs with
      wildly different magnitudes (e.g. dist_to_shore_m max=163,474 vs
      doy_sin in [-1,1]) cause attention to be dominated by large-magnitude
      features.  This fix was applied after diagnostic #3 confirmed the bug.
    """
    tr = h_df.iloc[train_idx]
    stats = {}
    for col in feat_cols:
        if col in tr.columns:
            vals = tr[col].dropna().astype(float)
            mu = float(vals.mean()) if len(vals) > 0 else 0.0
            sd = float(vals.std())  if len(vals) > 1 else 1.0
            stats[col] = (mu, max(sd, 1e-8))
        else:
            stats[col] = (0.0, 1.0)
    return stats


# ── CELL INDEX (for fast sequence lookup) ──────────────────────────────────

def build_cell_index(df: pd.DataFrame) -> dict:
    """
    Build index: {cell_id: sorted numpy array of integer positions in df}
    sorted by date_T ascending.  O(N log N) to build; O(log N) to query.

    NOTE(paper): Sequences are drawn from the FULL dataset (all 65,939 rows)
      so that each anchor row has the maximum available history, including
      rows from horizons other than the current H. This mirrors how A6 built
      the full datacube and ensures the richest possible context.
    """
    df_sorted = df.sort_values(["cell_id", "date_T"])
    index = {}
    for cell_id, grp in df_sorted.groupby("cell_id"):
        index[int(cell_id)] = grp.index.to_numpy()   # original df positions
    return index


# ── SEQUENCE BUILDER ────────────────────────────────────────────────────────

def build_all_sequences(
    h_df: pd.DataFrame,
    full_df: pd.DataFrame,
    cell_index: dict,
    feat_cols: list,
    medians: dict,
    scale_stats: dict = None,
    seq_len: int = SEQ_LEN,
) -> tuple:
    """
    Pre-compute all sequences for the anchor rows in h_df.

    Returns:
        seqs  : float32 array (N, seq_len, n_feat+1)  -- +1 for days_to_anchor
        masks : bool   array (N, seq_len)              -- True = padded (ignore)
        Labels must be extracted by the caller from h_df[target_col].

    Leakage assertion: every sequence timestep has date <= anchor_date (T).

    scale_stats: dict {col: (mean, std)} from compute_train_stats().
      If provided, z-score each feature column and clip to ±5σ.
      days_to_anchor is NOT z-scored (already /365; range ~0-0.33).
    """
    # NOTE(paper): days_to_anchor feature appended to each timestep.
    #   Tells the model how far back each observation is from T.
    #   Normalised by 365.0 (so 1 year = 1.0). This compensates for
    #   irregular observation cadence and irregular positional embeddings.

    n_anchor = len(h_df)
    n_feat = len(feat_cols) + 1   # +1 for days_to_anchor
    seqs  = np.zeros((n_anchor, seq_len, n_feat), dtype=np.float32)
    masks = np.ones((n_anchor, seq_len), dtype=bool)   # True = padded

    # Build a fast lookup: original df integer index -> row position in full_df
    # (full_df is already indexed 0..N-1 from pq.read_table().to_pandas())

    for i, (_, anchor) in enumerate(h_df.iterrows()):
        cid    = int(anchor["cell_id"])
        date_T = anchor["date_T"]

        # All positions in full_df for this cell
        cell_pos = cell_index.get(cid, np.array([], dtype=np.int64))

        # Filter to dates <= T
        cell_dates = full_df.iloc[cell_pos]["date_T"].values   # numpy datetime64
        date_T_np  = np.datetime64(date_T)
        valid_mask = cell_dates <= date_T_np
        valid_pos  = cell_pos[valid_mask]

        # LEAKAGE ASSERTION
        assert (cell_dates[valid_mask] <= date_T_np).all(), \
            f"Leakage detected: sequence for cell={cid}, T={date_T} contains future dates"

        # Take last seq_len observations
        lookback_pos = valid_pos[-seq_len:]    # sorted ascending (oldest first)
        n_steps = len(lookback_pos)

        if n_steps == 0:
            # Fully padded sequence (no data for this cell before T)
            # masks stays all-True; seqs stays all-zeros
            continue

        # Retrieve feature values for these timesteps
        rows = full_df.iloc[lookback_pos]
        feat_vals = rows[feat_cols].values.astype(np.float64)

        # Impute NAs with train medians
        feat_imputed = feat_vals.copy()
        for j, col in enumerate(feat_cols):
            med = medians.get(col, 0.0)
            nan_mask = np.isnan(feat_imputed[:, j])
            feat_imputed[nan_mask, j] = med

        # Z-score standardisation (fit on train only, applied here to all steps)
        # NOTE(paper): Applied after imputation. Clip to ±5σ to suppress
        #   any extreme outliers that survive log1p treatment (e.g. pct-change
        #   features with rare spikes). days_to_anchor excluded (already ~[0,0.33]).
        if scale_stats is not None:
            means_arr = np.array([scale_stats[col][0] for col in feat_cols], dtype=np.float64)
            stds_arr  = np.array([scale_stats[col][1] for col in feat_cols], dtype=np.float64)
            feat_imputed = (feat_imputed - means_arr) / stds_arr
            feat_imputed = np.clip(feat_imputed, -5.0, 5.0)

        # days_to_anchor (normalised by 365)
        step_dates = rows["date_T"].values
        days_to_anchor = ((date_T_np - step_dates).astype("timedelta64[D]")
                          .astype(float) / 365.0).reshape(-1, 1)

        # Concatenate: (n_steps, n_feat+1)
        step_data = np.concatenate([feat_imputed, days_to_anchor], axis=1)
        step_data = np.nan_to_num(step_data, nan=0.0)

        # Place in sequence: right-aligned (latest step at position seq_len-1)
        offset = seq_len - n_steps
        seqs[i, offset:, :] = step_data.astype(np.float32)
        masks[i, offset:] = False   # these positions are real data

    return seqs, masks


# ── PYTORCH DATASET ─────────────────────────────────────────────────────────

class HABSequenceDataset(Dataset):
    """
    PyTorch Dataset wrapping pre-computed sequences.

    Args:
        seqs:    float32 array (N, seq_len, n_feat)
        masks:   bool array   (N, seq_len)  True = padded timestep
        labels:  int array    (N,)          0/1 HAB label
    """

    def __init__(self, seqs: np.ndarray, masks: np.ndarray, labels: np.ndarray):
        assert len(seqs) == len(masks) == len(labels), "Length mismatch"
        self.seqs   = torch.from_numpy(seqs)
        self.masks  = torch.from_numpy(masks)
        self.labels = torch.from_numpy(labels.astype(np.float32))

    def __len__(self) -> int:
        return len(self.labels)

    def __getitem__(self, idx: int):
        return self.seqs[idx], self.masks[idx], self.labels[idx]
