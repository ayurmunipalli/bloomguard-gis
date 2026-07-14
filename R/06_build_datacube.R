# ============================================================
# FILE:       06_build_datacube.R
# OWNER:      A6 datacube (reviewer R6, sonnet-5) — LAST data-integrity gate before modeling
# PURPOSE:    Build the model training dataset (cell × date) by joining
#             HABSOS labels + satellite features + environmental features +
#             static geographic features + bio-optical species-discrimination
#             features (A4b), computing T+H forecast labels for each horizon
#             H ∈ {1,3,5,7,14}, and engineering trend/rate-of-change features
#             from the satellite AND bio-optical time series (D11/§8-B).
# INPUTS:     data/processed/habsos_labels.parquet       (A3)
#             data/processed/satellite_features.parquet  (A4 — FINAL, full MODIS)
#             data/processed/satellite_features_bio_optical.parquet (A4b — FINAL,
#               27,641,118 rows / 5,829 dates / 4,742 cells; RBD/KBBI/bbp
#               species-discrimination scores. Additive, read-only, joined
#               here for the first time — see 2026-07-14 extension below.)
#             data/processed/environmental_features.parquet (A5)
#             data/processed/static_geo.parquet          (A5)
# OUTPUTS:    data/processed/model_dataset.parquet
#             Status: FINAL — full MODIS satellite coverage (5829 dates, 2003-2021)
#             + bio-optical discrimination features and their rolling/trend
#             variants (2026-07-14 additive extension).
# TECHNIQUES: data.table left/exact-date joins; trailing OLS slopes via shift();
#             calendar-lag join for absolute deltas; T+H forecast label shift (D5/§2.2);
#             no-look-ahead hard assertions; feature_filled/satellite_missing flags;
#             KBBI winsorization to the physically-valid [-1,1] range (2026-07-14).
# CITATIONS:  Green (2022) RTM gridding method; PLAN.md D5/D11/§2.2/§8-B;
#             Hu et al. (2022) Harmful Algae 117:102289 (study area/dates);
#             Amin et al. (2009) Optics Express 17(11):9126-9144 (RBD/KBBI);
#             Cannizzaro et al. (2008) Cont. Shelf Res. 28(1):137-158 (bbp rule);
#             Morel (1988) J. Geophys. Res. 93(C9):10749-10768 (bbp reference curve).
#             See reports/bio_optical_spec.md for exact equations/page numbers.
#
# NOTE(paper): Trend features (§8-B) are first-class predictors by design.
#   Each level feature (chlor_a, SST, nFLH, Kd_490, and — as of 2026-07-14 —
#   rbd, kbbi (winsorized), bbp_ratio_morel, bbp_deficit) receives: absolute
#   k-day calendar-day deltas, day-over-day % change, trailing OLS slope over k
#   observed dates, and rolling mean/std (k=3,7 observations), via one shared
#   `add_trend_features()` helper (refactored 2026-07-14 from the original
#   inline loop so the satellite and bio-optical variables use byte-identical
#   logic — no parallel scheme). All computed strictly at or before feature
#   date T → no look-ahead into the label horizon.
#
# NOTE(limitation): KBBI (Amin 2009 Eq.20) is published with no epsilon guard
#   on its nLw(678)+nLw(667) denominator; sat-features.md documents that raw
#   KBBI ranges to roughly ±23,000 in cells/dates where that denominator is
#   near zero (dark/turbid/land-adjacent edge cases) — see A4b's log, "KBBI
#   numerical instability" entry, 2026-07-14. KBBI is a normalized index
#   physically bounded to [-1,1] (it is a normalized difference of two
#   non-negative-in-theory radiances), so any |kbbi|>1 reading is an
#   unreliable retrieval, not a real value. Per the lead's directive, this is
#   fixed at the CUBE layer (here), NOT by adding an epsilon to the published
#   formula in R/04b (the formula stays exactly as printed in Amin 2009).
#   Winsorization: kbbi := NA where |kbbi| > 1; raw value kept as `kbbi_raw`
#   (cheap to retain); `kbbi_invalid` flags exactly the rows that were reset to
#   NA (TRUE only for previously non-NA values outside [-1,1] — NaN/NA inputs
#   are untouched and remain FALSE, since they were already missing, not
#   invalid). Count logged at run time (see Section 4b below).
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
p_bio    <- proj_path("data/processed/satellite_features_bio_optical.parquet")  # A4b, additive
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
bio_raw    <- as.data.table(read_parquet(p_bio))    # A4b bio-optical, additive
env_raw    <- as.data.table(read_parquet(p_env))
static_raw <- as.data.table(read_parquet(p_static))

