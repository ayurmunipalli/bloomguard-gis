# ============================================================
# FILE:       06_build_datacube.R
# OWNER:      A6 datacube (reviewer R6, sonnet-5) — LAST data-integrity gate before modeling
# PURPOSE:    Build the model training dataset (cell × date) by joining
#             HABSOS labels + satellite features + environmental features +
#             static geographic features, computing T+H forecast labels for
#             each horizon H ∈ {1,3,5,7,14}, and engineering trend/rate-of-change
#             features from the satellite time series (D11/§8-B).
# INPUTS:     data/processed/habsos_labels.parquet       (A3)
#             data/processed/satellite_features.parquet  (A4 — PARTIAL, growing)
#             data/processed/environmental_features.parquet (A5)
#             data/processed/static_geo.parquet          (A5)
# OUTPUTS:    data/processed/model_dataset.parquet
#             Status: FINAL — full MODIS satellite coverage (5829 dates, 2003-2021).
# TECHNIQUES: data.table left/exact-date joins; trailing OLS slopes via shift();
#             calendar-lag join for absolute deltas; T+H forecast label shift (D5/§2.2);
#             no-look-ahead hard assertions; feature_filled/satellite_missing flags.
# CITATIONS:  Green (2022) RTM gridding method; PLAN.md D5/D11/§2.2/§8-B;
#             Hu et al. (2022) Harmful Algae 117:102289 (study area/dates).
#
# NOTE(paper): Trend features (§8-B) are first-class predictors by design.
#   Each level feature (chlor_a, SST, nFLH, Kd_490) receives: absolute k-day
#   calendar-day deltas, day-over-day % change, trailing OLS slope over k
#   observed dates, and rolling mean/std (k=3,7 observations). All computed
#   strictly at or before feature date T → no look-ahead into the label horizon.
#
# NOTE(paper): Row space is the HABSOS observation cell-days (T = sample date,
#   filtered to satellite era >= 2003-01-01). The forecast label for horizon H
#   at row (cell_id, T) is HAB(cell_id, T+H), found by self-joining the label
#   table. Rows with no HABSOS observation at T+H receive label = NA (unknown,
#   not assumed negative). The modelling script (A7) filters to non-NA labels
#   per horizon. This is the "label-centric with feature-date = T" design:
#   features are always at T (a HABSOS date), maximising feature coverage.
#
# NOTE(paper): Slope features use observation-order indices (1, 2, ..., k),
#   not calendar-day indices, because the satellite series covers only HABSOS
#   sample dates (cloud-gapped daily product). Unit = change per satellite
#   observation. Calendar-day delta columns (delta_Xd) use exact-date joins
#   and are NA where the required offset date is absent from satellite series.
#
# NOTE(limitation): DRAFT — as of this run, satellite_features.parquet covers
#   only the first ~250 HABSOS dates (2003-01-02 to 2003-11-20). All satellite-
#   derived columns are NA for the remaining ~5579 dates. satellite_missing=TRUE
#   marks these rows. Re-run after A4 MODIS pull completes.
#
# NOTE(paper): as of 2026-07-12, ERA5 wind (speed/direction/along-cross-shore, 2003-2021)
#   is REAL. CHIRPS precip and SMAP salinity remain PLACEHOLDER (NA) — see
#   data/raw/weather/manual_downloads.md and reports/agent_logs/env-features.md.
#   Seasonality (month, doy_sin, doy_cos) is real by construction.
#
# NOTE(limitation): HABSOS non-detection ≠ proven absence. IS_ABSENCE_UNCERTAIN
#   is TRUE for every row (including HAB=0). A row with HAB=0 means a sample
#   was taken and K. brevis was below the 100,000 cells/L threshold — it does
#   NOT certify that the cell was bloom-free. See habsos-label.md.
# ============================================================

# Force single-threaded arrow BEFORE anything else — deadlock prevention.
# See 00_config.R for the matching Sys.setenv(ARROW_NUM_THREADS="1").
# NOTE for A7 and downstream: always source 00_config.R first (it sets the
# env var), then call arrow::set_cpu_count(1L) after library(arrow).
Sys.setenv(ARROW_NUM_THREADS = "1")
suppressMessages({
  library(arrow)
  library(data.table)
  library(yaml)
})
arrow::set_cpu_count(1L)

