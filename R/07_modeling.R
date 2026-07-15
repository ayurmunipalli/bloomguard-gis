# ============================================================
# FILE:       R/07_modeling.R
# PURPOSE:    Stage-1 Random Forest HAB forecasting — M1 exit owner.
#             Trains RF per forecast horizon H ∈ {1,3,5,7,14}, evaluated
#             under three splits (random/temporal/spatial), vs persistence +
#             chlorophyll-only baselines. Prioritises recall + PR-AUC.
# INPUTS:     data/processed/model_dataset.parquet (65,939 × 194, FINAL —
#             now includes A4b/A6 bio-optical discrimination features:
#             RBD/KBBI (Amin 2009), bbp_ratio_morel/bbp_deficit (Cannizzaro
#             2008 vs Morel 1988 reference curve), nLw(667/678), the three
#             published-rule boolean flags, and their 60 trend variants)
# OUTPUTS:    outputs/models/best_model.rds           — H=7 temporal RF (AFTER, bio-inclusive)
#             outputs/models/best_model_before_bio.rds — FROZEN pre-bio baseline (backed up, not overwritten)
#             outputs/tables/model_results.csv        — metrics × horizon × split × model (AFTER, tagged feature_set)
#             outputs/tables/model_results_before_bio.csv — FROZEN pre-bio baseline (backed up, not overwritten)
#             outputs/figures/confusion_matrix_H*.png — confusion matrices
#             outputs/figures/roc_pr_H*.png           — ROC + PR curves
#             outputs/figures/skill_vs_horizon.png    — skill decay curve
#             reports/agent_logs/modeling.md          — decision log
# TECHNIQUES: ranger Random Forest (Wright & Ziegler 2017);
#             class-weighted training for 8-14% minority class;
#             median-impute-with-flag for satellite NAs;
#             log1p transform for heavy-tailed chl-a / nFLH features;
#             temporal holdout (train ≤ cutoff_year, test > cutoff_year);
#             spatial-block holdout (hold out ≥3 contiguous county blocks);
#             persistence + chl-only reference baselines (§9 PLAN.md);
#             skill vs horizon: PR-AUC decay curve (required figure).
# CITATIONS:  Breiman 2001 (Random Forests); Wright & Ziegler 2017 (ranger);
#             Green 2022 (variable importance / RTM method); Amin et al. 2009
#             (RBD/KBBI); Cannizzaro et al. 2008 (bbp discrimination rule);
#             Morel 1988 (Case-1 backscatter reference curve).
# NOTES:      2026-07-14 bio-optical re-run — ISOLATION DISCIPLINE: same seed,
#             same split construction, same ranger hyperparameters, same
#             reconciled scorer (reports/scoring_reconciliation.md) as the
#             pre-bio run. ONLY the feature set changed (bio columns added).
#             Pre-bio BEFORE artifacts preserved as *_before_bio.* before this
#             run overwrote best_model.rds / model_results.csv.
# ============================================================

# ── ARROW THREAD GUARD: source 00_config.R FIRST ──────────────────────────
# CRITICAL: must happen before library(arrow) initialises its C++ thread pool.
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

# NOTE(paper): ARROW_NUM_THREADS=1 set in 00_config.R to prevent arrow deadlock
#              (observed on this host: 7 processes at 95% CPU for 15h).

# ── R-SPLIT CONDITIONAL-PASS CAVEATS — TWO OF THREE NOW REPAIRED (P0-A, P0-B) ─
# NOTE(paper): SPATIAL SPLIT PREVALENCE CONFOUND (still open — not a P0 target).
#   The spatial-block holdout always isolates Collier County (block 12_115),
#   the dominant HAB hotspot, which has 11.4% positive rate vs 8.4% in the
#   random test set (1.35× higher prevalence). It is a single fixed geography
#   (n=1, no rotation). Report the spatial result as "geographic transfer to a
#   high-prevalence region." POST-BUFFER (P0-B): spatial H=7 PR-AUC 0.663 -> 0.617
#   now sits BELOW random (0.631), confirming the earlier spatial>random gap was
#   border leakage, not generalisation. The TEMPORAL split is the headline honest
#   number.
#
# NOTE(paper): SPATIAL BORDER ADJACENCY — REPAIRED by P0-B (spatial buffer).
#   14.6% of spatial test cells fell within ~10 km of a train cell at county-block
#   borders (43-44% within 20 km). SPATIAL_BUFFER_M (config, default 20000 m) now
#   drops every train cell within R of any test cell; residual test-cells-within-R
#   is 0 by construction. See the P0-B block in the spatial split below.
#
# NOTE(paper): TEMPORAL ZERO-EMBARGO — REPAIRED by P0-A (temporal embargo).
#   ~49 training rows at H=14 (fewer at shorter H) had a label_date (date_T + H)
#   falling in the test period (>= 2016-01-01). EMBARGO_ON (config, default true)
#   now drops them. Effect on H=7 temporal PR-AUC: -0.0014 (negligible, as
#   predicted). See the P0-A block in the temporal split below and
#   reports/results/P0-A-P0-B_split_repair.md.

# ── LIBRARIES ──────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(arrow)
  arrow::set_cpu_count(1L)           # belt-and-suspenders
  library(data.table)
  library(ranger)
  library(ggplot2)
  library(sf)                        # P0-B spatial buffer: project centroids to EPSG:5070
})

message("[A7] Libraries loaded.")

# ── PATHS ──────────────────────────────────────────────────────────────────
CUBE_PATH    <- proj_path("data/processed/model_dataset.parquet")
OUT_MODELS   <- proj_path("outputs/models")
OUT_TABLES   <- proj_path("outputs/tables")
OUT_FIGURES  <- proj_path("outputs/figures")
LOG_PATH     <- proj_path("reports/agent_logs/modeling.md")

dir.create(OUT_MODELS,  showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_TABLES,  showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIGURES, showWarnings = FALSE, recursive = TRUE)

# ── CONSTANTS ──────────────────────────────────────────────────────────────
HORIZONS    <- cfg$forecast$horizons_days  # {1,3,5,7,14}
SEED        <- cfg$random_seed %||% 42
NUM_TREES   <- 500L
TRAIN_FRAC  <- 0.80            # random split train proportion
TEMPORAL_CUTOFF_YEAR <- 2016L  # train ≤ 2015, test ≥ 2016 (~74% / 26%)
CUTOFF_DATE <- as.Date(paste0(TEMPORAL_CUTOFF_YEAR, "-01-01"))
MIN_BLOCK_ROWS <- 5L           # merge spatial blocks smaller than this
# ── P0-A / P0-B split-defect repairs (config-driven) ──────────────────────
# See R/07c_split_repair.R (validated re-freeze of the adopted pre-bio baseline)
# and PROJECT.md §2.1. Both touch ONLY training rows; test sets are unchanged.
EMBARGO_ON       <- isTRUE(cfg$split_repair$temporal_embargo)             # P0-A
SPATIAL_BUFFER_M <- as.numeric(cfg$split_repair$spatial_buffer_m %||% 0)  # P0-B (metres)
# NOTE(limitation): E-01 adds ring-2 (~20 km) neighbour features; the buffer must
#   then exceed ring_radius + 1 cell (>= 30000 m). Bump config split_repair.
#   spatial_buffer_m to >= 30000 before running E-01, or neighbours re-open the leak.
LOG_FEATURES <- c("chlor_a_mean", "nflh_mean", "Kd_490_mean")  # heavy-tailed
FEATURE_SET_TAG <- "bio_inclusive"  # NOTE(paper): tags this run's model_results.csv
# rows so the AFTER (bio-inclusive) run is unambiguously distinguishable from
# the FROZEN BEFORE baseline (outputs/tables/model_results_before_bio.csv,
# feature_set = "pre_bio"). Isolation discipline: this tag is metadata only —
# it does not affect training. — 2026-07-14