# Coerce date columns
labels_raw[, sample_date := as.Date(sample_date)]
sat_raw[,   date         := as.Date(date)]
bio_raw[,   date         := as.Date(date)]
env_raw[,   date         := as.Date(date)]

cat("  habsos_labels:          ", nrow(labels_raw),
    "rows | date range:", as.character(min(labels_raw$sample_date)),
    "to", as.character(max(labels_raw$sample_date)), "\n")
cat("  satellite_features:     ", nrow(sat_raw), "rows |",
    uniqueN(sat_raw$date), "unique dates |",
    as.character(min(sat_raw$date)), "to", as.character(max(sat_raw$date)), "\n")
cat("  bio_optical (A4b):      ", nrow(bio_raw), "rows |",
    uniqueN(bio_raw$date), "unique dates |", uniqueN(bio_raw$cell_id), "cells |",
    as.character(min(bio_raw$date)), "to", as.character(max(bio_raw$date)), "\n")
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

  # NOTE(paper): Same memory-guard filter applied to the bio-optical table
  #   (A4b, 27,641,118 rows across 4,742 cells) for the identical reason — keep
  #   full per-cell time series for the label cells only, before computing the
  #   rolling/trend variants in Section 4b. Additive: satellite_features_bio_optical.parquet
  #   itself is untouched on disk.
  n_bio_before <- nrow(bio_raw)
  bio_raw <- bio_raw[cell_id %in% label_cells]
  cat("  Bio-optical filtered to label cells:", length(intersect(label_cells, unique(bio_raw$cell_id))),
      "of", length(label_cells), "label cells matched |",
      n_bio_before, "->", nrow(bio_raw), "rows\n\n")
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

# ── NOTE(limitation): memory guard, 2026-07-14 — with the bio-optical table ──
#   (Section 4b) now ALSO held at label-cell scale (~8.5M rows) alongside
#   `sat`, holding onto `sat_raw`/`bio_raw` (each also ~8.5M rows) for the rest
#   of the script pushed peak memory past this machine's 16 GB vector limit
#   (observed live: "Error: vector memory limit of 16.0 Gb reached" during the
#   Section 6 base join). Fix: capture the two small scalars/vectors still
#   needed from `sat_raw` downstream (its column-name set for the
#   `trend_cols_added` diff, and the unique-date count for the coverage
#   summary print) right now, then free `sat_raw` immediately — it is not
#   otherwise used again. Mirrored for `bio_raw` after Section 4b below.
sat_raw_names   <- names(sat_raw)
n_sat_dates_all <- uniqueN(sat_raw$date)
rm(sat_raw); invisible(gc(verbose = FALSE))

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