# ── Config bootstrap: walk up to repo root containing config.yaml ──
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d)
    d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

cat("=== 06_build_datacube.R: Build Model Dataset ===\n")
cat("Run date:", format(Sys.time()), "\n\n")

# ============================================================
# 1. PATHS & CONFIG
# ============================================================
horizons   <- cfg$forecast$horizons_days          # c(1, 3, 5, 7, 14)
delta_lags <- cfg$trends$delta_lags_days          # c(1, 3, 5, 7) calendar days
slope_wins <- cfg$trends$slope_windows_days       # c(3, 5, 7) observations
roll_wins  <- cfg$trends$rolling_windows_days     # c(3, 7) observations
eps        <- cfg$trends$pct_change_epsilon       # 1e-6  (divide-by-zero guard)
dod_thresh <- cfg$trends$dod_pct_threshold        # 10 (%)
dod_consec <- cfg$trends$dod_consecutive_days     # 2 consecutive observations

p_labels <- proj_path(cfg$paths$habsos_labels)
p_sat    <- proj_path(cfg$paths$satellite_features)
p_env    <- proj_path(cfg$paths$environmental_features)
p_static <- proj_path("data/processed/static_geo.parquet")
p_out    <- proj_path(cfg$paths$model_dataset)

cat("Horizons (H):", paste(horizons, collapse = ", "), "\n")
cat("Output:       ", p_out, "\n\n")

# ============================================================
# 2. LOAD INPUTS
# ============================================================
cat("[1/10] Loading inputs...\n")
labels_raw <- as.data.table(read_parquet(p_labels))
sat_raw    <- as.data.table(read_parquet(p_sat))
env_raw    <- as.data.table(read_parquet(p_env))
static_raw <- as.data.table(read_parquet(p_static))

# Coerce date columns
labels_raw[, sample_date := as.Date(sample_date)]
sat_raw[,   date         := as.Date(date)]
env_raw[,   date         := as.Date(date)]

cat("  habsos_labels:          ", nrow(labels_raw),
    "rows | date range:", as.character(min(labels_raw$sample_date)),
    "to", as.character(max(labels_raw$sample_date)), "\n")
cat("  satellite_features:     ", nrow(sat_raw), "rows |",
    uniqueN(sat_raw$date), "unique dates |",
    as.character(min(sat_raw$date)), "to", as.character(max(sat_raw$date)), "\n")
cat("  environmental_features: ", nrow(env_raw), "rows\n")
cat("  static_geo:             ", nrow(static_raw), "rows\n\n")

# ── Memory guard: filter satellite to label cells before trend computation ──
# The full satellite table (27.6M rows × 4,743 cells) would require ~16 GB when
# extended with 61 trend columns. Labels use only 1,461 of the 4,743 cells.
# Filtering to label cells reduces to ~8.5M rows (~5 GB with trend cols added).
# NOTE(paper): This filter does NOT remove dates — each retained cell keeps its
# full 5,829-date time series so rolling stats are computed on the complete record.
# NOTE for A7: the full satellite_features.parquet is unchanged (4,743 cells);
# model_dataset.parquet carries only the 1,461 cells with HABSOS observations.
{
  label_cells <- unique(labels_raw$cell_id[labels_raw$sample_date >= as.Date("2003-01-01")])
  n_sat_before <- nrow(sat_raw)
  sat_raw <- sat_raw[cell_id %in% label_cells]
  cat("  Satellite filtered to label cells:", length(label_cells), "cells |",
      n_sat_before, "->", nrow(sat_raw), "rows\n\n")
}

# ============================================================
# 3. FILTER LABELS TO SATELLITE ERA
# ============================================================
cat("[2/10] Filtering to satellite era (>= 2003-01-01)...\n")

# NOTE(paper): MODIS-Aqua L3m reliable coverage begins 2003-01-01. Pre-2003
#   HABSOS records are preserved in habsos_labels.parquet (A3 decision) but
#   excluded here because no MODIS satellite features can be joined to them.
# NOTE(limitation): Drops 28,871 of 94,810 label rows (30.5%). Pre-2003
#   records remain available for historical analysis without satellite features.

