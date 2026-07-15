# ============================================================
# FILE:       R/07c_split_repair.R
# PURPOSE:    P0-A (temporal embargo) + P0-B (spatial buffer) — measurement-
#             apparatus repairs for the two R-SPLIT conditional-pass split
#             defects (R/07_modeling.R:38-72). Re-freezes the ADOPTED (pre-bio,
#             post-wind) RF baseline under the repaired splits.
#
#             This harness MIRRORS R/07_modeling.R's pipeline exactly (same seed,
#             hyperparameters, log1p, impute-with-flag, class weights, block
#             merge, holdout selection, scorer) and differs ONLY in:
#               (1) the 71 bio-optical features are EXCLUDED  -> reproduces the
#                   ADOPTED pre-bio model, which is what §6 freezes (NOT the
#                   bio-inclusive run that 07_modeling.R now produces);
#               (2) the temporal/spatial splits get the P0-A/P0-B repairs.
#
#             It runs TWO arms so the repair effect is attributable and validated:
#               CONTROL  (repair OFF) — MUST reproduce outputs/tables/model_results.csv
#                          (random split identical; all persistence rows identical;
#                          H=7 temporal rf pr_auc=0.5022, tp=382/fp=254/fn=693/tn=7551).
#               REPAIRED (repair ON)  — the re-frozen baseline.
#
#             Embargo touches ONLY the temporal split; buffer touches ONLY the
#             spatial split; the random split is untouched by both. So the two
#             changes cannot confound each other (temporal Δ = embargo effect,
#             spatial Δ = buffer effect, random Δ = 0 control).
#
# INPUTS:     data/processed/model_dataset.parquet
#             config.yaml split_repair.{temporal_embargo, spatial_buffer_m}
# OUTPUTS:    outputs/tables/model_results_p0ab.csv       — REPAIRED rf/persist/chl (experiment-tagged)
#             outputs/tables/split_repair_validation.csv  — CONTROL vs canonical, and REPAIRED Δ
#             prints the reproduction check and the H=7 temporal PR-AUC delta.
# TECHNIQUES: temporal purge/embargo; spatial buffer (EPSG:5070 metric distance);
#             ranger RF (identical hyperparameters to A7).
# CITATIONS:  same as R/07_modeling.R.
#
# NOTE(paper): P0-A temporal embargo — no training row's label_date (date_T + H)
#   may fall in the test period (>= 2016-01-01). Closes the zero-embargo leak of
#   R/07_modeling.R:64-72 (~49 rows at H=14).
# NOTE(paper): P0-B spatial buffer — drop train CELLS within R (config, default
#   20 km = 2 cells) of any spatial-test cell. Closes the 14.6%-border-adjacency
#   residual autocorrelation of R/07_modeling.R:60-62. Residual test cells within
#   R of a train cell after the buffer is 0 by construction.
# NOTE(limitation): the buffer radius must be widened for E-01. Ring-2 neighbour
#   features reach 2 cells (~20 km); a buffer must exceed ring_radius + 1 cell,
#   i.e. >= 30 km once E-01a/E-01b land. Bump config split_repair.spatial_buffer_m
#   to >= 30000 before running E-01, or the neighbour features re-open the leak.
# NOTE(limitation): the 15 frozen transformer rows in model_results.csv were
#   trained on the PRE-repair training sets (M3, frozen). Their TEST evaluations
#   remain valid (test sets are unchanged by the repairs), but their training was
#   not embargoed/buffered. Disclose when citing the transformer head-to-head.
# ============================================================

# ── ARROW THREAD GUARD: source 00_config.R FIRST ──────────────────────────
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(arrow); arrow::set_cpu_count(1L)
  library(data.table)
  library(ranger)
  library(sf)
})
message("[07c] Libraries loaded.")

# ── PATHS / CONSTANTS (identical to A7) ────────────────────────────────────
CUBE_PATH   <- proj_path("data/processed/model_dataset.parquet")
OUT_TABLES  <- proj_path("outputs/tables")
HORIZONS    <- cfg$forecast$horizons_days
SEED        <- cfg$random_seed %||% 42
NUM_TREES   <- 500L
TRAIN_FRAC  <- 0.80
TEMPORAL_CUTOFF_YEAR <- 2016L
CUTOFF_DATE <- as.Date(paste0(TEMPORAL_CUTOFF_YEAR, "-01-01"))
MIN_BLOCK_ROWS <- 5L
LOG_FEATURES <- c("chlor_a_mean", "nflh_mean", "Kd_490_mean")