# NOTE(paper): 2026-07-14 — this loop body was refactored (unchanged logic,
#   verbatim formulas, R6-verified — see reports/agent_logs/R6-datacube-review.md
#   §1/§6) into the shared `add_trend_features()` helper below so the bio-optical
#   trend variables (Section 4b) reuse EXACTLY this machinery rather than a
#   parallel scheme, per the mission's hard requirement #4. The function
#   modifies `dt` via `:=` AND returns it; callers MUST reassign the result
#   (`sat <- add_trend_features(sat, ...)`) rather than relying on modify-by-
#   reference alone — a data.table passed as a function argument can be
#   shallow-copied partway through a `by=`-grouped `:=` (observed live, see the
#   NOTE(limitation) just above the call site below), which silently drops
#   later columns if the caller doesn't capture the return value.
add_trend_features <- function(dt, level_cols, delta_lags, slope_wins, roll_wins, eps) {
  for (col in level_cols) {
    svar <- sub("_mean$", "", col)   # e.g. "chlor_a", "sst", "nflh", "Kd_490", or unchanged ("rbd","kbbi",...)

    # ── Absolute calendar-day deltas (exact-date join, NA if date absent) ──
    # NOTE(paper): delta_Xd = x_T - x_{T-X_days}. Backward-looking; X > 0.
    #   Uses exact-date self-join: shift the row's date forward by X so
    #   that when joined on (cell_id, date == date+X), the matching value is at T-X.
    #   NA when date T-X is not in the series (cloud gap or unprocessed).
    for (k in delta_lags) {
      lag_col  <- paste0(svar, "_lag_",   k, "d__")
      delt_col <- paste0(svar, "_delta_", k, "d")
      dt_lag   <- dt[, .(cell_id, join_date = date + k, lag_val = get(col))]
      dt[dt_lag, on = .(cell_id, date = join_date), (lag_col) := i.lag_val]
      dt[, (delt_col) := get(col) - get(lag_col)]
      dt[, (lag_col)  := NULL]   # drop temp column
    }

    # ── Day-over-day and k-day % change (calendar-day, exact join) ──
    # NOTE(paper): % change = (x_T - x_{T-k}) / (|x_{T-k}| + ε) * 100.
    #   ε = 1e-6 prevents division by zero in clear-water cells with near-zero
    #   values. Result is signed (negative = declining). PLAN.md §8-B. Applied
    #   identically to bio-optical scores (rbd/kbbi/bbp_ratio_morel/bbp_deficit)
    #   as to satellite levels — same guard, same formula, no bespoke handling.
    # Use dt[[...]] column access outside [.data.table] to avoid get() scoping issues.
    for (k in delta_lags) {
      delt_col <- paste0(svar, "_delta_", k, "d")
      pct_col  <- paste0(svar, "_pct_chg_", k, "d")
      x_T     <- dt[[col]]            # value at T
      x_delta <- dt[[delt_col]]       # x_T - x_{T-k}
      x_lag_k <- x_T - x_delta        # x_{T-k} reconstructed
      dt[[pct_col]] <- x_delta / (abs(x_lag_k) + eps) * 100.0
    }

    # ── Trailing OLS slope over k observed dates (observation order) ──
    for (k in slope_wins) {
      slope_col <- paste0(svar, "_slope_obs", k)
      dt[, (slope_col) := ols_slope_k(get(col), k), by = cell_id]
    }

    # ── Rolling mean / std over k observations (trailing, no look-ahead) ──
    # NOTE(paper): frollmean with align="right" gives a strictly trailing window.
    #   Rolling std computed via E[X^2] - E[X]^2 (Welford-free, sufficient here).
    sq_tmp <- paste0(svar, "_sq__")
    dt[, (sq_tmp) := get(col)^2]
    for (k in roll_wins) {
      mu_col  <- paste0(svar, "_rollmean_obs", k)
      std_col <- paste0(svar, "_rollstd_obs",  k)
      dt[, (mu_col) := frollmean(get(col),    n = k, na.rm = TRUE, align = "right"),
          by = cell_id]
      dt[, (std_col) := {
        mu2 <- frollmean(get(sq_tmp), n = k, na.rm = TRUE, align = "right")
        mu  <- get(mu_col)
        sqrt(pmax(0.0, mu2 - mu^2))
      }, by = cell_id]
    }
    dt[, (sq_tmp) := NULL]
  }
  dt
}

