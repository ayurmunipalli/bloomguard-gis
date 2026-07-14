# ============================================================
# FILE:       R/07b_predictions_dump.R
# PURPOSE:    Additive follow-up to R/07_modeling.R (A7) — persists per-row RF
#             predictions for BOTH the pre-bio ("before") and bio-inclusive
#             ("after") feature sets, for ALL H x split combinations, so A10
#             can compute PR-AUC + precision-at-recall-0.80 on the full grid
#             (5 horizons x 3 splits x 2 feature sets = 30 combos) without
#             re-fitting. Only H=7 temporal has saved per-row predictions in
#             best_model.rds / best_model_before_bio.rds; the other 14
#             horizon x split fits in 07_modeling.R's loop are transient.
# INPUTS:     data/processed/model_dataset.parquet (65,939 x 194, bio-inclusive)
# OUTPUTS:    outputs/tables/predictions_before_after.parquet
#             columns: feature_set {before,after}, horizon, split, cell_id,
#             date_T, prob, act
# TECHNIQUES: Identical split construction, seed, and ranger hyperparameters
#             as R/07_modeling.R (copied verbatim, not re-derived) so the
#             before/after comparison stays apples-to-apples. "before" =
#             feat_cols with the 78 bio-optical columns additionally dropped
#             (simulates the pre-bio model_dataset schema); "after" = the
#             same bio-inclusive feat_cols R/07_modeling.R trains on.
# CITATIONS:  Breiman 2001 (Random Forests); Wright & Ziegler 2017 (ranger).
# NOTES:      ADDITIVE ONLY — does not touch outputs/models/best_model.rds or
#             outputs/tables/model_results.csv (those are final per A7).
#             Isolation discipline: same seed/split/hyperparams as
#             R/07_modeling.R; only feat_cols differs between before/after.
# ============================================================

# ── ARROW THREAD GUARD: source 00_config.R FIRST ──────────────────────────
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(arrow)
  arrow::set_cpu_count(1L)
  library(data.table)
  library(ranger)
})

message("[A7b] Libraries loaded.")

# ── PATHS ──────────────────────────────────────────────────────────────────
CUBE_PATH  <- proj_path("data/processed/model_dataset.parquet")
OUT_TABLES <- proj_path("outputs/tables")
dir.create(OUT_TABLES, showWarnings = FALSE, recursive = TRUE)

# ── CONSTANTS (identical to R/07_modeling.R — isolation discipline) ────────
HORIZONS    <- cfg$forecast$horizons_days  # {1,3,5,7,14}
SEED        <- cfg$random_seed %||% 42
NUM_TREES   <- 500L
TRAIN_FRAC  <- 0.80
TEMPORAL_CUTOFF_YEAR <- 2016L
MIN_BLOCK_ROWS <- 5L
LOG_FEATURES <- c("chlor_a_mean", "nflh_mean", "Kd_490_mean")

# ── FEATURE EXCLUSION LIST (identical to R/07_modeling.R) ──────────────────
ALWAYS_EXCLUDE <- c(
  "cell_id", "date_T",
  "HAB",
  "HAB_H1", "HAB_H3", "HAB_H5", "HAB_H7", "HAB_H14",
  "spatial_block_tiger",
  "max_count", "n_samples",
  "IS_PLACEHOLDER_ROW", "satellite_missing", "cloud_flag",
  "salinity_coarse_flag", "feature_filled_any", "IS_ABSENCE_UNCERTAIN",
  "sat_IS_PLACEHOLDER", "env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER", "label_IS_PLACEHOLDER",
  "sat_feature_filled", "env_feature_filled",
  "precip_mm", "salinity_pss",
  "kbbi_raw", "kbbi_invalid", "bio_missing", "bio_cloud_flag",
  "bio_feature_filled", "bio_IS_PLACEHOLDER", "bio_chl_missing"
)

# ── LOAD DATA ──────────────────────────────────────────────────────────────
message("[A7b] Loading model_dataset.parquet ...")
dt <- as.data.table(arrow::read_parquet(CUBE_PATH))
message("[A7b] Loaded: ", nrow(dt), " rows x ", ncol(dt), " cols")

date_raw <- dt[["date_T"]]
dt[["date_T"]] <- tryCatch(
  as.Date(as.character(date_raw)),
  error = function(e) as.Date(as.numeric(date_raw), origin = "1970-01-01")
)
dt[["year"]] <- as.integer(substr(as.character(dt[["date_T"]]), 1L, 4L))