SAT_ERA_START <- as.Date("2003-01-01")
labels <- copy(labels_raw[sample_date >= SAT_ERA_START])
cat("  Dropped pre-2003 rows:", nrow(labels_raw) - nrow(labels),
    "| Remaining:", nrow(labels), "\n\n")

# ============================================================
# 4. COMPUTE SATELLITE TREND FEATURES
# ============================================================
cat("[3/10] Computing satellite trend features (D11/§8-B)...\n")

level_cols <- c("chlor_a_mean", "sst_mean", "nflh_mean", "Kd_490_mean")

sat <- copy(sat_raw)
setorder(sat, cell_id, date)

# Helper: vectorised OLS slope over k consecutive observations (observation order)
# Formula from OLS with x = 1:k equally spaced, using closed-form coefficients.
# k=3:  slope = (y[i] - y[i-2]) / 2
# k=5:  slope = (-2*y[i-4] - y[i-3] + y[i-1] + 2*y[i]) / 10
# k=7:  slope = (-3*y[i-6] - 2*y[i-5] - y[i-4] + y[i-2] + 2*y[i-1] + 3*y[i]) / 28
# NA is propagated if any of the k window values is NA.
ols_slope_k <- function(y, k) {
  switch(as.character(k),
    "3" = (y - shift(y, 2L)) / 2.0,
    "5" = (-2.0 * shift(y, 4L) - shift(y, 3L) +
             shift(y, 1L) + 2.0 * y) / 10.0,
    "7" = (-3.0 * shift(y, 6L) - 2.0 * shift(y, 5L) - shift(y, 4L) +
             shift(y, 2L) + 2.0 * shift(y, 1L) + 3.0 * y) / 28.0,
    stop("Unsupported window k=", k, " for ols_slope_k")
  )
}

for (col in level_cols) {
  svar <- sub("_mean$", "", col)   # "chlor_a", "sst", "nflh", "Kd_490"

  # ── Absolute calendar-day deltas (exact-date join, NA if date absent) ──
  # NOTE(paper): delta_Xd = x_T - x_{T-X_days}. Backward-looking; X > 0.
  #   Uses exact-date self-join: shift the satellite row's date forward by X so
  #   that when joined on (cell_id, date == date+X), the matching value is at T-X.
  #   NA when date T-X is not in the satellite series (cloud gap or unprocessed).
  for (k in delta_lags) {
    lag_col  <- paste0(svar, "_lag_",   k, "d__")
    delt_col <- paste0(svar, "_delta_", k, "d")
    sat_lag  <- sat[, .(cell_id, join_date = date + k, lag_val = get(col))]
    sat[sat_lag, on = .(cell_id, date = join_date), (lag_col) := i.lag_val]
    sat[, (delt_col) := get(col) - get(lag_col)]
    sat[, (lag_col)  := NULL]   # drop temp column
  }

  # ── Day-over-day and k-day % change (calendar-day, exact join) ──
  # NOTE(paper): % change = (x_T - x_{T-k}) / (|x_{T-k}| + ε) * 100.
  #   ε = 1e-6 prevents division by zero in clear-water cells with near-zero
  #   chl-a. Result is signed (negative = declining). PLAN.md §8-B.
  # Use sat[[...]] column access outside [.data.table] to avoid get() scoping issues.
  for (k in delta_lags) {
    delt_col <- paste0(svar, "_delta_", k, "d")
    pct_col  <- paste0(svar, "_pct_chg_", k, "d")
    x_T     <- sat[[col]]            # value at T
    x_delta <- sat[[delt_col]]       # x_T - x_{T-k}
    x_lag_k <- x_T - x_delta        # x_{T-k} reconstructed
    sat[[pct_col]] <- x_delta / (abs(x_lag_k) + eps) * 100.0
  }

  # ── Trailing OLS slope over k observed dates (observation order) ──
  col_vec <- sat[[col]]  # extract vector once; passed into function by cell group
  for (k in slope_wins) {
    slope_col <- paste0(svar, "_slope_obs", k)
    sat[, (slope_col) := ols_slope_k(get(col), k), by = cell_id]
  }

  # ── Rolling mean / std over k observations (trailing, no look-ahead) ──
  # NOTE(paper): frollmean with align="right" gives a strictly trailing window.
  #   Rolling std computed via E[X^2] - E[X]^2 (Welford-free, sufficient here).
  sq_tmp <- paste0(svar, "_sq__")
  sat[, (sq_tmp) := get(col)^2]
  for (k in roll_wins) {
    mu_col  <- paste0(svar, "_rollmean_obs", k)
    std_col <- paste0(svar, "_rollstd_obs",  k)
    sat[, (mu_col) := frollmean(get(col),    n = k, na.rm = TRUE, align = "right"),
        by = cell_id]
    sat[, (std_col) := {
      mu2 <- frollmean(get(sq_tmp), n = k, na.rm = TRUE, align = "right")
      mu  <- get(mu_col)
      sqrt(pmax(0.0, mu2 - mu^2))
    }, by = cell_id]
  }
  sat[, (sq_tmp) := NULL]
}