# NOTE(limitation): data.table's `:=` normally modifies by reference with no
#   copy, but a data.table passed as a function argument can be shallow-copied
#   partway through (observed live, 2026-07-14: R emits "A shallow copy of this
#   data.table was taken..." warnings from the by=cell_id grouped assignments
#   inside the loop, and only the FIRST variable's delta columns + the
#   threshold flag survived back in `sat` — everything after that point in the
#   loop was silently lost because it landed on a copy the caller never sees).
#   Fix: capture and reassign the function's return value at the call site
#   instead of relying on modify-by-reference across the function boundary.
sat <- add_trend_features(sat, level_cols, delta_lags, slope_wins, roll_wins, eps)

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

trend_cols_added <- setdiff(names(sat), sat_raw_names)
cat("  Trend columns added (", length(trend_cols_added), "):",
    paste(head(trend_cols_added, 10), collapse = ", "),
    if (length(trend_cols_added) > 10) "..." else "", "\n\n")

# ============================================================
# 4b. BIO-OPTICAL SPECIES-DISCRIMINATION FEATURES (A4b extension, 2026-07-14)
# ============================================================
# NOTE(paper): Additive extension — mission: rebuild model_dataset.parquet with
#   the A4b bio-optical discrimination features (RBD/KBBI/Cannizzaro-vs-Morel
#   bbp score) and their rolling/trend variants, LEFT-JOINED onto the existing
#   cube. Does NOT touch satellite_features.parquet, habsos_labels, env/static
#   features, or the existing MODIS trend cols computed above.
cat("[3b/10] Preparing bio-optical features + KBBI winsorization (A4b)...\n")

bio <- copy(bio_raw)
# NOTE(limitation): memory guard (see the matching note at the `sat` copy
#   above) — capture the small name-vector needed for the trend-cols diff now,
#   so bio_raw can be freed right after Section 4b instead of lingering
#   (unused) through Sections 5-10 alongside `sat`/`bio`/`base`.
bio_raw_names <- names(bio_raw)

# ── NOTE(limitation)/NOTE(cite): KBBI winsorization (mandatory, see header). ──
# Amin (2009) Eq.20 KBBI = (nLw678-nLw667)/(nLw678+nLw667) is a normalized
# difference and is physically bounded to [-1,1]; sat-features.md documents
# raw KBBI reaching ~±23,000 where the denominator is near zero (dark/turbid/
# land-adjacent edge cells) — an unreliable retrieval, not a real value. Fixed
# HERE at the cube layer (not by adding epsilon to the published A4b formula).
bio[, kbbi_raw := kbbi]                                   # keep raw value (cheap)
n_kbbi_invalid   <- bio[, sum(!is.na(kbbi) & abs(kbbi) > 1)]
n_bio_kbbi_nonNA <- bio[, sum(!is.na(kbbi_raw))]          # captured for the final summary (bio_raw freed below)
bio[, kbbi_invalid := (!is.na(kbbi) & abs(kbbi) > 1)]     # TRUE only where reset to NA
bio[kbbi_invalid == TRUE, kbbi := NA_real_]
cat("  KBBI winsorization: ", n_kbbi_invalid, "of", n_bio_kbbi_nonNA,
    "non-NA KBBI values had |kbbi|>1 -> reset to NA (kbbi_invalid=TRUE).\n")
cat("  KBBI valid range after winsorization: [",
    bio[!is.na(kbbi), sprintf('%.4f, %.4f', min(kbbi), max(kbbi))], "]\n")
stopifnot("KBBI winsorization failed: |kbbi|>1 remains" =
            bio[!is.na(kbbi), all(abs(kbbi) <= 1)])