for (feat in LOG_FEATURES) {
  if (feat %in% names(dt)) {
    if (feat == "nflh_mean") {
      dt[, (feat) := sign(get(feat)) * log1p(abs(get(feat)))]
    } else {
      dt[, (feat) := log1p(pmax(get(feat), 0))]
    }
  }
}

# NOTE(paper): BIO_ALL_COLS = every bio-optical column added by the 2026-07-14
#              A4b/A6 re-run (11 level/flag + 60 trend + 7 meta = 78 columns).
#              Regex-derived from the actual column names present (not
#              hand-enumerated) to avoid drift; "before" drops ALL of them
#              (not just the meta subset) to faithfully simulate the pre-bio
#              model_dataset schema R/07_modeling.R's frozen BEFORE model saw.
BIO_ALL_COLS <- grep("^(rbd|kbbi|bbp_|nlw_667$|nlw_678$|cannizzaro_kbrevis$|bio_)",
                      names(dt), value = TRUE)
message("[A7b] BIO_ALL_COLS (dropped for 'before'): ", length(BIO_ALL_COLS),
        " columns")
stopifnot(length(BIO_ALL_COLS) == 78L)  # 11 level/flag + 60 trend + 7 meta

# ── IMPUTATION WITH MISSINGNESS FLAG (identical to R/07_modeling.R) ────────
impute_with_flag <- function(train_dt, test_dt, feat_cols) {
  for (col in feat_cols) {
    na_col <- paste0(col, "_is_missing")
    train_dt[[na_col]] <- as.integer(is.na(train_dt[[col]]))
    test_dt[[na_col]]  <- as.integer(is.na(test_dt[[col]]))
    med <- median(train_dt[[col]], na.rm = TRUE)
    if (is.na(med)) med <- 0
    set(train_dt, which(is.na(train_dt[[col]])), col, med)
    set(test_dt,  which(is.na(test_dt[[col]])),  col, med)
  }
  list(train = train_dt, test = test_dt)
}

merge_tiny_blocks <- function(block_vec, min_rows = MIN_BLOCK_ROWS) {
  cnt  <- table(block_vec)
  tiny <- names(cnt)[cnt < min_rows]
  if (length(tiny) == 0) return(block_vec)
  target <- names(cnt)[which.max(cnt)]
  block_vec[block_vec %in% tiny] <- target
  block_vec
}

# ── MAIN LOOP: splits computed ONCE per H (feature-set-independent), then
#    trained TWICE per split (before/after) on the SAME row indices ─────────
all_preds <- list()