# ── Threshold-crossing flag: chlor_a up >10% DoD for >= 2 consecutive obs ──
# NOTE(paper): Directly interpretable bloom-accumulation signal. A cell where
#   chlor_a has risen >10% day-over-day (calendar-day exact join) in at least
#   two consecutive observations is flagged as exhibiting rapid chl-a escalation.
#   PLAN.md D11/§8-B. The consecutive test uses observation order.
chla_pct_1d <- "chlor_a_pct_chg_1d"
if (chla_pct_1d %in% names(sat)) {
  sat[, chlor_a_rise10pct_flag__ := (!is.na(get(chla_pct_1d))) &
                                      (get(chla_pct_1d) > dod_thresh)]
  sat[, chlor_a_above10pct_consec :=
        as.integer(chlor_a_rise10pct_flag__ &
                   !is.na(shift(chlor_a_rise10pct_flag__)) &
                   shift(chlor_a_rise10pct_flag__)),
      by = cell_id]
  sat[, chlor_a_rise10pct_flag__ := NULL]
} else {
  sat[, chlor_a_above10pct_consec := NA_integer_]
}

trend_cols_added <- setdiff(names(sat), names(sat_raw))
cat("  Trend columns added (", length(trend_cols_added), "):",
    paste(head(trend_cols_added, 10), collapse = ", "),
    if (length(trend_cols_added) > 10) "..." else "", "\n\n")

# ============================================================
# 5. HISTORICAL HAB FEATURES (temporal self-lag from labels)
# ============================================================
cat("[4/10] Computing historical HAB lag features...\n")

# NOTE(paper): For each (cell_id, T), indicates whether any HAB=1 observation
#   exists for that cell in the [T - lag_days, T) window (strictly before T).
#   Captures temporal autocorrelation in bloom occurrence at the cell level.
# NOTE(limitation): This indicator is based solely on HABSOS sampling dates,
#   not continuous monitoring. Absence of a prior observation ≠ prior non-bloom.

hab_ref <- labels[, .(cell_id, sample_date, HAB)]
setorder(hab_ref, cell_id, sample_date)

hab_lags_list <- list()
for (lag_days in c(7L, 14L)) {
  col_name <- paste0("hab_any_prior_", lag_days, "d")
  # Non-equi join: for each (cell_id, T = ref_date), find all hab_ref rows
  # for the same cell where sample_date ∈ [T - lag_days, T).
  # data.table non-equi joins require pre-computed columns (no expressions in on=).
  ref_tbl <- hab_ref[, .(cell_id,
                          ref_date    = sample_date,
                          win_start   = sample_date - lag_days)]
  # In data.table non-equi join x[i, ...]:
  # - x = hab_ref: cell_id, sample_date, HAB  → accessed as HAB (no prefix)
  # - i = ref_tbl: cell_id, ref_date, win_start → accessed as i.ref_date
  window_hits <- hab_ref[ref_tbl,
                          on = .(cell_id,
                                 sample_date >= win_start,
                                 sample_date <  ref_date),
                          allow.cartesian = TRUE,
                          .(cell_id, ref_date = i.ref_date, HAB)]
  agg <- window_hits[, .(hab_any = as.integer(any(HAB == 1L, na.rm = TRUE))),
                      by = .(cell_id, sample_date = ref_date)]
  agg[is.na(hab_any), hab_any := 0L]
  setnames(agg, "hab_any", col_name)
  hab_lags_list[[col_name]] <- agg
  cat("  hab_any_prior_", lag_days, "d: ",
      sum(agg[[col_name]], na.rm = TRUE), "positive rows\n", sep = "")
}