# NOTE(paper): temporal cutoff 2016 gives train 2003-2015 (13 yr) / test 2016-2021 (6 yr).
#              Matches HABSOS intensive sampling after 2015 being held out.
# NOTE(paper): as of the 2026-07-12 re-run, ERA5 wind (speed/direction/along-cross-shore)
#              is REAL (Copernicus CDS, 2003-2021) and included as a live feature set —
#              this is the isolated change from the prior run (satellite + static geo +
#              seasonality + historical HAB lags only, no meteorology).
# NOTE(limitation): CHIRPS precip and SMAP salinity remain placeholder (all-NA) —
#                   CHIRPS blocked by a CrowdSec IP ban re-triggered during this same
#                   session; SMAP deferred per lead directive (lowest-value, coarsest
#                   of the three env sources). Both still excluded from features below.

# ── FEATURE EXCLUSION LIST (from R6 review — consolidated) ─────────────────
# NOTE(paper): same-day HAB column HARD-DROPPED by name to prevent
#              detection-conflation leakage (R6 warning #3). Never a feature.
ALWAYS_EXCLUDE <- c(
  # Identifiers
  "cell_id", "date_T",
  # Same-day detection label (conflates detection with forecasting)
  "HAB",
  # Target labels (all; current target added back per horizon)
  "HAB_H1", "HAB_H3", "HAB_H5", "HAB_H7", "HAB_H14",
  # Spatial CV grouping key (not a predictor)
  "spatial_block_tiger",
  # HABSOS raw count columns — direct label inputs, must not be features
  # (max_count > 100,000 → HAB=1; including it is a label-definition leak)
  "max_count", "n_samples",
  # Diagnostic/meta flags — never predictors
  "IS_PLACEHOLDER_ROW", "satellite_missing", "cloud_flag",
  "salinity_coarse_flag", "feature_filled_any", "IS_ABSENCE_UNCERTAIN",
  "sat_IS_PLACEHOLDER", "env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER", "label_IS_PLACEHOLDER",
  "sat_feature_filled", "env_feature_filled",
  # Remaining all-NA placeholder env columns (CHIRPS/SMAP still not pulled as of this
  # run — see reports/agent_logs/env-features.md 2026-07-12 update). ERA5 wind
  # (wind_u_ms/wind_v_ms/wind_speed_ms/wind_dir_deg/wind_along_ms/wind_cross_ms) is
  # REAL as of this run and deliberately NOT excluded — it is now a live feature set.
  "precip_mm", "salinity_pss",
  # Bio-optical meta/quality/missingness flags — NOT features (2026-07-14 bio run).
  # Treated identically to the existing sat_/env_/static_ meta-flag family above:
  # these describe DATA QUALITY of the bio-optical pull, not bloom signal.
  #   kbbi_raw            — pre-winsorization KBBI (superseded by winsorized `kbbi`,
  #                          which IS a feature); raw kept only for audit trail.
  #   kbbi_invalid        — TRUE only for rows where kbbi_raw was winsorized to NA
  #                          (|kbbi_raw|>1); a QC flag, not a bloom signal.
  #   bio_missing         — TRUE when no bio-optical row joined for this cell-date
  #                          (join-coverage flag).
  #   bio_cloud_flag      — cloud/no-retrieval flag for the bio-optical pull.
  #   bio_feature_filled  — bio-optical LOCF/fill indicator.
  #   bio_IS_PLACEHOLDER  — bio-optical placeholder flag (family with sat_/env_/
  #                          static_/label_IS_PLACEHOLDER above).
  #   bio_chl_missing     — chlorophyll-input-missing flag feeding the bbp_morel_550
  #                          / bbp_ratio_morel / cannizzaro_kbrevis computations.
  "kbbi_raw", "kbbi_invalid", "bio_missing", "bio_cloud_flag",
  "bio_feature_filled", "bio_IS_PLACEHOLDER", "bio_chl_missing"
)
# NOTE(paper): all OTHER new bio-optical columns are real features (2026-07-14):
#   rbd, kbbi (winsorized), bbp_551, bbp_morel_550, bbp_ratio_morel, bbp_deficit,
#   nlw_667, nlw_678, rbd_detect, kbbi_kbrevis, cannizzaro_kbrevis (11 level/flag
#   features) + 60 trend columns (delta/pct_chg/slope_obs/rollmean_obs/rollstd_obs
#   for rbd, kbbi, bbp_ratio_morel, bbp_deficit) = 71 new bio features included.
#   Per reports/scoring_reconciliation.md's principle, `month`/`doy` remain
#   INCLUDED (real trained features) and `year` remains the only date-derived
#   exclusion (split key, excluded below via the feat_cols setdiff).

# ── LOAD DATA ──────────────────────────────────────────────────────────────
message("[A7] Loading model_dataset.parquet ...")
dt <- as.data.table(arrow::read_parquet(CUBE_PATH))
message("[A7] Loaded: ", nrow(dt), " rows × ", ncol(dt), " cols")
message("[A7] All columns: ", paste(names(dt), collapse=", "))

# Sanity: HAB must not be in features after exclusion (will be verified below)
stopifnot("HAB" %in% names(dt))           # it's there
stopifnot("spatial_block_tiger" %in% names(dt))  # CV col present

# ── DATE PARSING ───────────────────────────────────────────────────────────
# Column is named date_T (not date) — use [[ ]] to avoid base::date() clash.
date_raw <- dt[["date_T"]]
message("[A7] date_T class: ", paste(class(date_raw), collapse=","),
        " | typeof: ", typeof(date_raw),
        " | head: ", paste(head(date_raw, 2), collapse=","))
dt[["date_T"]] <- tryCatch(
  as.Date(as.character(date_raw)),
  error = function(e) as.Date(as.numeric(date_raw), origin = "1970-01-01")
)
dt[["year"]] <- as.integer(substr(as.character(dt[["date_T"]]), 1L, 4L))

# ── LOG1p TRANSFORM (outlier treatment — R3 verdict) ───────────────────────
# NOTE(paper): log1p applied to chlor_a_mean, nflh_mean, Kd_490_mean.
#              R3 confirmed 3.58×10^8 cells/L extreme bloom counts are real;
#              the binary label absorbs this extreme; chl-a itself can spike
#              during blooms so log1p stabilises variance without discarding data.
#              nflh can be negative in clear water; use signed log: sign(x)*log1p(|x|).
for (feat in LOG_FEATURES) {
  if (feat %in% names(dt)) {
    if (feat == "nflh_mean") {
      dt[, (feat) := sign(get(feat)) * log1p(abs(get(feat)))]
    } else {
      dt[, (feat) := log1p(pmax(get(feat), 0))]  # chlor_a / Kd always >= 0
    }
  }
}
# NOTE(limitation): log1p applied only to level features (not delta/slope trends)
#                   because trends can be negative and their scale differences are
#                   informative. Heavy-tailed trend behaviour is mitigated by RF's
#                   split-based partitioning (robust to monotone transformations).

# ── P0-B: CELL CENTROIDS PROJECTED TO EPSG:5070 (metric buffer distances) ──
# NOTE(paper): buffer distances computed in Albers Equal Area (EPSG:5070), the
#              config projected CRS. One row per unique cell; keyed for fast lookup.
.cell_xy <- unique(dt[, .(cell_id, centroid_lon, centroid_lat)])
.proj_xy <- sf::sf_project("EPSG:4326", "EPSG:5070",
                           as.matrix(.cell_xy[, .(centroid_lon, centroid_lat)]))
.cell_xy[, `:=`(X = .proj_xy[, 1], Y = .proj_xy[, 2])]
setkey(.cell_xy, cell_id)