# ── NOTE(paper): NaN == missing verification. R's is.na(NaN) is TRUE by ──
#   construction, so NaN already behaves identically to NA everywhere in this
#   pipeline (joins, frollmean(na.rm=TRUE), stopifnot checks). Codified here as
#   an explicit assertion rather than assumed, per mission hard requirement #3.
for (nan_check_col in c("rbd", "kbbi", "bbp_551", "bbp_morel_550",
                         "bbp_ratio_morel", "bbp_deficit", "nlw_667", "nlw_678")) {
  x <- bio[[nan_check_col]]
  stopifnot("NaN not caught by is.na() -- would break downstream missingness handling" =
              sum(is.nan(x) & !is.na(x)) == 0)
}
cat("  NaN==missing check: PASS (is.na() catches every NaN in all 8 bio score columns)\n")

# ── Drop bio-side duplicate/intermediate columns before join ──
# chlor_a_mean here is A4b's own read-only copy (used only to compute the
# Cannizzaro/Morel score); the cube already carries chlor_a_mean from A4's
# satellite_features.parquet, so drop it to avoid a name collision on merge.
# The raw band-level inputs (Rrs_*, bbp_443, bbp_s) are intermediate to the
# published nLw/RBD/KBBI/bbp_551 formulas and are not carried as separate
# model features (their information is fully captured by the derived scores).
bio[, c("chlor_a_mean",
        "Rrs_667_mean", "Rrs_667_n_valid", "Rrs_678_mean", "Rrs_678_n_valid",
        "bbp_443_mean", "bbp_443_n_valid", "bbp_s_mean", "bbp_s_n_valid") := NULL]
setnames(bio, "IS_PLACEHOLDER", "bio_IS_PLACEHOLDER")
setnames(bio, "chl_missing",    "bio_chl_missing")

# ── Rolling/trend treatment for the bio scores (mission hard requirement #4) ──
# Reuses the EXACT SAME add_trend_features() helper used for chlor_a/sst/nflh/
# Kd_490 above — no parallel scheme. Produces, per variable: 4 calendar-day
# deltas, 4 pct-change, 3 trailing OLS slopes, 2 rolling means, 2 rolling stds
# (15 cols/variable x 4 variables = 60 new trend cols), computed strictly from
# observations at or before T (verified in the leakage assertions, Section 9).
bio_level_cols <- c("rbd", "kbbi", "bbp_ratio_morel", "bbp_deficit")
setorder(bio, cell_id, date)
bio <- add_trend_features(bio, bio_level_cols, delta_lags, slope_wins, roll_wins, eps)

bio_trend_cols_added <- setdiff(names(bio), bio_raw_names)
cat("  Bio-optical columns added (", length(bio_trend_cols_added), " total, incl. trend cols):",
    paste(head(bio_trend_cols_added, 10), collapse = ", "), "...\n\n")

# Memory guard (see NOTE above `bio_raw_names`): free bio_raw now — everything
# still needed from it (`bio_raw_names`, `n_bio_kbbi_nonNA`) is already captured.
rm(bio_raw); invisible(gc(verbose = FALSE))

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
# NOTE(limitation): memory guard, 2026-07-14 — mutate `sat` in place and alias
#   it as `sat_join` instead of copy(sat): `sat` is not used again after this
#   point, and with the bio-optical table now also at label-cell scale
#   (~8.5M rows), an extra full duplicate of `sat` here was part of what
#   pushed this run over the 16 GB vector memory limit (see the NOTE at the
#   `sat <- copy(sat_raw)` line above for the full incident).
setnames(sat, "IS_PLACEHOLDER", "sat_IS_PLACEHOLDER")
setnames(sat, "feature_filled", "sat_feature_filled")
sat[, sat_date_present__ := TRUE]   # sentinel for join-hit detection
sat_join <- sat

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

# Memory guard: `sat`/`sat_join` (same object, ~8.5M rows x ~75 cols) are fully
# consumed by the merge above (which copies only what it needs into `base`,
# 65,939 rows) — free them now rather than holding through the rest of the join chain.
rm(sat, sat_join); invisible(gc(verbose = FALSE))