EMBARGO_ON  <- isTRUE(cfg$split_repair$temporal_embargo)
BUFFER_M    <- as.numeric(cfg$split_repair$spatial_buffer_m %||% 20000)
message("[07c] Repair config: embargo=", EMBARGO_ON, " buffer_m=", BUFFER_M)

# ── ADOPTED (pre-bio) feature exclusion: A7's ALWAYS_EXCLUDE + the 71 bio cols ─
ALWAYS_EXCLUDE <- c(
  "cell_id", "date_T", "HAB",
  "HAB_H1", "HAB_H3", "HAB_H5", "HAB_H7", "HAB_H14",
  "spatial_block_tiger", "max_count", "n_samples",
  "IS_PLACEHOLDER_ROW", "satellite_missing", "cloud_flag",
  "salinity_coarse_flag", "feature_filled_any", "IS_ABSENCE_UNCERTAIN",
  "sat_IS_PLACEHOLDER", "env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER", "label_IS_PLACEHOLDER",
  "sat_feature_filled", "env_feature_filled",
  "precip_mm", "salinity_pss",
  "kbbi_raw", "kbbi_invalid", "bio_missing", "bio_cloud_flag",
  "bio_feature_filled", "bio_IS_PLACEHOLDER", "bio_chl_missing"
)
# Bio-optical FEATURE columns to exclude so this reproduces the pre-bio ADOPTED
# model (07_modeling.R INCLUDES these; we drop them). Named level/flag features
# + all trend variants matching the A7 grep pattern + cannizzaro_kbrevis.
BIO_LEVEL <- c("rbd", "kbbi", "bbp_551", "bbp_morel_550", "bbp_ratio_morel",
               "bbp_deficit", "nlw_667", "nlw_678", "cannizzaro_kbrevis")
bio_exclude_cols <- function(cols) {
  trend <- grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_", cols, value = TRUE)
  unique(c(intersect(BIO_LEVEL, cols), trend))  # rbd_detect / kbbi_kbrevis caught by trend grep
}