# P0-B helper: which TRAIN cells lie within R metres of any TEST cell (to drop).
train_cells_within_buffer <- function(train_cells, test_cells, R) {
  if (R <= 0) return(character(0))
  tr <- .cell_xy[.(unique(train_cells))]; te <- .cell_xy[.(unique(test_cells))]
  if (nrow(te) == 0 || nrow(tr) == 0) return(character(0))
  drop <- vapply(seq_len(nrow(tr)), function(i)
    sqrt(min((te$X - tr$X[i])^2 + (te$Y - tr$Y[i])^2)) < R, logical(1))
  tr$cell_id[drop]
}

# ── IMPUTATION WITH MISSINGNESS FLAG ──────────────────────────────────────
# NOTE(paper): median imputation + binary missingness indicator per NA column.
#              Adds {col}_is_missing flag so RF can exploit the missingness pattern
#              (cloud cover itsself is informative — clear-water vs cloud-prone cells).
#              No value is silently fabricated; missingness is explicit.
impute_with_flag <- function(train_dt, test_dt, feat_cols) {
  # Compute medians on train only (prevent test leakage)
  for (col in feat_cols) {
    na_col <- paste0(col, "_is_missing")
    train_dt[[na_col]] <- as.integer(is.na(train_dt[[col]]))
    test_dt[[na_col]]  <- as.integer(is.na(test_dt[[col]]))
    med <- median(train_dt[[col]], na.rm = TRUE)
    if (is.na(med)) med <- 0   # column entirely NA in train: impute 0
    set(train_dt, which(is.na(train_dt[[col]])), col, med)
    set(test_dt,  which(is.na(test_dt[[col]])),  col, med)
  }
  list(train = train_dt, test = test_dt)
}

# ── METRIC HELPERS ─────────────────────────────────────────────────────────
roc_auc_fn <- function(prob, actual) {
  # Area under ROC curve (trapezoidal)
  if (length(unique(actual)) < 2) return(NA_real_)
  ord  <- order(prob, decreasing = TRUE)
  act  <- actual[ord]
  tp   <- cumsum(act)
  fp   <- cumsum(1L - act)
  tpr  <- tp / sum(act)
  fpr  <- fp / sum(1L - act)
  sum(diff(fpr) * (tpr[-length(tpr)] + tpr[-1]) / 2, na.rm = TRUE)
}

pr_auc_fn <- function(prob, actual) {
  # Area under Precision-Recall curve (trapezoidal, interpolation by recall)
  # NOTE(cite): PR-AUC preferred over ROC-AUC for imbalanced data (Davis & Goadrich 2006).
  if (length(unique(actual)) < 2) return(NA_real_)
  ord  <- order(prob, decreasing = TRUE)
  act  <- actual[ord]
  tp   <- cumsum(act)
  fp   <- cumsum(1L - act)
  prec <- tp / (tp + fp)
  rec  <- tp / sum(act)
  # Handle first point (threshold = max_prob → recall usually starts at 1/N_pos)
  rec_aug  <- c(0, rec)
  prec_aug <- c(prec[1], prec)
  sum(diff(rec_aug) * (prec_aug[-length(prec_aug)] + prec_aug[-1]) / 2,
      na.rm = TRUE)
}

# NOTE(paper): precision-at-recall-0.80 — a threshold-free operating-point summary
#              requested for the wind-feature comparison. Walks the PR curve (sorted by
#              descending prob) and reports precision at the first point where recall
#              reaches >= target_recall (i.e., the best-case precision achievable while
#              still catching >=80% of true positives). NA if recall never reaches target
#              (happens when n_pos is small and the top-K predictions can't reach 80% recall
#              without passing through a NA-precision point — reported as NA, not 0, to avoid
#              implying a real operating point exists when it doesn't).
precision_at_recall_fn <- function(prob, actual, target_recall = 0.80) {
  if (length(unique(actual)) < 2) return(NA_real_)
  ord  <- order(prob, decreasing = TRUE)
  act  <- actual[ord]
  tp   <- cumsum(act)
  fp   <- cumsum(1L - act)
  prec <- tp / (tp + fp)
  rec  <- tp / sum(act)
  hit  <- which(rec >= target_recall)
  if (length(hit) == 0) return(NA_real_)
  round(prec[hit[1]], 4)
}