for (H in HORIZONS) {
  target_col <- paste0("HAB_H", H)
  message("\n[A7b] ===== Horizon H=", H, " =====")

  h_dt <- dt[!is.na(get(target_col))]
  message("[A7b] H=", H, ": ", nrow(h_dt), " labelled rows")

  h_dt[, block_cv := merge_tiny_blocks(spatial_block_tiger)]

  # ---- Splits (identical construction/seed to R/07_modeling.R; row
  #      membership does not depend on feature set) ----
  set.seed(SEED + H)
  pos_idx <- which(h_dt[[target_col]] == 1L)
  neg_idx <- which(h_dt[[target_col]] == 0L)
  train_pos <- sample(pos_idx, floor(TRAIN_FRAC * length(pos_idx)))
  train_neg <- sample(neg_idx, floor(TRAIN_FRAC * length(neg_idx)))
  rand_train_idx <- sort(c(train_pos, train_neg))
  rand_test_idx  <- setdiff(seq_len(nrow(h_dt)), rand_train_idx)

  temp_train_idx <- which(h_dt$year < TEMPORAL_CUTOFF_YEAR)
  temp_test_idx  <- which(h_dt$year >= TEMPORAL_CUTOFF_YEAR)

  block_sizes <- sort(table(h_dt$block_cv), decreasing = TRUE)
  cumulative  <- cumsum(block_sizes) / nrow(h_dt)
  n_holdout   <- max(1L, min(which(cumulative >= 0.15)))
  holdout_blocks <- names(block_sizes)[seq_len(n_holdout)]
  spat_test_idx  <- which(h_dt$block_cv %in% holdout_blocks)
  spat_train_idx <- setdiff(seq_len(nrow(h_dt)), spat_test_idx)

  splits <- list(
    random   = list(train = rand_train_idx,  test = rand_test_idx),
    temporal = list(train = temp_train_idx,  test = temp_test_idx),
    spatial  = list(train = spat_train_idx,  test = spat_test_idx)
  )

  for (split_name in names(splits)) {
    tr_idx <- splits[[split_name]]$train
    te_idx <- splits[[split_name]]$test
    if (length(tr_idx) < 20 || length(te_idx) < 10) {
      message("[A7b] SKIP H=", H, " split=", split_name, " (too few rows)")
      next
    }

    te_cell_id <- h_dt[te_idx][["cell_id"]]
    te_date_T  <- h_dt[te_idx][["date_T"]]

    for (feature_set in c("before", "after")) {
      excl_H    <- c(ALWAYS_EXCLUDE, setdiff(paste0("HAB_H", HORIZONS), target_col))
      feat_cols <- setdiff(names(h_dt), c(excl_H, target_col, "year", "block_cv"))
      if (feature_set == "before") {
        feat_cols <- setdiff(feat_cols, BIO_ALL_COLS)
      }
      na_cols <- feat_cols[sapply(feat_cols, function(cn) anyNA(h_dt[[cn]]))]

      tr_dt <- copy(h_dt[tr_idx, c(feat_cols, target_col), with = FALSE])
      te_dt <- copy(h_dt[te_idx, c(feat_cols, target_col), with = FALSE])

      imp   <- impute_with_flag(tr_dt, te_dt, na_cols)
      tr_dt <- imp$train
      te_dt <- imp$test

      n_pos <- sum(tr_dt[[target_col]] == 1L)
      n_neg <- sum(tr_dt[[target_col]] == 0L)
      if (n_pos == 0) { message("[A7b] SKIP: no positives in train"); next }
      w <- ifelse(tr_dt[[target_col]] == 1L, n_neg / n_pos, 1.0)

      tr_model <- copy(tr_dt)
      set(tr_model, j = target_col,
          value = factor(tr_model[[target_col]], levels = c(0, 1)))
      f <- as.formula(paste(target_col, "~ ."))

      # ---- SAME per-H/per-split seed formula as R/07_modeling.R, used for
      #      BOTH feature sets (apples-to-apples: same RF stochasticity given
      #      identical training data ordering) ----
      rf_seed <- SEED + H * 100L + which(names(splits) == split_name)
      message("[A7b]   Training RF (H=", H, ", split=", split_name,
              ", feature_set=", feature_set, ", ", length(feat_cols),
              " feat, ", nrow(tr_model), " train / ", nrow(te_dt), " test) ...")
      rf <- tryCatch(
        ranger(f, data = tr_model, num.trees = NUM_TREES, probability = TRUE,
               case.weights = w, num.threads = 1L, seed = rf_seed),
        error = function(e) { message("[A7b] ranger ERROR: ", e$message); NULL }
      )
      if (is.null(rf)) next

      te_model <- copy(te_dt)
      set(te_model, j = target_col,
          value = factor(te_model[[target_col]], levels = c(0, 1)))
      prob <- predict(rf, data = te_model)$predictions[, "1"]
      act  <- as.integer(as.character(te_model[[target_col]]))

      all_preds[[length(all_preds) + 1]] <- data.table(
        feature_set = feature_set,
        horizon     = H,
        split       = split_name,
        cell_id     = te_cell_id,
        date_T      = te_date_T,
        prob        = prob,
        act         = act
      )

      rm(rf, tr_dt, te_dt, tr_model, te_model, imp)
      gc(FALSE)
    }
  }
  rm(h_dt); gc(FALSE)
}

# ── SAVE ─────────────────────────────────────────────────────────────────
preds_dt <- rbindlist(all_preds, fill = TRUE)
message("\n[A7b] predictions_before_after: ", nrow(preds_dt), " rows, ",
        length(unique(paste(preds_dt$feature_set, preds_dt$horizon, preds_dt$split))),
        " combos")
arrow::write_parquet(preds_dt, file.path(OUT_TABLES, "predictions_before_after.parquet"))
message("[A7b] outputs/tables/predictions_before_after.parquet saved.")

# Sanity print: combo coverage table
combo_tab <- preds_dt[, .N, by = .(feature_set, horizon, split)]
setorder(combo_tab, feature_set, horizon, split)
print(combo_tab)

message("[A7b] Done.")