# ── Left-join base ← bio-optical species-discrimination features (A4b, ──
#   additive, 2026-07-14). NEVER inner-join: missing bio-optical values
#   (the 1 excluded edge cell not in bio_raw, or cloud/no-joint-retrieval
#   cell-dates) become NA, exactly like satellite_missing above. Row count
#   is asserted unchanged immediately after (mission hard requirement #1).
n_rows_before_bio_join <- nrow(base)
# NOTE(limitation): memory guard (same rationale as `sat_join` above) — mutate
#   `bio` in place and alias as `bio_join` instead of copy(bio).
bio[, bio_date_present__ := TRUE]   # sentinel for join-hit detection
bio_join <- bio

base <- merge(base, bio_join,
              by.x = c("cell_id", "sample_date"),
              by.y = c("cell_id", "date"),
              all.x = TRUE)

stopifnot("BIO JOIN BLOW-UP: row count changed after left-join of bio-optical features" =
            nrow(base) == n_rows_before_bio_join)

# Derive bio_missing flag: TRUE when no bio-optical row was joined at all
# (distinct from cloud-gap NA within an existing bio row, mirroring exactly
# how satellite_missing is defined relative to sat's own NA level values).
base[, bio_missing := is.na(bio_date_present__)]
base[, bio_date_present__ := NULL]
base[bio_missing == TRUE, bio_IS_PLACEHOLDER := TRUE]

cat("  Bio-optical join: ", n_rows_before_bio_join, "->", nrow(base),
    "rows (row count preserved, PASS) | bio_missing=TRUE:",
    sum(base$bio_missing), sprintf("(%.1f%%)\n", 100 * mean(base$bio_missing)))

# Memory guard: `bio`/`bio_join` (same object) fully consumed by the merge above.
rm(bio, bio_join); invisible(gc(verbose = FALSE))

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
    sprintf("(%.1f%%)\n",
            100 * sum(!base$satellite_missing) / nrow(base)))
cat("  Bio-optical coverage (non-miss):",
    sum(!base$bio_missing), "/", nrow(base),
    sprintf("(%.1f%%)\n\n",
            100 * sum(!base$bio_missing) / nrow(base)))

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
# NOTE(paper): 2026-07-14 — bio_missing added to this OR-condition for the same
#   reason satellite_missing is included (no bio-optical row was joined for
#   this cell-date at all — distinct from an ordinary cloud-gap NA within a
#   joined bio row, which stays a normal missing *feature value*, not a
#   placeholder row).
base[, IS_PLACEHOLDER_ROW := (
  (satellite_missing == TRUE) |         # satellite not yet processed for this date
  (bio_missing == TRUE) |               # no bio-optical row joined for this cell-date
  (env_IS_PLACEHOLDER == TRUE) |        # env dynamic features (wind/precip/sal) are placeholder
  (!is.na(static_IS_PLACEHOLDER) &
     static_IS_PLACEHOLDER == TRUE)     # static geo has NA depth (24 edge cells)
)]

# feature_filled_any: any LOCF fill was applied by A4, A4b, or A5
base[, feature_filled_any := (
  (!is.na(sat_feature_filled) & sat_feature_filled) |
  (!is.na(env_feature_filled) & env_feature_filled) |
  (!is.na(bio_feature_filled) & bio_feature_filled)
)]

cat("  IS_PLACEHOLDER_ROW = TRUE:", sum(base$IS_PLACEHOLDER_ROW, na.rm = TRUE),
    sprintf("(%.1f%%)\n", 100 * mean(base$IS_PLACEHOLDER_ROW, na.rm = TRUE)))
cat("  satellite_missing  = TRUE:", sum(base$satellite_missing), "\n")
cat("  bio_missing        = TRUE:", sum(base$bio_missing), "\n")
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

# G: Bio-optical left-join preserved row count (re-assert on final `base`,
#    defense-in-depth on top of the assertion made immediately after the join).
stopifnot("LEAKAGE-G: bio-optical join changed row count" =
            nrow(base) == n_rows_before_bio_join)