# ── METRIC / IMPUTE / BASELINE HELPERS (verbatim from A7) ──────────────────
roc_auc_fn <- function(prob, actual) {
  if (length(unique(actual)) < 2) return(NA_real_)
  ord <- order(prob, decreasing = TRUE); act <- actual[ord]
  tp <- cumsum(act); fp <- cumsum(1L - act)
  tpr <- tp / sum(act); fpr <- fp / sum(1L - act)
  sum(diff(fpr) * (tpr[-length(tpr)] + tpr[-1]) / 2, na.rm = TRUE)
}
pr_auc_fn <- function(prob, actual) {
  if (length(unique(actual)) < 2) return(NA_real_)
  ord <- order(prob, decreasing = TRUE); act <- actual[ord]
  tp <- cumsum(act); fp <- cumsum(1L - act)
  prec <- tp / (tp + fp); rec <- tp / sum(act)
  rec_aug <- c(0, rec); prec_aug <- c(prec[1], prec)
  sum(diff(rec_aug) * (prec_aug[-length(prec_aug)] + prec_aug[-1]) / 2, na.rm = TRUE)
}
precision_at_recall_fn <- function(prob, actual, target_recall = 0.80) {
  if (length(unique(actual)) < 2) return(NA_real_)
  ord <- order(prob, decreasing = TRUE); act <- actual[ord]
  tp <- cumsum(act); fp <- cumsum(1L - act)
  prec <- tp / (tp + fp); rec <- tp / sum(act)
  hit <- which(rec >= target_recall)
  if (length(hit) == 0) return(NA_real_)
  round(prec[hit[1]], 4)
}
compute_metrics <- function(prob, actual, threshold = 0.5) {
  pred <- as.integer(prob >= threshold)
  tp <- sum(pred == 1L & actual == 1L); fp <- sum(pred == 1L & actual == 0L)
  fn <- sum(pred == 0L & actual == 1L); tn <- sum(pred == 0L & actual == 0L)
  prec <- if (tp + fp == 0) NA_real_ else tp / (tp + fp)
  rec  <- if (tp + fn == 0) NA_real_ else tp / (tp + fn)
  f1   <- if (is.na(prec) || is.na(rec) || (prec + rec) == 0) NA_real_ else 2 * prec * rec / (prec + rec)
  acc  <- (tp + tn) / length(actual)
  fnr  <- if (tp + fn == 0) NA_real_ else fn / (tp + fn)
  data.table(
    accuracy = round(acc, 4), precision = round(prec, 4), recall = round(rec, 4),
    f1 = round(f1, 4), fnr = round(fnr, 4),
    roc_auc = round(roc_auc_fn(prob, actual), 4), pr_auc = round(pr_auc_fn(prob, actual), 4),
    prec_at_recall80 = precision_at_recall_fn(prob, actual, 0.80),
    n_test = length(actual), n_pos = sum(actual),
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}
impute_with_flag <- function(train_dt, test_dt, feat_cols) {
  for (col in feat_cols) {
    na_col <- paste0(col, "_is_missing")
    train_dt[[na_col]] <- as.integer(is.na(train_dt[[col]]))
    test_dt[[na_col]]  <- as.integer(is.na(test_dt[[col]]))
    med <- median(train_dt[[col]], na.rm = TRUE); if (is.na(med)) med <- 0
    set(train_dt, which(is.na(train_dt[[col]])), col, med)
    set(test_dt,  which(is.na(test_dt[[col]])),  col, med)
  }
  list(train = train_dt, test = test_dt)
}
merge_tiny_blocks <- function(block_vec, min_rows = MIN_BLOCK_ROWS) {
  cnt <- table(block_vec); tiny <- names(cnt)[cnt < min_rows]
  if (length(tiny) == 0) return(block_vec)
  target <- names(cnt)[which.max(cnt)]
  block_vec[block_vec %in% tiny] <- target
  block_vec
}
baseline_persistence <- function(test_dt, target_col) {
  prob <- as.numeric(test_dt[["HAB"]]); act <- test_dt[[target_col]]
  m <- compute_metrics(prob, act, threshold = 0.5); m[, model := "persistence"]; m
}
baseline_chl_only <- function(train_dt, test_dt, target_col) {
  chl_col <- "chlor_a_mean"
  tr <- copy(train_dt[, c(chl_col, target_col), with = FALSE])
  te <- copy(test_dt[,  c(chl_col, target_col), with = FALSE])
  med_chl <- median(tr[[chl_col]], na.rm = TRUE); if (is.na(med_chl)) med_chl <- 0
  set(tr, which(is.na(tr[[chl_col]])), chl_col, med_chl)
  set(te, which(is.na(te[[chl_col]])), chl_col, med_chl)
  n_pos <- sum(tr[[target_col]] == 1L, na.rm = TRUE); n_neg <- sum(tr[[target_col]] == 0L, na.rm = TRUE)
  w <- ifelse(tr[[target_col]] == 1L, n_neg / n_pos, 1.0)
  f <- as.formula(paste(target_col, "~", chl_col))
  set(tr, j = target_col, value = factor(tr[[target_col]], levels = c(0, 1)))
  set(te, j = target_col, value = factor(te[[target_col]], levels = c(0, 1)))
  rf_chl <- tryCatch(ranger(f, data = tr, num.trees = 100L, probability = TRUE,
                            case.weights = w, seed = SEED, num.threads = 1L),
                     error = function(e) NULL)
  if (is.null(rf_chl)) return(data.table(model = "chl_only", pr_auc = NA))
  prob <- predict(rf_chl, data = te)$predictions[, "1"]
  act  <- as.integer(as.character(te[[target_col]]))
  m <- compute_metrics(prob, act); m[, model := "chl_only"]; m
}

# ── LOAD + PREP (identical to A7) ──────────────────────────────────────────
message("[07c] Loading parquet ...")
dt <- as.data.table(read_parquet(CUBE_PATH))
dt[["date_T"]] <- as.Date(as.character(dt[["date_T"]]))
dt[["year"]]   <- as.integer(substr(as.character(dt[["date_T"]]), 1L, 4L))
for (feat in LOG_FEATURES) if (feat %in% names(dt)) {
  if (feat == "nflh_mean") dt[, (feat) := sign(get(feat)) * log1p(abs(get(feat)))]
  else dt[, (feat) := log1p(pmax(get(feat), 0))]
}

# Cell centroids projected to EPSG:5070 for metric buffer distances (P0-B).
cell_xy <- unique(dt[, .(cell_id, centroid_lon, centroid_lat)])
proj <- sf::sf_project("EPSG:4326", "EPSG:5070",
                       as.matrix(cell_xy[, .(centroid_lon, centroid_lat)]))
cell_xy[, `:=`(X = proj[, 1], Y = proj[, 2])]
setkey(cell_xy, cell_id)

# For each spatial split: which TRAIN cells lie within R of any TEST cell.
train_cells_within_buffer <- function(train_cells, test_cells, R) {
  tr <- cell_xy[.(unique(train_cells))]; te <- cell_xy[.(unique(test_cells))]
  if (nrow(te) == 0 || nrow(tr) == 0) return(character(0))
  # min distance from each train cell to the nearest test cell
  drop <- vapply(seq_len(nrow(tr)), function(i) {
    d2 <- (te$X - tr$X[i])^2 + (te$Y - tr$Y[i])^2
    sqrt(min(d2)) < R
  }, logical(1))
  tr$cell_id[drop]
}

# ── MAIN: run one arm (repair on/off) over all H × split ───────────────────
run_arm <- function(repair) {
  results <- list(); drops <- list()
  for (H in HORIZONS) {
    target_col <- paste0("HAB_H", H)
    h_dt <- dt[!is.na(get(target_col))]
    excl_H    <- c(ALWAYS_EXCLUDE, setdiff(paste0("HAB_H", HORIZONS), target_col))
    feat_cols <- setdiff(names(h_dt), c(excl_H, target_col, "year"))
    feat_cols <- setdiff(feat_cols, bio_exclude_cols(feat_cols))   # ADOPTED pre-bio
    # NOTE: match A7 EXACTLY — A7's ALWAYS_EXCLUDE does NOT drop centroid_lon/lat,
    # county_fips/name, state_fips, so they ARE features in the adopted model.
    # The ONLY intended difference from A7 is the bio-feature exclusion above.
    stopifnot(!"HAB" %in% feat_cols)
    na_cols <- feat_cols[vapply(feat_cols, function(cn) anyNA(h_dt[[cn]]), logical(1))]
    h_dt[, block_cv := merge_tiny_blocks(spatial_block_tiger)]

    # (1) RANDOM 80/20 (untouched by repair)
    set.seed(SEED + H)
    pos_idx <- which(h_dt[[target_col]] == 1L); neg_idx <- which(h_dt[[target_col]] == 0L)
    train_pos <- sample(pos_idx, floor(TRAIN_FRAC * length(pos_idx)))
    train_neg <- sample(neg_idx, floor(TRAIN_FRAC * length(neg_idx)))
    rand_train_idx <- sort(c(train_pos, train_neg))
    rand_test_idx  <- setdiff(seq_len(nrow(h_dt)), rand_train_idx)

    # (2) TEMPORAL holdout + P0-A embargo
    temp_train_idx <- which(h_dt$year < TEMPORAL_CUTOFF_YEAR)
    temp_test_idx  <- which(h_dt$year >= TEMPORAL_CUTOFF_YEAR)
    if (repair && EMBARGO_ON) {
      label_date <- h_dt$date_T[temp_train_idx] + H
      keep <- label_date < CUTOFF_DATE
      n_drop <- sum(!keep)
      drops[[paste0("H", H, "_embargo")]] <- data.table(H = H, repair_step = "P0-A embargo",
        n_train_before = length(temp_train_idx), n_dropped = n_drop,
        n_train_after = sum(keep))
      temp_train_idx <- temp_train_idx[keep]
    }

    # (3) SPATIAL block holdout + P0-B buffer
    block_sizes <- sort(table(h_dt$block_cv), decreasing = TRUE)
    cumulative <- cumsum(block_sizes) / nrow(h_dt)
    n_holdout <- max(1L, min(which(cumulative >= 0.15)))
    holdout_blocks <- names(block_sizes)[seq_len(n_holdout)]
    spat_test_idx  <- which(h_dt$block_cv %in% holdout_blocks)
    spat_train_idx <- setdiff(seq_len(nrow(h_dt)), spat_test_idx)
    if (repair && BUFFER_M > 0) {
      test_cells  <- h_dt$cell_id[spat_test_idx]
      train_cells <- h_dt$cell_id[spat_train_idx]
      # % of TEST cells within R of a train cell BEFORE the buffer
      te_u <- cell_xy[.(unique(test_cells))]; tr_u <- cell_xy[.(unique(train_cells))]
      before_frac <- mean(vapply(seq_len(nrow(te_u)), function(i)
        sqrt(min((tr_u$X - te_u$X[i])^2 + (tr_u$Y - te_u$Y[i])^2)) < BUFFER_M, logical(1)))
      drop_cells <- train_cells_within_buffer(train_cells, test_cells, BUFFER_M)
      keep <- !(h_dt$cell_id[spat_train_idx] %in% drop_cells)
      # residual AFTER: train cells now exclude everything within R -> test-within-R = 0
      tr_after <- cell_xy[.(unique(h_dt$cell_id[spat_train_idx[keep]]))]
      after_frac <- if (nrow(tr_after) == 0) 0 else mean(vapply(seq_len(nrow(te_u)), function(i)
        sqrt(min((tr_after$X - te_u$X[i])^2 + (tr_after$Y - te_u$Y[i])^2)) < BUFFER_M, logical(1)))
      drops[[paste0("H", H, "_buffer")]] <- data.table(H = H, repair_step = "P0-B buffer",
        n_train_before = length(spat_train_idx), n_dropped = sum(!keep),
        n_train_after = sum(keep),
        cells_dropped = length(drop_cells),
        test_within_R_before_pct = round(100 * before_frac, 2),
        test_within_R_after_pct  = round(100 * after_frac, 2))
      spat_train_idx <- spat_train_idx[keep]
    }

    splits <- list(random = list(train = rand_train_idx, test = rand_test_idx),
                   temporal = list(train = temp_train_idx, test = temp_test_idx),
                   spatial = list(train = spat_train_idx, test = spat_test_idx))

    for (split_name in names(splits)) {
      tr_idx <- splits[[split_name]]$train; te_idx <- splits[[split_name]]$test
      if (length(tr_idx) < 20 || length(te_idx) < 10) next
      tr_dt <- copy(h_dt[tr_idx, c(feat_cols, target_col), with = FALSE])
      te_dt <- copy(h_dt[te_idx, c(feat_cols, target_col), with = FALSE])
      imp <- impute_with_flag(tr_dt, te_dt, na_cols); tr_dt <- imp$train; te_dt <- imp$test
      n_pos <- sum(tr_dt[[target_col]] == 1L); n_neg <- sum(tr_dt[[target_col]] == 0L)
      if (n_pos == 0) next
      w <- ifelse(tr_dt[[target_col]] == 1L, n_neg / n_pos, 1.0)
      tr_model <- copy(tr_dt)
      set(tr_model, j = target_col, value = factor(tr_model[[target_col]], levels = c(0, 1)))
      f <- as.formula(paste(target_col, "~ ."))
      rf <- tryCatch(ranger(f, data = tr_model, num.trees = NUM_TREES, probability = TRUE,
                            case.weights = w, num.threads = 1L,
                            seed = SEED + H * 100L + which(names(splits) == split_name)),
                     error = function(e) NULL)
      if (is.null(rf)) next
      te_model <- copy(te_dt)
      set(te_model, j = target_col, value = factor(te_model[[target_col]], levels = c(0, 1)))
      prob_rf <- predict(rf, data = te_model)$predictions[, "1"]
      act <- as.integer(as.character(te_model[[target_col]]))
      m_rf <- compute_metrics(prob_rf, act); m_rf[, model := "rf"]

      te_hab <- h_dt[te_idx, "HAB", with = FALSE]
      m_pers <- baseline_persistence(cbind(te_dt, te_hab), target_col)
      m_chl  <- baseline_chl_only(h_dt[tr_idx, c("chlor_a_mean", target_col), with = FALSE],
                                  h_dt[te_idx, c("chlor_a_mean", target_col), with = FALSE], target_col)
      for (m_row in list(m_rf, m_pers, m_chl)) {
        m_row[, `:=`(horizon = H, split = split_name, n_train = length(tr_idx),
                     pos_rate_train = round(n_pos / (n_pos + n_neg), 4))]
        results[[length(results) + 1]] <- m_row
      }
    }
  }
  list(results = rbindlist(results, fill = TRUE), drops = rbindlist(drops, fill = TRUE))
}

# ── RUN BOTH ARMS ──────────────────────────────────────────────────────────
message("\n[07c] === CONTROL arm (repair OFF — must reproduce canonical) ===")
control <- run_arm(repair = FALSE)
message("[07c] === REPAIRED arm (repair ON) ===")
repaired <- run_arm(repair = TRUE)

col_order <- c("horizon", "split", "model", "recall", "pr_auc", "roc_auc", "precision",
               "f1", "fnr", "accuracy", "n_test", "n_train", "n_pos", "tp", "fp", "fn",
               "tn", "pos_rate_train", "prec_at_recall80")
rep_dt <- repaired$results; setcolorder(rep_dt, intersect(col_order, names(rep_dt)))
rep_dt[, feature_set := "adopted_prebio_p0ab"]
fwrite(rep_dt, file.path(OUT_TABLES, "model_results_p0ab.csv"))
message("[07c] model_results_p0ab.csv written: ", nrow(rep_dt), " rows")

# ── VALIDATION vs canonical ────────────────────────────────────────────────
canon <- fread(file.path(OUT_TABLES, "model_results.csv"))
ctrl <- control$results
val_rows <- list()
for (i in seq_len(nrow(ctrl))) {
  r <- ctrl[i]; c <- canon[horizon == r$horizon & split == r$split & model == r$model]
  if (nrow(c) != 1) next
  val_rows[[length(val_rows) + 1]] <- data.table(
    horizon = r$horizon, split = r$split, model = r$model,
    canon_pr_auc = c$pr_auc, control_pr_auc = r$pr_auc,
    d_pr_auc = round(r$pr_auc - c$pr_auc, 4),
    canon_tp = c$tp, control_tp = r$tp, canon_n_train = c$n_train, control_n_train = r$n_train)
}
val <- rbindlist(val_rows)
fwrite(val, file.path(OUT_TABLES, "split_repair_validation.csv"))

cat("\n================ CONTROL REPRODUCTION CHECK ================\n")
cat("Max |Δ pr_auc| control-vs-canonical, random split (must be ~0):",
    val[split == "random", max(abs(d_pr_auc))], "\n")
cat("Max |Δ pr_auc| control-vs-canonical, persistence rows (must be ~0):",
    val[model == "persistence", max(abs(d_pr_auc))], "\n")
h7c <- val[horizon == 7 & split == "temporal" & model == "rf"]
cat(sprintf("H=7 temporal rf CONTROL pr_auc=%.4f (canonical 0.5022), control_tp=%d (canon 382)\n",
            h7c$control_pr_auc, h7c$control_tp))
cat("\n---- rows where |Δ| > 0.0005 in control (unexpected) ----\n")
print(val[abs(d_pr_auc) > 0.0005][order(-abs(d_pr_auc))])

# ── REPAIR DROP REPORT ─────────────────────────────────────────────────────
cat("\n================ P0-A / P0-B DROP REPORT ================\n")
print(repaired$drops)

# ── REPAIRED vs canonical DELTA ────────────────────────────────────────────
cat("\n================ REPAIRED Δ vs canonical (adopted baseline) ================\n")
delta_rows <- list()
for (i in seq_len(nrow(rep_dt))) {
  r <- rep_dt[i]; c <- canon[horizon == r$horizon & split == r$split & model == r$model]
  if (nrow(c) != 1) next
  delta_rows[[length(delta_rows) + 1]] <- data.table(
    horizon = r$horizon, split = r$split, model = r$model,
    canon_pr_auc = c$pr_auc, repaired_pr_auc = r$pr_auc,
    d_pr_auc = round(r$pr_auc - c$pr_auc, 4),
    canon_n_train = c$n_train, repaired_n_train = r$n_train)
}
delta <- rbindlist(delta_rows)
print(delta[model == "rf"][order(horizon, split)])
h7d <- delta[horizon == 7 & split == "temporal" & model == "rf"]
cat(sprintf("\n>>> HEADLINE: H=7 temporal rf PR-AUC  %.4f -> %.4f  (Δ = %+.4f)\n",
            h7d$canon_pr_auc, h7d$repaired_pr_auc, h7d$d_pr_auc))
if (abs(h7d$d_pr_auc) > 0.02) {
  cat("\n*** STOP: |Δ| > 0.02 at H=7 temporal — §7.3 PIVOT TRIGGER. Author decision. ***\n")
} else {
  cat("    |Δ| <= 0.02 — within the pivot-trigger band; safe to re-freeze.\n")
}
message("\n[07c] Done.")