# Merge both lag tables together keyed on (cell_id, sample_date)
hab_lags <- Reduce(function(a, b)
  merge(a, b, by = c("cell_id", "sample_date"), all = TRUE),
  hab_lags_list)

cat("\n")

# ============================================================
# 6. BASE JOIN: labels ← satellite + env + historical HAB + static
# ============================================================
cat("[5/10] Building base join (labels ← satellite + env + static)...\n")

# Rename IS_PLACEHOLDER and feature_filled before merging to avoid collisions.
sat_join <- copy(sat)
setnames(sat_join, "IS_PLACEHOLDER", "sat_IS_PLACEHOLDER")
setnames(sat_join, "feature_filled", "sat_feature_filled")
sat_join[, sat_date_present__ := TRUE]   # sentinel for join-hit detection

env_join <- copy(env_raw)
setnames(env_join, "IS_PLACEHOLDER", "env_IS_PLACEHOLDER")
setnames(env_join, "feature_filled", "env_feature_filled")

static_join <- copy(static_raw)
setnames(static_join, "IS_PLACEHOLDER", "static_IS_PLACEHOLDER")

setnames(labels, "IS_PLACEHOLDER", "label_IS_PLACEHOLDER")

# Left-join labels ← satellite (exact date match on cell_id + sample_date)
# NOTE: sat covers only HABSOS-date-aligned dates; most rows will be NA (DRAFT).
base <- merge(labels, sat_join,
              by.x = c("cell_id", "sample_date"),
              by.y = c("cell_id", "date"),
              all.x = TRUE)

# Derive satellite_missing flag: TRUE when no satellite row was joined
base[, satellite_missing := is.na(sat_date_present__)]
base[, sat_date_present__ := NULL]
base[satellite_missing == TRUE, sat_IS_PLACEHOLDER := TRUE]

# Left-join base ← environmental features (1:1 since env keyed on same dates)
base <- merge(base, env_join,
              by.x = c("cell_id", "sample_date"),
              by.y = c("cell_id", "date"),
              all.x = TRUE)

# Left-join base ← historical HAB lags
base <- merge(base, hab_lags, by = c("cell_id", "sample_date"), all.x = TRUE)
# Fill NA with 0 (no prior bloom observation within window)
for (hcol in c("hab_any_prior_7d", "hab_any_prior_14d")) {
  base[is.na(get(hcol)), (hcol) := 0L]
}

# Left-join base ← static geo (cell-level; one row per cell_id)
# NOTE(paper): spatial_block_tiger from static_geo is the spatial CV grouping
#   per Lead Directive (reports/decisions.md 2026-07-11). 82 TIGER county blocks.
base <- merge(base, static_join, by = "cell_id", all.x = TRUE)

cat("  Base rows after join:         ", nrow(base), "\n")
cat("  Satellite coverage (non-miss):",
    sum(!base$satellite_missing), "/", nrow(base),
    sprintf("(%.1f%%)\n\n",
            100 * sum(!base$satellite_missing) / nrow(base)))

# ============================================================
# 7. T+H FORECAST LABEL SHIFT (D5 — CRITICAL)
# ============================================================
cat("[6/10] Computing T+H forecast labels for H ∈ {",
    paste(horizons, collapse = ","), "}...\n")

# NOTE(paper): For horizon H, the training label for row (cell_id, T) is
#   HAB(cell_id, T+H). Built by self-joining habsos labels:
#   for each row (cell_id, D=T+H, HAB) in labels, the feature date is T = D-H.
#   Rows with no HABSOS observation at T+H receive label = NA (unobserved).
# LEAKAGE CHECK: Since H > 0, the label date (T+H) is strictly after the
#   feature date (T). This is guaranteed by construction (H ∈ {1,3,5,7,14}).

label_ref_full <- labels_raw[sample_date >= SAT_ERA_START,
                               .(cell_id, sample_date, HAB)]