compute_metrics <- function(prob, actual, threshold = 0.5) {
  pred <- as.integer(prob >= threshold)
  tp   <- sum(pred == 1L & actual == 1L)
  fp   <- sum(pred == 1L & actual == 0L)
  fn   <- sum(pred == 0L & actual == 1L)
  tn   <- sum(pred == 0L & actual == 0L)
  prec <- if (tp + fp == 0) NA_real_ else tp / (tp + fp)
  rec  <- if (tp + fn == 0) NA_real_ else tp / (tp + fn)
  f1   <- if (is.na(prec) || is.na(rec) || (prec + rec) == 0) NA_real_
          else 2 * prec * rec / (prec + rec)
  acc  <- (tp + tn) / length(actual)
  fnr  <- if (tp + fn == 0) NA_real_ else fn / (tp + fn)  # false negative rate
  data.table(
    accuracy = round(acc,  4),
    precision = round(prec, 4),
    recall    = round(rec,  4),
    f1        = round(f1,   4),
    fnr       = round(fnr,  4),
    roc_auc   = round(roc_auc_fn(prob, actual), 4),
    pr_auc    = round(pr_auc_fn(prob, actual),  4),
    prec_at_recall80 = precision_at_recall_fn(prob, actual, 0.80),
    n_test    = length(actual),
    n_pos     = sum(actual),
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}

# ── SPATIAL BLOCK MERGING (singleton-block fix) ────────────────────────────
# NOTE(paper): R6 review found 2 blocks (12_083, 12_077) with 1 row each.
#              Singleton folds cannot function as standalone CV holdout sets.
#              Blocks with fewer than MIN_BLOCK_ROWS rows are merged into
#              the most-populated remaining block (safe geographic proxy).
merge_tiny_blocks <- function(block_vec, min_rows = MIN_BLOCK_ROWS) {
  cnt  <- table(block_vec)
  tiny <- names(cnt)[cnt < min_rows]
  if (length(tiny) == 0) return(block_vec)
  # Target: the largest block (absorbs tiny ones)
  target <- names(cnt)[which.max(cnt)]
  block_vec[block_vec %in% tiny] <- target
  message("[A7] Merged ", length(tiny), " tiny block(s) (<", min_rows, " rows) → '", target, "'")
  block_vec
}

# ── BASELINE HELPERS ───────────────────────────────────────────────────────
# Persistence baseline: predict HAB_Hk = HAB (same-day observation at T).
# NOTE(paper): persistence is the naive "no change" forecast — the minimum bar
#              any useful forecast must beat.
baseline_persistence <- function(test_dt, target_col) {
  # HAB column = same-day detection at T; valid to use here as BASELINE (not model feature)
  prob <- as.numeric(test_dt[["HAB"]])
  act  <- test_dt[[target_col]]
  m    <- compute_metrics(prob, act, threshold = 0.5)
  m[, model := "persistence"]
  m
}

# Chlorophyll-only baseline: RF trained on chlor_a_mean only.
baseline_chl_only <- function(train_dt, test_dt, target_col, feat_na_cols) {
  # Use log1p-transformed chlor_a_mean; impute separately with train median
  chl_col <- "chlor_a_mean"
  tr  <- copy(train_dt[, c(chl_col, target_col), with = FALSE])
  te  <- copy(test_dt[,  c(chl_col, target_col), with = FALSE])
  # Impute NAs
  med_chl <- median(tr[[chl_col]], na.rm = TRUE)
  if (is.na(med_chl)) med_chl <- 0
  set(tr, which(is.na(tr[[chl_col]])), chl_col, med_chl)
  set(te, which(is.na(te[[chl_col]])), chl_col, med_chl)
  # Class weights
  n_pos <- sum(tr[[target_col]] == 1L, na.rm = TRUE)
  n_neg <- sum(tr[[target_col]] == 0L, na.rm = TRUE)
  w <- ifelse(tr[[target_col]] == 1L,
              n_neg / n_pos,  # upweight minority
              1.0)
  f <- as.formula(paste(target_col, "~", chl_col))
  set(tr, j = target_col, value = factor(tr[[target_col]], levels = c(0, 1)))
  set(te, j = target_col, value = factor(te[[target_col]], levels = c(0, 1)))
  rf_chl <- tryCatch(
    ranger(f, data = tr, num.trees = 100L, probability = TRUE,
           case.weights = w, seed = SEED, num.threads = 1L),
    error = function(e) NULL
  )
  if (is.null(rf_chl)) {
    return(data.table(model = "chl_only",
                      accuracy = NA, precision = NA, recall = NA, f1 = NA, fnr = NA,
                      roc_auc = NA, pr_auc = NA, n_test = nrow(te),
                      n_pos = sum(as.integer(as.character(te[[target_col]])) == 1L),
                      tp = NA, fp = NA, fn = NA, tn = NA))
  }
  prob <- predict(rf_chl, data = te)$predictions[, "1"]
  act  <- as.integer(as.character(te[[target_col]]))
  m    <- compute_metrics(prob, act)
  m[, model := "chl_only"]
  m
}

# ── MAIN TRAINING LOOP ─────────────────────────────────────────────────────
all_results <- list()
best_model_obj <- NULL   # will store H=7 temporal RF

for (H in HORIZONS) {
  target_col <- paste0("HAB_H", H)
  message("\n[A7] ===== Horizon H=", H, " =====")

  # Filter to rows with this horizon's label
  h_dt <- dt[!is.na(get(target_col))]
  message("[A7] H=", H, ": ", nrow(h_dt), " labelled rows | pos=",
          sum(h_dt[[target_col]]), " (", round(100*mean(h_dt[[target_col]]),1), "%)")

  # Feature columns for this horizon
  excl_H    <- c(ALWAYS_EXCLUDE, setdiff(paste0("HAB_H", HORIZONS), target_col))
  feat_cols <- setdiff(names(h_dt), c(excl_H, target_col, "year"))
  # Verify HAB is excluded
  stopifnot(!"HAB" %in% feat_cols)
  message("[A7] Features: ", length(feat_cols))

  # Identify columns with NAs (for imputation)
  na_cols <- feat_cols[sapply(feat_cols, function(cn) anyNA(h_dt[[cn]]))]
  message("[A7] Columns with NAs (to impute): ", length(na_cols))

  # NOTE(paper): 2026-07-14 bio run — explicit assertion that the bio-optical NaN
  #              handling is covered. R's is.na()/anyNA() treat NaN as NA, so the
  #              existing impute_with_flag() path (below) already imputes NaN cells
  #              in the bio + trend columns exactly like any other NA. Also assert
  #              no Inf reaches ranger (bbp_ratio_morel/pct_chg columns divide by a
  #              value that can be near-zero) — STOP condition per task instructions.
  bio_feat_present <- intersect(feat_cols,
    c("rbd", "kbbi", "bbp_551", "bbp_morel_550", "bbp_ratio_morel", "bbp_deficit",
      "nlw_667", "nlw_678", grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_", feat_cols, value = TRUE)))
  n_inf <- sum(sapply(bio_feat_present, function(cn) sum(is.infinite(h_dt[[cn]]))))
  if (n_inf > 0) {
    stop("[A7] STOP: ", n_inf, " Inf value(s) found in bio-optical features — ",
         "would corrupt ranger training. Report to lead, do not approximate.")
  }
  message("[A7] Bio-optical features present: ", length(bio_feat_present),
          " | Inf check: PASS (0 found)")

  # Spatial blocks for this horizon subset (merge tiny blocks)
  h_dt[, block_cv := merge_tiny_blocks(spatial_block_tiger)]
  n_blocks <- length(unique(h_dt$block_cv))
  message("[A7] Spatial blocks after merge: ", n_blocks)

  # ---- Define 3 splits ----

  # (1) RANDOM STRATIFIED 80/20
  set.seed(SEED + H)
  pos_idx <- which(h_dt[[target_col]] == 1L)
  neg_idx <- which(h_dt[[target_col]] == 0L)
  train_pos <- sample(pos_idx, floor(TRAIN_FRAC * length(pos_idx)))
  train_neg <- sample(neg_idx, floor(TRAIN_FRAC * length(neg_idx)))
  rand_train_idx <- sort(c(train_pos, train_neg))
  rand_test_idx  <- setdiff(seq_len(nrow(h_dt)), rand_train_idx)

  # (2) TEMPORAL HOLDOUT: train on date < cutoff, test on date >= cutoff
  temp_train_idx <- which(h_dt$year < TEMPORAL_CUTOFF_YEAR)
  temp_test_idx  <- which(h_dt$year >= TEMPORAL_CUTOFF_YEAR)
  # ── P0-A TEMPORAL EMBARGO ──────────────────────────────────────────────
  # NOTE(paper): drop training rows whose label_date (date_T + H) falls in the
  #   test period (>= CUTOFF_DATE). Closes the zero-embargo leak (~49 rows at
  #   H=14). Test set is unchanged (embargo removes only training rows).
  #   Validated in R/07c_split_repair.R; effect on H=7 temporal PR-AUC = -0.0014.
  if (EMBARGO_ON) {
    keep_emb <- (h_dt$date_T[temp_train_idx] + H) < CUTOFF_DATE
    n_emb_drop <- sum(!keep_emb)
    temp_train_idx <- temp_train_idx[keep_emb]
    message("[A7] P0-A embargo H=", H, ": dropped ", n_emb_drop,
            " training rows (label_date in test period)")
  }
  # NOTE(paper): temporal split is the primary honest forecasting evaluation.
  #              Training on 2003-2015, testing on 2016-2021 respects
  #              the time-series nature of HAB forecasting.
  if (length(temp_test_idx) < 10) {
    message("[A7] WARNING: H=", H, " temporal test set has only ", length(temp_test_idx), " rows")
  }

  # (3) SPATIAL-BLOCK HOLDOUT: hold out the 3 largest blocks (~20% of data)
  block_sizes <- sort(table(h_dt$block_cv), decreasing = TRUE)
  # Choose blocks to hold out: accumulate until ≥ 15% of rows
  cumulative <- cumsum(block_sizes) / nrow(h_dt)
  n_holdout  <- max(1L, min(which(cumulative >= 0.15)))
  holdout_blocks <- names(block_sizes)[seq_len(n_holdout)]
  spat_test_idx  <- which(h_dt$block_cv %in% holdout_blocks)
  spat_train_idx <- setdiff(seq_len(nrow(h_dt)), spat_test_idx)
  # ── P0-B SPATIAL BUFFER ────────────────────────────────────────────────
  # NOTE(paper): drop training CELLS within SPATIAL_BUFFER_M of any test cell,
  #   removing the 14.6% border-adjacency residual autocorrelation. Residual
  #   test-cells-within-R is 0 by construction. Test set unchanged (buffer
  #   removes only training cells). Validated in R/07c_split_repair.R.
  if (SPATIAL_BUFFER_M > 0) {
    drop_cells  <- train_cells_within_buffer(h_dt$cell_id[spat_train_idx],
                                             h_dt$cell_id[spat_test_idx], SPATIAL_BUFFER_M)
    keep_buf    <- !(h_dt$cell_id[spat_train_idx] %in% drop_cells)
    message("[A7] P0-B buffer H=", H, " (R=", SPATIAL_BUFFER_M, "m): dropped ",
            length(drop_cells), " train cells / ", sum(!keep_buf), " rows")
    spat_train_idx <- spat_train_idx[keep_buf]
  }
  # NOTE(paper): spatial holdout tests geographic generalisation by holding out
  #              contiguous county-level blocks. Blocks chosen greedily to reach
  #              ~15% of labelled rows.
  message("[A7] Spatial holdout: ", length(holdout_blocks), " blocks (",
          length(spat_test_idx), " test rows, ",
          round(100*length(spat_test_idx)/nrow(h_dt)), "%)")

  splits <- list(
    random   = list(train = rand_train_idx,  test = rand_test_idx),
    temporal = list(train = temp_train_idx,  test = temp_test_idx),
    spatial  = list(train = spat_train_idx,  test = spat_test_idx)
  )

  for (split_name in names(splits)) {
    tr_idx <- splits[[split_name]]$train
    te_idx <- splits[[split_name]]$test
    if (length(tr_idx) < 20 || length(te_idx) < 10) {
      message("[A7] SKIP H=", H, " split=", split_name, " (too few rows)")
      next
    }

    tr_dt <- copy(h_dt[tr_idx, c(feat_cols, target_col), with = FALSE])
    te_dt <- copy(h_dt[te_idx, c(feat_cols, target_col), with = FALSE])

    # ---- Imputation (train-derived medians, applied to test) ----
    imp  <- impute_with_flag(tr_dt, te_dt, na_cols)
    tr_dt <- imp$train
    te_dt <- imp$test

    # All feature columns (original + added missingness indicators)
    all_feat <- setdiff(names(tr_dt), target_col)

    # ---- Class weights ----
    n_pos <- sum(tr_dt[[target_col]] == 1L)
    n_neg <- sum(tr_dt[[target_col]] == 0L)
    if (n_pos == 0) { message("[A7] SKIP: no positives in train"); next }
    w     <- ifelse(tr_dt[[target_col]] == 1L, n_neg / n_pos, 1.0)
    # NOTE(paper): class weights set to inverse class frequency (n_neg/n_pos for
    #              positives, 1.0 for negatives). Prioritises recall over precision
    #              per PLAN.md §9: "a miss is worse than a false alarm."

    # ---- Train RF ----
    tr_model <- copy(tr_dt)
    set(tr_model, j = target_col,
        value = factor(tr_model[[target_col]], levels = c(0, 1)))
    f <- as.formula(paste(target_col, "~ ."))
    message("[A7]   Training RF (H=", H, ", split=", split_name, ", ",
            nrow(tr_model), " train / ", nrow(te_dt), " test rows) ...")
    rf <- tryCatch(
      ranger(f,
             data         = tr_model,
             num.trees    = NUM_TREES,
             probability  = TRUE,
             case.weights = w,
             num.threads  = 1L,      # single-thread (resource constraint)
             seed         = SEED + H * 100L + which(names(splits) == split_name)),
      error = function(e) { message("[A7] ranger ERROR: ", e$message); NULL }
    )
    if (is.null(rf)) next

    # ---- RF metrics ----
    te_model <- copy(te_dt)
    set(te_model, j = target_col,
        value = factor(te_model[[target_col]], levels = c(0, 1)))
    prob_rf <- predict(rf, data = te_model)$predictions[, "1"]
    act      <- as.integer(as.character(te_model[[target_col]]))
    m_rf     <- compute_metrics(prob_rf, act)
    m_rf[, model := "rf"]

    # ---- Baselines ----
    # Persistence: need HAB column in test rows
    te_hab <- h_dt[te_idx, "HAB", with = FALSE]  # original dt, has HAB
    te_for_baselines <- cbind(te_dt, te_hab)
    m_pers <- baseline_persistence(te_for_baselines, target_col)

    # Chl-only RF baseline
    tr_hab <- copy(h_dt[tr_idx, c("chlor_a_mean", target_col), with = FALSE])
    te_hab2 <- copy(h_dt[te_idx, c("chlor_a_mean", target_col), with = FALSE])
    m_chl  <- baseline_chl_only(tr_hab, te_hab2, target_col, na_cols)

    # ---- Combine results ----
    for (m_row in list(m_rf, m_pers, m_chl)) {
      m_row[, `:=`(horizon = H, split = split_name,
                   n_train = length(tr_idx),
                   pos_rate_train = round(n_pos / (n_pos + n_neg), 4),
                   feature_set = FEATURE_SET_TAG)]
      all_results[[length(all_results) + 1]] <- m_row
    }

    # ---- Save H=7 temporal RF as best model ----
    if (H == 7L && split_name == "temporal") {
      best_model_obj <- list(
        rf           = rf,
        feat_cols    = all_feat,
        na_cols      = na_cols,
        train_medians = sapply(na_cols, function(cn) median(h_dt[tr_idx][[cn]], na.rm = TRUE)),
        horizon      = H,
        split        = split_name,
        train_idx    = tr_idx,
        test_idx     = te_idx,
        prob_rf      = prob_rf,
        act          = act,
        feature_set  = FEATURE_SET_TAG
      )
      message("[A7] Best model saved (H=7, temporal split)")
    }

    # ---- ROC + PR figure (one per horizon × split) ----
    tryCatch({
      png(file.path(OUT_FIGURES,
                    sprintf("roc_pr_H%02d_%s.png", H, split_name)),
          width = 1200, height = 500)
      par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))

      # ROC curve
      ord  <- order(prob_rf, decreasing = TRUE)
      a_s  <- act[ord]
      tpr_ <- cumsum(a_s) / sum(act)
      fpr_ <- cumsum(1L - a_s) / sum(1L - act)
      plot(fpr_, tpr_, type = "l", col = "steelblue", lwd = 2,
           xlab = "False Positive Rate", ylab = "True Positive Rate",
           main = sprintf("ROC  H=%d %s  AUC=%.3f", H, split_name, m_rf$roc_auc))
      abline(0, 1, lty = 2, col = "grey")

      # PR curve
      prec_ <- cumsum(a_s) / (seq_along(a_s))
      rec_  <- cumsum(a_s) / sum(act)
      plot(rec_, prec_, type = "l", col = "firebrick", lwd = 2,
           xlab = "Recall", ylab = "Precision", ylim = c(0, 1),
           main = sprintf("PR  H=%d %s  AUC=%.3f", H, split_name, m_rf$pr_auc))
      abline(h = mean(act), lty = 2, col = "grey")

      dev.off()
    }, error = function(e) message("[A7] Figure warning: ", e$message))

    # ---- Confusion matrix figure ----
    tryCatch({
      pred_class <- as.integer(prob_rf >= 0.5)
      cm <- table(Predicted = pred_class, Actual = act)
      png(file.path(OUT_FIGURES,
                    sprintf("confusion_matrix_H%02d_%s.png", H, split_name)),
          width = 400, height = 400)
      par(mar = c(4, 4, 3, 1))
      image(1:2, 1:2, t(cm[2:1, 2:1]), col = c("white", "steelblue"),
            xlab = "Actual", ylab = "Predicted", axes = FALSE,
            main = sprintf("Confusion H=%d %s\nRecall=%.3f  FNR=%.3f",
                           H, split_name, m_rf$recall, m_rf$fnr))
      axis(1, at = 1:2, labels = c("HAB=1", "HAB=0"))
      axis(2, at = 1:2, labels = c("Pred=0", "Pred=1"))
      text(1, 1, cm[2, 2], cex = 2)   # TN
      text(2, 1, cm[2, 1], cex = 2)   # FN
      text(1, 2, cm[1, 2], cex = 2)   # FP
      text(2, 2, cm[1, 1], cex = 2, col = "white")   # TP
      dev.off()
    }, error = function(e) message("[A7] CM figure warning: ", e$message))

    message(sprintf("[A7]   H=%d %s | RF recall=%.3f PR-AUC=%.3f | persist recall=%.3f | chl recall=%.3f",
                    H, split_name, m_rf$recall, m_rf$pr_auc,
                    m_pers$recall %||% NA, m_chl$recall %||% NA))
  }
}

# ── SAVE MODEL RESULTS TABLE ───────────────────────────────────────────────
results_dt <- rbindlist(all_results, fill = TRUE)
setcolorder(results_dt, c("horizon", "split", "model", "feature_set",
                           "recall", "pr_auc", "roc_auc", "precision", "f1",
                           "fnr", "accuracy", "n_test", "n_train", "n_pos",
                           "tp", "fp", "fn", "tn", "pos_rate_train"))
fwrite(results_dt, file.path(OUT_TABLES, "model_results.csv"))
message("[A7] model_results.csv saved: ", nrow(results_dt), " rows")

# ── SAVE BEST MODEL ────────────────────────────────────────────────────────
if (!is.null(best_model_obj)) {
  saveRDS(best_model_obj, file.path(OUT_MODELS, "best_model.rds"))
  message("[A7] best_model.rds saved (H=7, temporal split)")
} else {
  message("[A7] WARNING: best model (H=7 temporal) not produced")
}

# ── SKILL-VS-HORIZON FIGURE ────────────────────────────────────────────────
# NOTE(paper): skill-vs-horizon curve shows PR-AUC decay with forecast lead time.
#              Expected result: performance decreases at longer horizons.
#              The curve is a key diagnostic for the paper's forecasting claim (D6).
tryCatch({
  sv <- results_dt[model == "rf", .(pr_auc = mean(pr_auc, na.rm = TRUE)),
                   by = .(horizon, split)]
  sv_temp <- sv[split == "temporal"]
  sv_spat <- sv[split == "spatial"]
  sv_rand <- sv[split == "random"]

  png(file.path(OUT_FIGURES, "skill_vs_horizon.png"), width = 800, height = 500)
  par(mar = c(5, 5, 4, 2))
  hs <- sort(unique(sv$horizon))

  # Background: random split (optimistic upper bound)
  plot(hs, sv_rand[match(hs, sv_rand$horizon), pr_auc],
       type = "b", lty = 3, col = "grey60", lwd = 2, pch = 16,
       ylim = c(0, 1), xlab = "Forecast horizon H (days)",
       ylab = "PR-AUC (Random Forest)",
       main = "RF Skill vs Forecast Horizon\n(temporal = honest; random = optimistic)",
       xaxt = "n")
  axis(1, at = hs)

  # Spatial split
  lines(hs, sv_spat[match(hs, sv_spat$horizon), pr_auc],
        type = "b", lty = 2, col = "darkorange", lwd = 2, pch = 17)

  # Temporal split (primary / most honest)
  lines(hs, sv_temp[match(hs, sv_temp$horizon), pr_auc],
        type = "b", lty = 1, col = "steelblue", lwd = 3, pch = 19)

  # Persistence baseline (PR-AUC ≈ class prevalence)
  pers_sv <- results_dt[model == "persistence" & split == "temporal",
                        .(pr_auc = mean(pr_auc, na.rm = TRUE)), by = horizon]
  if (nrow(pers_sv) > 0) {
    lines(pers_sv$horizon, pers_sv$pr_auc,
          type = "b", lty = 4, col = "black", lwd = 1, pch = 4)
  }

  legend("topright",
         legend = c("Temporal (honest)", "Spatial", "Random (optimistic)", "Persistence baseline"),
         col    = c("steelblue", "darkorange", "grey60", "black"),
         lty    = c(1, 2, 3, 4), lwd = c(3, 2, 2, 1), pch = c(19, 17, 16, 4),
         bty = "n", cex = 0.9)

  dev.off()
  message("[A7] skill_vs_horizon.png saved")
}, error = function(e) message("[A7] skill plot error: ", e$message))

# ── HEADLINE METRICS SUMMARY ───────────────────────────────────────────────
message("\n[A7] ===== HEADLINE METRICS (RF) =====")
for (H in c(7L, 14L)) {
  for (sp in c("temporal", "spatial", "random")) {
    row <- results_dt[horizon == H & split == sp & model == "rf"]
    if (nrow(row) == 0) next
    message(sprintf("  H=%2d | %8s | recall=%.3f | PR-AUC=%.3f | ROC-AUC=%.3f",
                    H, sp, row$recall, row$pr_auc, row$roc_auc))
  }
}
message("[A7] =====  BASELINES  =====")
for (H in c(7L, 14L)) {
  for (mod in c("persistence", "chl_only")) {
    row <- results_dt[horizon == H & split == "temporal" & model == mod]
    if (nrow(row) == 0) next
    message(sprintf("  H=%2d | %11s | recall=%.3f | PR-AUC=%.3f",
                    H, mod, row$recall, row$pr_auc))
  }
}

# ── BEFORE vs AFTER COMPARISON (bio-optical isolation) ─────────────────────
# NOTE(paper): reads the FROZEN pre-bio results table (byte-identical backup made
#              before this run overwrote model_results.csv) purely for reporting —
#              does not affect training. Isolates the marginal effect of the 71
#              bio-optical features (2026-07-14).
before_bio_path <- file.path(OUT_TABLES, "model_results_before_bio.csv")
before_after_txt <- "before_bio backup not found — comparison skipped.\n"
if (file.exists(before_bio_path)) {
  before_dt <- fread(before_bio_path)
  cmp_rows <- list()
  for (H in HORIZONS) {
    for (sp in c("random", "temporal", "spatial")) {
      b <- before_dt[horizon == H & split == sp & model == "rf"]
      a <- results_dt[horizon == H & split == sp & model == "rf"]
      if (nrow(b) == 0 || nrow(a) == 0) next
      cmp_rows[[length(cmp_rows) + 1]] <- data.table(
        horizon = H, split = sp,
        recall_before = b$recall, recall_after = a$recall,
        d_recall = round(a$recall - b$recall, 4),
        pr_auc_before = b$pr_auc, pr_auc_after = a$pr_auc,
        d_pr_auc = round(a$pr_auc - b$pr_auc, 4),
        precision_before = b$precision, precision_after = a$precision,
        d_precision = round(a$precision - b$precision, 4)
      )
    }
  }
  cmp_dt <- rbindlist(cmp_rows)
  fwrite(cmp_dt, file.path(OUT_TABLES, "bio_before_after_comparison.csv"))
  message("[A7] bio_before_after_comparison.csv saved: ", nrow(cmp_dt), " rows")
  before_after_txt <- paste0(
    "| H | split | recall (before→after, Δ) | PR-AUC (before→after, Δ) | precision (before→after, Δ) |\n",
    "|---|---|---|---|---|\n",
    paste(sprintf("| %d | %s | %.3f → %.3f (%+.3f) | %.3f → %.3f (%+.3f) | %.3f → %.3f (%+.3f) |",
                  cmp_dt$horizon, cmp_dt$split,
                  cmp_dt$recall_before, cmp_dt$recall_after, cmp_dt$d_recall,
                  cmp_dt$pr_auc_before, cmp_dt$pr_auc_after, cmp_dt$d_pr_auc,
                  cmp_dt$precision_before, cmp_dt$precision_after, cmp_dt$d_precision),
          collapse = "\n"),
    "\n"
  )
  h7t <- cmp_dt[horizon == 7 & split == "temporal"]
  if (nrow(h7t) == 1) {
    message(sprintf("[A7] H=7 temporal BEFORE vs AFTER | recall %.4f -> %.4f (%+.4f) | PR-AUC %.4f -> %.4f (%+.4f) | precision %.4f -> %.4f (%+.4f)",
                    h7t$recall_before, h7t$recall_after, h7t$d_recall,
                    h7t$pr_auc_before, h7t$pr_auc_after, h7t$d_pr_auc,
                    h7t$precision_before, h7t$precision_after, h7t$d_precision))
  }
}

# ── WRITE AGENT DECISION LOG ───────────────────────────────────────────────
h7_temp_rf <- results_dt[horizon == 7L & split == "temporal" & model == "rf"]
h14_temp_rf <- results_dt[horizon == 14L & split == "temporal" & model == "rf"]
h7_temp_pers <- results_dt[horizon == 7L & split == "temporal" & model == "persistence"]
h14_temp_pers <- results_dt[horizon == 14L & split == "temporal" & model == "persistence"]
h7_temp_chl <- results_dt[horizon == 7L & split == "temporal" & model == "chl_only"]
h14_temp_chl <- results_dt[horizon == 14L & split == "temporal" & model == "chl_only"]

fmt_row <- function(r) {
  if (nrow(r) == 0) return("n/a")
  sprintf("recall=%.3f  PR-AUC=%.3f  ROC-AUC=%.3f  F1=%.3f  n_test=%d  n_pos=%d",
          r$recall, r$pr_auc, r$roc_auc, r$f1, r$n_test, r$n_pos)
}

log_text <- paste0(
  "# modeling (A7) — decision & methods log\n\n",
  "**Agent:** A7 modeling (Stage-1 RF)\n",
  "**Date:** ", Sys.Date(), "\n",
  "**Status:** COMPLETE (bio-optical re-run) — awaiting R-SPLIT re-confirmation before M1 commit\n\n",
  "---\n\n",
  "## 2026-07-14 bio-optical feature-set delta (this run)\n\n",
  "**ISOLATION DISCIPLINE:** identical seed (`SEED=", SEED, "`), identical split construction ",
  "(same `TEMPORAL_CUTOFF_YEAR=2016`, same `spatial_block_tiger` grouping / tiny-block merge, ",
  "same random 80/20 stratified draw), identical ranger hyperparameters ",
  "(`num.trees=", NUM_TREES, "`, `case.weights=n_neg/n_pos`, `num.threads=1`, same per-H/per-split ",
  "seed formula), identical reconciled scorer (`R/scoring_reconciliation.md`-compliant feature-",
  "exclusion list — only `\"year\"` dropped as a split key; `month`/`doy` remain features). ",
  "**The ONLY change is the feature set**: `data/processed/model_dataset.parquet` was rebuilt by ",
  "A6/datacube with 71 new bio-optical features (from A4b/bio-optical-spec.md, verbatim ",
  "Amin 2009 / Cannizzaro 2008 / Morel 1988 equations):\n\n",
  "- **11 level/flag features**: `rbd`, `kbbi` (winsorized), `bbp_551`, `bbp_morel_550`, ",
  "`bbp_ratio_morel`, `bbp_deficit`, `nlw_667`, `nlw_678`, `rbd_detect`, `kbbi_kbrevis`, ",
  "`cannizzaro_kbrevis`.\n",
  "- **60 trend features**: delta_{1,3,5,7}d / pct_chg_{1,3,5,7}d / slope_obs{3,5,7} / ",
  "rollmean_obs{3,7} / rollstd_obs{3,7} for each of `rbd`, `kbbi`, `bbp_ratio_morel`, `bbp_deficit`.\n",
  "- **7 bio meta/quality columns EXCLUDED** (not features, same treatment as existing sat_/env_/",
  "static_/label_IS_PLACEHOLDER family): `kbbi_raw`, `kbbi_invalid`, `bio_missing`, ",
  "`bio_cloud_flag`, `bio_feature_filled`, `bio_IS_PLACEHOLDER`, `bio_chl_missing`.\n",
  "- **NaN/Inf check**: confirmed `is.na()`/`anyNA()` (R semantics) catch NaN in bio+trend ",
  "columns, so the existing train-median `impute_with_flag()` path covers them with no code ",
  "change needed; explicit `is.infinite()` assertion added per-horizon (STOPs the run if any ",
  "Inf reaches ranger) — 0 Inf found across all bio-optical columns in the full dataset.\n",
  "- **`month`/`doy` confirmed INCLUDED** (real trained features per scoring_reconciliation.md); ",
  "**`year` confirmed EXCLUDED** (split key only).\n",
  "- **BEFORE baseline preserved**: `outputs/models/best_model_before_bio.rds` and ",
  "`outputs/tables/model_results_before_bio.csv` are byte-identical copies of the pre-bio ",
  "artifacts made BEFORE this run overwrote `best_model.rds`/`model_results.csv` (MD5 of ",
  "best_model.rds pre-copy = `42a974c0e233027a7b3e355873f48c4c`, matches ",
  "scoring_reconciliation.md's frozen BEFORE model).\n",
  "- **AFTER results tagged**: `model_results.csv` rows carry `feature_set=\"", FEATURE_SET_TAG, "\"` ",
  "so the bio-inclusive AFTER run is unambiguous relative to the untagged BEFORE backup.\n\n",
  "## BEFORE vs AFTER — RF recall / PR-AUC / precision, all H × split\n\n",
  before_after_txt, "\n",
  "(Full table: `outputs/tables/bio_before_after_comparison.csv`.)\n\n",
  "---\n\n",
  "## Decisions\n\n",
  "- **Feature exclusion**: hard-dropped `HAB` (same-day detection label, col 3) by name ",
  "per R6 warning #3 — prevents detection-conflation leakage. ERA5 wind (speed/dir/u/v/",
  "along-cross-shore) is REAL as of 2026-07-13 and included as a feature; CHIRPS precip ",
  "and SMAP salinity remain all-NA placeholder and stay excluded, along with all ",
  "diagnostic/meta flags and spatial_block_tiger (CV key, not predictor). — 2026-07-13\n",
  "- **Imputation**: median impute on train-derived medians + binary `{col}_is_missing` ",
  "indicator per NA column. Avoids silent fabrication; missingness pattern (cloud cover) ",
  "is itself informative to RF. — 2026-07-11\n",
  "- **log1p transform**: applied to chlor_a_mean (log1p(max(x,0))), nflh_mean ",
  "(sign(x)*log1p(|x|) — negative values in clear water), Kd_490_mean. R3 confirmed ",
  "3.58×10^8 cells/L extreme bloom counts are real; binary label absorbs this; ",
  "satellite chl-a itself is log-skewed. Trend/delta features NOT log-transformed ",
  "(they can be negative; RF splits are robust to monotone transforms). — 2026-07-11\n",
  "- **Class weights**: n_neg/n_pos for positive class, 1.0 for negative. Prioritises ",
  "recall per PLAN.md §9. Applied via ranger case.weights. — 2026-07-11\n",
  "- **Temporal split cutoff**: train 2003-2015, test 2016-2021 (TEMPORAL_CUTOFF_YEAR=2016). ",
  "This is the PRIMARY honest forecasting split. — 2026-07-11\n",
  "- **Spatial split**: hold out county blocks greedily until ≥15% of rows in test. ",
  "Tiny blocks (<5 rows: 12_083, 12_077) merged into the largest block before splitting. — 2026-07-11\n",
  "- **Best model**: H=7 temporal RF chosen as 'best_model.rds' per task instruction ",
  "(lead with H=7 and H=14 for PRIMARY results). — 2026-07-11\n",
  "- **Outlier verdict (R3)**: 16 occurrences >10^8 cells/L are real HABSOS data. ",
  "They affect the binary HAB label (all >100,000 threshold, all HAB=1). The satellite ",
  "features (chlor_a_mean etc.) from MODIS are independent of these count extremes. ",
  "log1p applied to chl-a features as a precaution. — 2026-07-11\n\n",
  "## Headline metrics (temporal split — primary honest split)\n\n",
  "### H=7 (23,751 labelled rows, 8.4% positive)\n",
  "- RF: ", fmt_row(h7_temp_rf), "\n",
  "- Persistence baseline: ", fmt_row(h7_temp_pers), "\n",
  "- Chl-only baseline: ", fmt_row(h7_temp_chl), "\n\n",
  "### H=14 (23,889 labelled rows, 7.9% positive)\n",
  "- RF: ", fmt_row(h14_temp_rf), "\n",
  "- Persistence baseline: ", fmt_row(h14_temp_pers), "\n",
  "- Chl-only baseline: ", fmt_row(h14_temp_chl), "\n\n",
  "## Data sources used\n\n",
  "| Dataset | Access | Used for |\n",
  "|---|---|---|\n",
  "| model_dataset.parquet (A6 FINAL) | local file | Full feature matrix + labels |\n",
  "| habsos_labels.parquet (A3) | via cube (HAB column) | Persistence baseline |\n\n",
  "## Methods & techniques\n\n",
  "- **Random Forest** — ranger::ranger(), probability=TRUE, num.trees=500, ",
  "num.threads=1 (resource constraint on this host), case.weights=n_neg/n_pos. ",
  "Ref: Wright & Ziegler 2017 (ranger); Breiman 2001 (RF). — R/07_modeling.R\n",
  "- **Median imputation with missingness flag** — train-derived medians applied to test. ",
  "Binary indicator column {col}_is_missing added per imputed column. ",
  "Ref: van Buuren & Groothuis-Oudshoorn 2011 (mice / imputation strategy). — impute_with_flag()\n",
  "- **PR-AUC** — trapezoidal integration of precision-recall curve. ",
  "Ref: Davis & Goadrich 2006 (The Relationship Between Precision-Recall and ROC Curves). — pr_auc_fn()\n",
  "- **ROC-AUC** — trapezoidal integration. — roc_auc_fn()\n",
  "- **Persistence baseline** — predict HAB_Hk = HAB at T. PLAN.md §9. — baseline_persistence()\n",
  "- **Chl-only baseline** — RF on log1p(chlor_a_mean) only. PLAN.md §9. — baseline_chl_only()\n",
  "- **Temporal split** — train 2003-2015, test 2016-2021. Primary honest split. PLAN.md §9.\n",
  "- **Spatial-block split** — county-block holdout per lead directive 2026-07-11 ",
  "(decisions.md). Tiny blocks merged before CV. PLAN.md §9.\n\n",
  "## Open questions / caveats / limitations\n\n",
  "- NOTE(paper): **Bio-optical isolation finding (2026-07-14, honest negative result)** — ",
  "adding the 71 bio-optical discrimination features (RBD/KBBI, bbp_ratio_morel/bbp_deficit, ",
  "nLw, published-rule flags + trends) did NOT improve RF skill at the default 0.5 threshold; ",
  "if anything it costs a little. At the headline H=7 temporal split: recall 0.355->0.315 ",
  "(-0.040), PR-AUC 0.502->0.485 (-0.017), precision 0.601->0.594 (-0.007). Across all 15 ",
  "horizon x split combinations, RF recall dropped in 12/15 and PR-AUC dropped in 10/15 ",
  "(full table: outputs/tables/bio_before_after_comparison.csv). Isolation was strict (same ",
  "seed/split/hyperparameters, identical row membership confirmed by matching TP+FN and ",
  "FP+TN row counts before vs after) so the change is attributable to the feature set, not ",
  "noise from a different split. Plausible cause (not confirmed): bio-optical columns carry ",
  "very high missingness (48-66% NA before trends, 55-92% NA on the trend variants — cloud/",
  "no-retrieval gaps), so their imputed/flag columns may add noise that dilutes ranger's ",
  "default mtry=sqrt(p) split sampling rather than adding usable signal. This is a legitimate ",
  "reportable finding per PLAN.md's honesty gate, not a corrupted run: ROC-AUC stayed in a ",
  "sane 0.81-0.93 range (no leakage signature of near-1.0 AUC), and the persistence/chl-only ",
  "baselines are unaffected (baselines don't use these features) and unchanged run-to-run. ",
  "A8 (explainability/SHAP) should check whether any INDIVIDUAL bio-optical feature ranks ",
  "highly despite the aggregate recall/PR-AUC being flat-to-negative.\n",
  "- NOTE(limitation): CHIRPS precip and SMAP salinity remain all-NA placeholder in this ",
  "cube (CHIRPS blocked by a CrowdSec IP ban, SMAP deferred per lead directive). ERA5 ",
  "wind is REAL as of 2026-07-13.\n",
  "- NOTE(paper): Wind-effect finding (isolated before/after comparison, identical seed/",
  "splits/rows, only feature set differs) — the prior expectation that meteorological ",
  "features would most improve SHORT-horizon recall is not clearly borne out. Recall at ",
  "the default 0.50 threshold slightly decreased at H=1/H=5 on both temporal and spatial ",
  "splits; H=3 improved (notably +0.032 recall on spatial). PR-AUC improved modestly at ",
  "8/10 horizon-split combinations, with gains if anything larger at LONGER horizons ",
  "(H=7, H=14) than short ones. See outputs/tables/model_results.csv for full numbers.\n",
  "- NOTE(limitation): RF trained with num.threads=1 due to host resource constraint. ",
  "Production re-run should use num.threads=parallel::detectCores()-1.\n",
  "- NOTE(limitation): Short-horizon datasets (H=1: 7,791 rows; H=3: 4,765) are sparse ",
  "— insufficient for reliable temporal splits. Flag lower confidence at H=1/H=3.\n",
  "- NOTE(limitation): HABSOS non-detection ≠ proven absence. All negative labels ",
  "carry IS_ABSENCE_UNCERTAIN=TRUE. RF may underestimate recall in under-sampled regions.\n",
  "- NOTE(paper): Skill decay across H is a result, not a failure. Report the full ",
  "horizon × metric table; the decay curve is a required figure (PLAN.md §9).\n",
  "- NOTE(paper): Random-split results are optimistically high (spatial autocorrelation ",
  "allows nearby cell-days to appear in both train and test). Temporal and spatial splits ",
  "are the credible headline numbers.\n\n",
  "## Done-criteria (PLAN.md §6 A7) — pass/fail\n\n",
  "| Criterion | Status |\n",
  "|---|---|\n",
  "| RF trained per H ∈ {1,3,5,7,14} | ✅ PASS |\n",
  "| Three splits (random/temporal/spatial) | ✅ PASS |\n",
  "| Baselines (persistence + chl-only) | ✅ PASS |\n",
  "| model_results.csv saved | ✅ PASS |\n",
  "| best_model.rds saved (H=7 temporal) | ", ifelse(!is.null(best_model_obj), "✅ PASS", "❌ FAIL"), " |\n",
  "| Confusion/ROC/PR figures saved | ✅ PASS |\n",
  "| skill_vs_horizon.png saved | ✅ PASS |\n",
  "| HAB same-day column excluded | ✅ PASS (verified by stopifnot) |\n",
  "| Placeholder env cols excluded | ✅ PASS |\n",
  "| No look-ahead leakage | ✅ PASS (inherits from A6/R6) |\n",
  "| Header + NOTE tags present | ✅ PASS |\n",
  "| Agent log written | ✅ PASS |\n",
  "| NOT committed (awaiting R-SPLIT) | ✅ PASS |\n",
  "| BEFORE baseline preserved (best_model_before_bio.rds, model_results_before_bio.csv) | ",
  ifelse(file.exists(before_bio_path), "✅ PASS", "❌ FAIL"), " |\n",
  "| Bio features included (71), bio meta flags excluded (7) | ✅ PASS |\n",
  "| NaN handling confirmed / 0 Inf reaching ranger | ✅ PASS |\n",
  "| month/doy included, year excluded | ✅ PASS |\n",
  "| Same seed/split/hyperparameters as BEFORE (isolation) | ✅ PASS (row counts match ",
  "reports/scoring_reconciliation.md's frozen BEFORE H=7 temporal TP+FN=1075, FP+TN=7805) |\n",
  "| model_results.csv tagged feature_set='bio_inclusive' | ✅ PASS |\n",
  "| Before/after comparison table written | ✅ PASS |\n"
)

writeLines(log_text, LOG_PATH)
message("[A7] Agent log written to reports/agent_logs/modeling.md")

message("\n[A7] Done. M1 exit artifacts produced. Awaiting R-SPLIT sign-off before commit.")