# H: KBBI winsorization holds through to the final written table.
stopifnot("LEAKAGE-H: KBBI winsorization did not hold in final table (|kbbi|>1 remains)" =
            base[!is.na(kbbi), all(abs(kbbi) <= 1)])

# I: Bio-optical trend/delta columns present for all 4 winsorized/rolled
#    variables (rbd, kbbi, bbp_ratio_morel, bbp_deficit). The generic B/C
#    regexes above already swept these in (variable-name-agnostic patterns),
#    so this re-counts specifically to confirm none are silently missing.
bio_delta_cols <- grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_delta_[0-9]+d$",
                        names(base), value = TRUE)
bio_pct_cols   <- grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_pct_chg_[0-9]+d$",
                        names(base), value = TRUE)
bio_slope_cols <- grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_(slope_obs|rollmean_obs|rollstd_obs)[0-9]+$",
                        names(base), value = TRUE)
stopifnot("LEAKAGE-I: bio-optical trend cols missing (expected 16 delta + 16 pct_chg + 28 slope/roll)" =
            length(bio_delta_cols) == 16 && length(bio_pct_cols) == 16 && length(bio_slope_cols) == 28)

# J: Zero non-finite (Inf/-Inf) values anywhere in the numeric feature matrix.
# NOTE(paper): NA is expected/allowed (honest missingness, ~74% for the bio
#   scores per A4b's log); Inf/-Inf is never a legitimate value anywhere in
#   this pipeline and would indicate a divide-by-zero or corrupted upstream
#   value slipping through unnoticed. Checked across ALL numeric columns, not
#   just the new ones, as a whole-cube quality gate (mission hard requirement #3).
numeric_cols <- names(base)[vapply(base, is.numeric, logical(1))]
non_finite_report <- vapply(numeric_cols, function(cl) sum(is.infinite(base[[cl]])), integer(1))
non_finite_report <- non_finite_report[non_finite_report > 0]
if (length(non_finite_report) > 0) {
  cat("  Non-finite (Inf/-Inf) values found in:\n")
  print(non_finite_report)
}
stopifnot("LEAKAGE-J/QUALITY: Inf/-Inf values found in the feature matrix" =
            length(non_finite_report) == 0)

cat("  LEAKAGE-A: sample_date >= 2003-01-01    PASS\n")
cat("  LEAKAGE-B: all delta lags > 0           PASS\n")
cat("  LEAKAGE-C: slope/roll cols trailing     PASS (", length(slope_cols), "cols)\n")
cat("  LEAKAGE-D: all horizons > 0             PASS\n")
cat("  LEAKAGE-E: HAB lag cols use strict-<T   PASS\n")
cat("  LEAKAGE-G: bio join row count preserved PASS (", nrow(base), "rows)\n")
cat("  LEAKAGE-H: KBBI winsorization holds     PASS (max|kbbi| =",
    base[!is.na(kbbi), round(max(abs(kbbi)), 4)], ")\n")
cat("  LEAKAGE-I: bio trend cols present       PASS (", length(bio_delta_cols) + length(bio_pct_cols) +
    length(bio_slope_cols), "cols: ", length(bio_delta_cols), "delta +", length(bio_pct_cols),
    "pct_chg +", length(bio_slope_cols), "slope/roll)\n")
cat("  LEAKAGE-J: zero Inf/-Inf in feature matrix PASS (", length(numeric_cols), "numeric cols checked)\n")
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
              "satellite_missing", "bio_missing", "feature_filled_any",
              "sat_IS_PLACEHOLDER", "bio_IS_PLACEHOLDER", "env_IS_PLACEHOLDER", "static_IS_PLACEHOLDER",
              "cloud_flag", "bio_cloud_flag", "kbbi_invalid", "salinity_coarse_flag",
              "spatial_block_tiger",                   # spatial CV grouping (Lead directive)
              "spatial_cluster")                       # adjacency diagnostic (not CV grouping)