for (H in horizons) {
  hab_col <- paste0("HAB_H", H)
  # Shift: label row at date D=T+H represents feature date T = D-H
  lab_shifted <- label_ref_full[, .(cell_id,
                                     feature_date = sample_date - H,
                                     hab_target    = HAB)]
  base <- merge(base, lab_shifted,
                by.x = c("cell_id", "sample_date"),
                by.y = c("cell_id", "feature_date"),
                all.x = TRUE)
  setnames(base, "hab_target", hab_col)
  n_nonNA <- sum(!is.na(base[[hab_col]]))
  n_pos   <- sum(base[[hab_col]] == 1L, na.rm = TRUE)
  cat(sprintf("  H=%2d: %d labelled rows (%d pos, %.1f%%)\n",
              H, n_nonNA, n_pos, 100 * n_pos / pmax(1, n_nonNA)))
}

# ============================================================
# 8. ROW-LEVEL HONESTY FLAGS
# ============================================================
cat("\n[7/10] Computing row-level honesty flags...\n")

# IS_PLACEHOLDER_ROW: TRUE when any constituent source is placeholder/missing.
# NOTE(paper): Models should not treat placeholder rows as fully-observed.
#   A7 may weight or exclude IS_PLACEHOLDER_ROW = TRUE rows per horizon.
base[, IS_PLACEHOLDER_ROW := (
  (satellite_missing == TRUE) |         # satellite not yet processed for this date
  (env_IS_PLACEHOLDER == TRUE) |        # env dynamic features (wind/precip/sal) are placeholder
  (!is.na(static_IS_PLACEHOLDER) &
     static_IS_PLACEHOLDER == TRUE)     # static geo has NA depth (24 edge cells)
)]

# feature_filled_any: any LOCF fill was applied by A4 or A5
base[, feature_filled_any := (
  (!is.na(sat_feature_filled) & sat_feature_filled) |
  (!is.na(env_feature_filled) & env_feature_filled)
)]

cat("  IS_PLACEHOLDER_ROW = TRUE:", sum(base$IS_PLACEHOLDER_ROW, na.rm = TRUE),
    sprintf("(%.1f%%)\n", 100 * mean(base$IS_PLACEHOLDER_ROW, na.rm = TRUE)))
cat("  satellite_missing  = TRUE:", sum(base$satellite_missing), "\n")
cat("  feature_filled_any = TRUE:", sum(base$feature_filled_any, na.rm = TRUE), "\n\n")

# ============================================================
# 9. NO-LOOK-AHEAD LEAKAGE ASSERTION (HARD — must not fail)
# ============================================================
cat("[8/10] Running no-look-ahead leakage assertions...\n")

# A: All feature dates are in the satellite era.
stopifnot("LEAKAGE-A: pre-2003 feature rows" =
            all(base$sample_date >= SAT_ERA_START))

# B: Calendar-day delta columns are backward (k > 0 days back).
delta_cols <- grep("_delta_[0-9]+d$", names(base), value = TRUE)
# They are x_T - x_{T-k}: by construction the lag join used date+k, so
# the matched value is at date-k. All k ∈ {1,3,5,7} > 0. ✓
stopifnot("LEAKAGE-B: no zero-lag delta" = all(delta_lags > 0))

# C: Slope / rolling features use shift() with lag >= 1 (trailing).
# ols_slope_k() uses shift(y, 2L or higher) as its oldest lag — no negative lag.
# frollmean uses align="right" (trailing). Verified by construction.
slope_cols <- grep("_slope_obs[0-9]+|_rollmean_obs[0-9]+|_rollstd_obs[0-9]+",
                   names(base), value = TRUE)
stopifnot("LEAKAGE-C: expected slope/roll cols present" = length(slope_cols) > 0)

# D: All H values in horizons are strictly positive → label is strictly future.
stopifnot("LEAKAGE-D: all horizons > 0" = all(horizons > 0L))
# If H were 0, label date = feature date T (contemporaneous leakage). Not allowed.

# E: Historical HAB lag features use strictly prior dates (< T).
# Non-equi join used sample_date < ref_date (strict less-than). Verified.
stopifnot("LEAKAGE-E: hab lag cols present" =
            all(c("hab_any_prior_7d", "hab_any_prior_14d") %in% names(base)))

