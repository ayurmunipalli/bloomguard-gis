# ============================================================
# FILE: 06_build_datacube.R
# OWNER: A6 datacube (reviewer R6, sonnet-5) — LAST data-integrity gate before modeling
# PURPOSE: Join labels + satellite + environmental features into the sftime datacube;
#          compute TREND features (D11/§8-B); attach T+H labels with a leakage assertion;
#          flatten to model_dataset for Stage 1 and expose per-cell sequences for Stage 2.
# INPUTS:  habsos_labels.parquet, satellite_features.parquet, environmental_features.parquet.
# OUTPUTS: data/processed/datacube.rds (sftime); model_dataset.parquet + .gpkg.
# TECHNIQUES: inner/left joins ON DATE (not one giant outer join); data.table rbindlist;
#             per-cell time-series deltas/%-change/slopes/threshold-flags; T+H label shift;
#             spatial-autocorrelation cluster flag for grouped splits.
# CITATIONS: sftime datacube (mentor's approach, D10); rbindlist (Nov 15 note).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): NO LOOK-AHEAD — every feature/rolling stat computed at or before T; label = T+H.
#              Assert in code: max(feature_timestamp) <= T and label_timestamp == T+H.
# NOTE(paper): trend features are first-class (D11): abs deltas, relative DoD %-change,
#              trailing slopes, threshold-crossing flags, rolling mean/std, spatial gradient.
# NOTE(limitation): %-change guarded with epsilon when x_{T-1} ~ 0 (clear-water chl-a).

stop("TODO(A6 datacube): build cube + trends + T+H labels + leakage assert + flatten. §6-A6/§8-B.")