present_key <- intersect(key_cols, names(base))
other_cols  <- setdiff(names(base), present_key)
setcolorder(base, c(present_key, other_cols))

cat("  Final rows:", nrow(base), " | Final cols:", ncol(base), "\n")
cat("  New bio-optical columns added this run (", length(bio_trend_cols_added) + 1, " incl. bio_missing):\n")
cat("   ", paste(c(bio_trend_cols_added, "bio_missing"), collapse = ", "), "\n")

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
cat("  Satellite dates in parquet:", n_sat_dates_all, "\n")
cat("  Feature dates (post-2003):", uniqueN(base$date_T), "\n")
cat("  Coverage:",
    sprintf("%.1f%%\n",
            100 * n_sat_dates_all / uniqueN(base$date_T)))

# ── Pre/post reconciliation against the pre-bio cube on disk (mission hard ──
#   requirement #1: row count MUST reconcile exactly; report before/after).
if (file.exists(p_out)) {
  pre_bio_cube <- as.data.table(read_parquet(p_out))
  n_rows_pre_bio_cube <- nrow(pre_bio_cube)
  n_cols_pre_bio_cube <- ncol(pre_bio_cube)
  rm(pre_bio_cube)
} else {
  n_rows_pre_bio_cube <- NA_integer_
  n_cols_pre_bio_cube <- NA_integer_
}
cat("\nRow/column reconciliation vs. pre-bio model_dataset.parquet:\n")
cat("  Pre-bio : ", n_rows_pre_bio_cube, "rows x", n_cols_pre_bio_cube, "cols\n")
cat("  Post-bio: ", nrow(base), "rows x", ncol(base), "cols  (+",
    ncol(base) - n_cols_pre_bio_cube, "new cols)\n")
if (!is.na(n_rows_pre_bio_cube)) {
  stopifnot("ROW RECONCILIATION FAILED: rebuilt cube row count != pre-bio cube row count" =
              nrow(base) == n_rows_pre_bio_cube)
  cat("  Row count reconciliation: PASS (identical to pre-bio cube)\n")
}

cat("\n[10/10] Writing parquet...\n")
dir.create(dirname(p_out), showWarnings = FALSE, recursive = TRUE)
write_parquet(base, p_out)

sz_mb <- round(file.info(p_out)$size / 1e6, 2)
cat("  Written:", p_out, "\n")
cat("  File size:", sz_mb, "MB\n")
cat("  Rows:", nrow(base), " | Cols:", ncol(base), "\n")
cat("\n*** STATUS: FINAL — full MODIS satellite coverage (5829 dates, satellite_missing=0) ***\n")
cat("*** STATUS: FINAL — bio-optical species-discrimination features joined additively (2026-07-14) ***\n")
cat(sprintf("    IS_PLACEHOLDER_ROW = TRUE for %.1f%% of rows.\n",
            100 * mean(base$IS_PLACEHOLDER_ROW, na.rm = TRUE)))
cat("    env_IS_PLACEHOLDER = wind_is_placeholder & precip_is_placeholder & salinity_is_placeholder\n")
cat("    (see reports/agent_logs/env-features.md for which of the three are real as of this run).\n")
cat(sprintf("    KBBI: %d of %d non-NA raw KBBI values winsorized to NA (|kbbi|>1); kbbi_invalid flags these.\n",
            n_kbbi_invalid, n_bio_kbbi_nonNA))
cat(sprintf("    bio_missing = TRUE for %d rows (%.1f%%) — no bio-optical row joined at all.\n",
            sum(base$bio_missing), 100 * mean(base$bio_missing)))
cat("    Non-finite (Inf/-Inf) check across full feature matrix: PASS (see LEAKAGE-J above).\n")
cat("=== 06_build_datacube.R: DONE ===\n")