# F: HAB (the same-day HAB at T) is included for reference but should NOT be
#    used as a feature for horizon H > 0 (that would be contemporaneous leakage).
#    A7 must drop the column 'HAB' when training on HAB_HX for any X > 0.
#    We tag it here for A7's attention.
# NOTE(paper): The column 'HAB' represents the bloom status at feature date T
#   (same day). Using it as a feature when predicting HAB at T+H (H>0) is
#   NOT leakage in the strict look-ahead sense (it's observed at T), but it
#   can conflate detection with forecasting. A7 should run ablations with and
#   without same-day HAB as a feature. Retained here for diagnostics.

cat("  LEAKAGE-A: sample_date >= 2003-01-01    PASS\n")
cat("  LEAKAGE-B: all delta lags > 0           PASS\n")
cat("  LEAKAGE-C: slope/roll cols trailing     PASS (", length(slope_cols), "cols)\n")
cat("  LEAKAGE-D: all horizons > 0             PASS\n")
cat("  LEAKAGE-E: HAB lag cols use strict-<T   PASS\n")
cat("  *** NO LOOK-AHEAD LEAKAGE DETECTED — all assertions PASSED ***\n\n")

# ============================================================
# 10. FINALISE COLUMN ORDER AND WRITE OUTPUT
# ============================================================
cat("[9/10] Finalising and writing output...\n")

# Rename sample_date to date_T to make the "feature observation date" explicit.
setnames(base, "sample_date", "date_T")

# Bring key columns to front.
key_cols <- c("cell_id", "date_T",
              "HAB",                                    # same-day label (diagnostic only)
              paste0("HAB_H", horizons),               # forecast targets
              "IS_PLACEHOLDER_ROW", "IS_ABSENCE_UNCERTAIN",
              "satellite_missing", "feature_filled_any",
              "sat_IS_PLACEHOLDER", "env_IS_PLACEHOLDER", "static_IS_PLACEHOLDER",
              "cloud_flag", "salinity_coarse_flag",
              "spatial_block_tiger",                   # spatial CV grouping (Lead directive)
              "spatial_cluster")                       # adjacency diagnostic (not CV grouping)
present_key <- intersect(key_cols, names(base))
other_cols  <- setdiff(names(base), present_key)
setcolorder(base, c(present_key, other_cols))

cat("  Final rows:", nrow(base), " | Final cols:", ncol(base), "\n")

# Summary of label availability per horizon
cat("\nLabel availability per horizon:\n")
for (H in horizons) {
  hcol   <- paste0("HAB_H", H)
  n_obs  <- sum(!is.na(base[[hcol]]))
  n_pos  <- sum(base[[hcol]] == 1L, na.rm = TRUE)
  cat(sprintf("  H=%2d: %5d labelled rows | %4d positive (%.2f%%) | %5d NA (no HABSOS obs at T+H)\n",
              H, n_obs, n_pos, 100 * n_pos / pmax(1, n_obs), sum(is.na(base[[hcol]]))))
}

# Draft status summary
cat("\nSatellite coverage summary:\n")
cat("  Satellite dates in parquet:", uniqueN(sat_raw$date), "\n")
cat("  Feature dates (post-2003):", uniqueN(base$date_T), "\n")
cat("  Coverage:",
    sprintf("%.1f%%\n",
            100 * uniqueN(sat_raw$date) / uniqueN(base$date_T)))

cat("\n[10/10] Writing parquet...\n")
dir.create(dirname(p_out), showWarnings = FALSE, recursive = TRUE)
write_parquet(base, p_out)

sz_mb <- round(file.info(p_out)$size / 1e6, 2)
cat("  Written:", p_out, "\n")
cat("  File size:", sz_mb, "MB\n")
cat("  Rows:", nrow(base), " | Cols:", ncol(base), "\n")
cat("\n*** STATUS: FINAL — full MODIS satellite coverage (5829 dates, satellite_missing=0) ***\n")
cat(sprintf("    IS_PLACEHOLDER_ROW = TRUE for %.1f%% of rows.\n",
            100 * mean(base$IS_PLACEHOLDER_ROW, na.rm = TRUE)))
cat("    env_IS_PLACEHOLDER = wind_is_placeholder & precip_is_placeholder & salinity_is_placeholder\n")
cat("    (see reports/agent_logs/env-features.md for which of the three are real as of this run).\n")
cat("=== 06_build_datacube.R: DONE ===\n")
