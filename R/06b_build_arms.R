# ============================================================
# FILE:       R/06b_build_arms.R
# PURPOSE:    M1 datacube rebuild — two arms on ONE re-anchored row definition.
#             D15 row anchoring: a row is (cell_id, T = label_date - H); satellite
#             features as-of T (latest clear chlor_a in [T-7, T]); ONLY the label at
#             T+H is required (no feature-time HABSOS sample). D13 two arms:
#               Arm A (PORTABLE)     — satellite + reanalysis only, ZERO HABSOS-derived.
#               Arm B (INSTRUMENTED) — Arm A + continuous HABSOS lags (D17).
#             D18: slopes are calendar-day (_slope_Nd), not per-observation.
# INPUTS:     data/processed/habsos_labels.parquet            (labels + max_count cells/L)
#             data/processed/satellite_features.parquet       (chl/sst/nflh/Kd, dense cell-date)
#             data/processed/satellite_features_bio_optical.parquet (bio scores, dense)
#             data/raw/weather/era5_checkpoints/*.parquet     (daily wind per cell)
#             data/processed/static_geo.parquet               (depth/dist/county/block)
#             data/processed/ring1_neighbors.parquet          (queen adjacency, precomputed)
# OUTPUTS:    data/processed/model_dataset_arm_a.parquet
#             data/processed/model_dataset_arm_b.parquet
# WHY A NEW SCRIPT (not an edit of 06): re-running 06 would overwrite the frozen
#   model_dataset.parquet that best_model.rds (md5 3ea9a5...) depends on. Rule 6 keeps
#   frozen artifacts byte-intact; 06 stays the M0 baseline builder, 06b builds the M1 arms.
# NOTE(limitation): reanalysis at re-anchored T comes from the DAILY ERA5 checkpoints
#   (data/raw/weather/era5_checkpoints), not environmental_features.parquet — that parquet
#   aggregated ERA5 only to HABSOS sample dates, so it cannot serve non-HABSOS anchor dates.
#   CHIRPS precip and SMAP salinity are placeholder (NA) on every row (never landed).
# NOTE(limitation): Arm B continuous lags (D17) are HABSOS-derived and BREAK PORTABILITY
#   by design — they belong to Arm B only. A-B is the contribution, not either arm alone.
# ============================================================
Sys.setenv(ARROW_NUM_THREADS = "1")
suppressMessages({ library(arrow); library(data.table) })
arrow::set_cpu_count(1L)
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d)
        source(file.path(d,"R","00_config.R")) })

horizons   <- cfg$forecast$horizons_days          # 1,3,5,7,14
delta_lags <- cfg$trends$delta_lags_days          # 1,3,5,7 (calendar days)
slope_wins <- cfg$trends$slope_windows_days       # 3,5,7 (calendar days — D18)
roll_wins  <- cfg$trends$rolling_windows_days     # 3,7 (observations)
eps        <- cfg$trends$pct_change_epsilon
SNAP_WIN   <- 7L                                   # 8-day window [T-7, T] for the satellite as-of snap
cat("=== 06b_build_arms.R ===\nHorizons:", paste(horizons,collapse=","),
    "| slope windows (days):", paste(slope_wins,collapse=","), "\n\n")

fwc_class <- function(x) as.integer((x>1e3)+(x>1e4)+(x>1e5)+(x>1e6))   # E-06 0..4 (R/e06_stop1_distribution.R:21)

# calendar-day trend features on a per-(cell,date) table ordered by cell,date
add_trend <- function(dt, cols) {
  for (col in cols) {
    v <- sub("_mean$", "", col)
    for (k in unique(c(delta_lags, slope_wins))) {
      lagc <- paste0(v, "__lag", k)
      dl <- dt[, .(cell_id, jd = date + k, lv = get(col))]
      dt[dl, on = .(cell_id, date = jd), (lagc) := i.lv]
      dt[, (paste0(v, "_delta_", k, "d")) := get(col) - get(lagc)]
      dt[, (lagc) := NULL]
    }
    for (k in delta_lags) {                                   # % change (calendar-day)
      d <- dt[[paste0(v, "_delta_", k, "d")]]
      set(dt, j = paste0(v, "_pct_chg_", k, "d"), value = d / (abs(dt[[col]] - d) + eps) * 100)
    }
    for (k in slope_wins)                                     # D18: calendar-day rate
      set(dt, j = paste0(v, "_slope_", k, "d"), value = dt[[paste0(v, "_delta_", k, "d")]] / k)
    sq <- paste0(v, "__sq"); dt[, (sq) := get(col)^2]         # rolling (observation order)
    for (k in roll_wins) {
      mu <- paste0(v, "_rollmean_obs", k)
      dt[, (mu) := frollmean(get(col), k, na.rm = TRUE, align = "right"), by = cell_id]
      dt[, (paste0(v, "_rollstd_obs", k)) := {
        m2 <- frollmean(get(sq), k, na.rm = TRUE, align = "right"); sqrt(pmax(0, m2 - get(mu)^2)) }, by = cell_id]
    }
    dt[, (sq) := NULL]
  }
  dt
}

# ── HABSOS labels (dedup to one row per cell-day: max HAB, max cells/L) ──
hab <- as.data.table(read_parquet("data/processed/habsos_labels.parquet",
        col_select = c("cell_id","sample_date","max_count","HAB")))
hab[, sample_date := as.Date(sample_date)]
hab <- hab[, .(HAB = max(HAB), max_count = max(max_count)), by = .(cell_id, sample_date)]
label_cells <- unique(hab$cell_id)
cat("HABSOS: ", nrow(hab), " cell-day labels, ", length(label_cells), " cells\n")

# ── ANCHORS: (cell_id, date_T = label_date - H, horizon, label) for every H ──
anchors <- rbindlist(lapply(horizons, function(H)
  hab[, .(cell_id, date_T = sample_date - H, horizon = H,
          label = HAB, label_date = sample_date, label_max_count = max_count)]))
cat("Anchors (all H, pre satellite-availability filter):", nrow(anchors), "\n\n")

# ============================================================
# 1. SATELLITE LEVELS + TRENDS  ->  as-of snap to anchor T
# ============================================================
cat("[1] satellite levels + calendar-day trends ...\n")
sat <- as.data.table(read_parquet("data/processed/satellite_features.parquet"))
sat[, date := as.Date(date)]
sat <- sat[cell_id %in% label_cells]
setorder(sat, cell_id, date)
setnames(sat, "IS_PLACEHOLDER", "sat_IS_PLACEHOLDER")
setnames(sat, "feature_filled", "sat_feature_filled")
sat <- add_trend(sat, c("chlor_a_mean","sst_mean","nflh_mean","Kd_490_mean"))
sat_clear <- sat[!is.na(chlor_a_mean)]                 # snap candidates = clear chlor_a
sat_clear[, snap_date := date]
setkey(sat_clear, cell_id, date)
rm(sat); invisible(gc(FALSE))

# roll join: for each anchor, latest clear satellite date d* <= T within SNAP_WIN days
setkey(anchors, cell_id, date_T)
a_sat <- sat_clear[anchors, on = .(cell_id, date = date_T), roll = SNAP_WIN]
setnames(a_sat, "date", "date_T")
a_sat <- a_sat[!is.na(snap_date)]                      # keep anchors with a clear obs in [T-7,T]
cat("  Anchors with a clear satellite snap:", nrow(a_sat), "\n")
for (H in horizons) {
  s <- a_sat[horizon == H]
  cat(sprintf("    H=%2d: %d rows | pos_rate=%.4f\n", H, nrow(s), mean(s$label == 1)))
}
rm(sat_clear); invisible(gc(FALSE))

# ============================================================
# 2. BIO-OPTICAL (aligned to the SAME snapped date d*) + trends
# ============================================================
cat("\n[2] bio-optical features at snapped date d* ...\n")
bio <- as.data.table(read_parquet("data/processed/satellite_features_bio_optical.parquet"))
bio[, date := as.Date(date)]; bio[, cell_id := as.integer(cell_id)]
bio <- bio[cell_id %in% label_cells]
setorder(bio, cell_id, date)
# KBBI winsorization to [-1,1] (physical bound; see 06 header) — keep raw, flag invalid
bio[, kbbi_raw := kbbi]
bio[, kbbi_invalid := (!is.na(kbbi) & abs(kbbi) > 1)]
bio[kbbi_invalid == TRUE, kbbi := NA_real_]
bio[, c("Rrs_667_mean","Rrs_667_n_valid","Rrs_678_mean","Rrs_678_n_valid",
        "bbp_443_mean","bbp_443_n_valid","bbp_s_mean","bbp_s_n_valid","chlor_a_mean") := NULL]
setnames(bio, "IS_PLACEHOLDER", "bio_IS_PLACEHOLDER")
bio <- add_trend(bio, c("rbd","kbbi","bbp_ratio_morel","bbp_deficit"))
# exact join at (cell_id, d*) — bio is on the same MODIS dates as the satellite snap
bio[, snap_date := date][, date := NULL]
setkey(bio, cell_id, snap_date)
a_ab <- bio[a_sat, on = .(cell_id, snap_date)]
rm(bio); invisible(gc(FALSE))
cat("  Joined bio at d*; rows:", nrow(a_ab), "\n")

# ============================================================
# 3. REANALYSIS: ERA5 wind (daily) at exact T  +  seasonality  +  placeholders
# ============================================================
cat("\n[3] ERA5 wind (daily checkpoints) at anchor T + seasonality ...\n")
ck <- list.files("data/raw/weather/era5_checkpoints", pattern="\\.parquet$", full.names=TRUE)
wind <- rbindlist(lapply(ck, function(f) as.data.table(read_parquet(f))))
wind[, date := as.Date(date)]
wind <- wind[cell_id %in% label_cells]
setkey(wind, cell_id, date)
a_ab <- merge(a_ab, wind, by.x = c("cell_id","date_T"), by.y = c("cell_id","date"), all.x = TRUE)
rm(wind); invisible(gc(FALSE))
a_ab[, month   := as.integer(format(date_T, "%m"))]
a_ab[, doy     := as.integer(format(date_T, "%j"))]
a_ab[, doy_sin := sin(2*pi*doy/365.25)]
a_ab[, doy_cos := cos(2*pi*doy/365.25)]
# CHIRPS / SMAP never landed -> placeholder on every row (honest)
a_ab[, precip_mm := NA_real_][, precip_is_placeholder := TRUE]
a_ab[, salinity_pss := NA_real_][, salinity_is_placeholder := TRUE]
cat("  wind_is_placeholder rate:", round(mean(a_ab$wind_is_placeholder, na.rm=TRUE), 4),
    "| wind NA rows:", sum(is.na(a_ab$wind_speed_ms)), "\n")

# ============================================================
# 4. STATIC GEO (per cell)
# ============================================================
static <- as.data.table(read_parquet("data/processed/static_geo.parquet"))
setnames(static, "IS_PLACEHOLDER", "static_IS_PLACEHOLDER")
a_ab <- merge(a_ab, static, by = "cell_id", all.x = TRUE)

# ============================================================
# 5. ARM B CONTINUOUS LAGS (D17) — HABSOS-derived, strictly prior to T
# ============================================================
cat("\n[4] Arm B continuous lags (organismQuantity cells/L, strictly < T) ...\n")
keyrows <- a_ab[, .(cell_id, date_T)]                 # one row per anchor
keyrows[, rid := .I]
hab_ev <- hab[, .(cell_id, sd = sample_date, mc = max_count, hab = HAB)]

# helper: max cells/L (and severity) over own-cell habsos in [T-W, T)
# nomatch=NULL is REQUIRED: with the default nomatch=NA, every unmatched (rid, source)
# pair yields an NA row, and max()/min() with na.rm=FALSE then collapse to NA whenever a
# rid has ANY unmatched pair — which is almost always for the multi-neighbor join.
prior_max <- function(W) {
  q <- copy(keyrows)[, `:=`(ws = date_T - W, we = date_T)]
  m <- hab_ev[q, on = .(cell_id, sd >= ws, sd < we), allow.cartesian = TRUE, nomatch = NULL,
              .(rid = i.rid, mc = x.mc)]
  m[, .(v = max(mc)), by = rid]
}
p7  <- prior_max(7L);  p14 <- prior_max(14L)
sev14 <- {
  q <- copy(keyrows)[, `:=`(ws = date_T - 14L, we = date_T)]
  m <- hab_ev[q, on = .(cell_id, sd >= ws, sd < we), allow.cartesian = TRUE, nomatch = NULL,
              .(rid = i.rid, sev = fwc_class(x.mc))]
  m[, .(v = max(sev)), by = rid]
}
# days since last positive (strictly before T, same cell)
dsl <- {
  pos <- hab_ev[hab == 1L]
  q <- copy(keyrows)
  m <- pos[q, on = .(cell_id, sd < date_T), allow.cartesian = TRUE, nomatch = NULL,
           .(rid = i.rid, sd = x.sd, T = i.date_T)]
  m[, .(v = as.integer(min(T - sd))), by = rid]           # min gap = most recent prior positive
}
# neighbors max cells/L in [T-7, T)
nbr <- as.data.table(read_parquet("data/processed/ring1_neighbors.parquet"))
nbr_prior7 <- {
  q <- merge(keyrows, nbr, by = "cell_id", allow.cartesian = TRUE)   # each anchor x its neighbor cells
  q[, `:=`(ws = date_T - 7L, we = date_T)]
  m <- hab_ev[q, on = .(cell_id = neighbor_cell_id, sd >= ws, sd < we), allow.cartesian = TRUE,
              nomatch = NULL, .(rid = i.rid, mc = x.mc)]
  m[, .(v = max(mc)), by = rid]
}
keyrows[p7,  on = "rid", max_cells_prior_7d  := i.v]
keyrows[p14, on = "rid", max_cells_prior_14d := i.v]
keyrows[sev14, on = "rid", max_severity_prior_14d := i.v]
keyrows[dsl,  on = "rid", days_since_last_positive := i.v]
keyrows[nbr_prior7, on = "rid", max_cells_neighbors_prior_7d := i.v]
keyrows[, log10_max_cells_prior_7d  := log10(1 + max_cells_prior_7d)]
keyrows[, log10_max_cells_prior_14d := log10(1 + max_cells_prior_14d)]
keyrows[, log10_max_cells_neighbors_prior_7d := log10(1 + max_cells_neighbors_prior_7d)]
armB_lag_cols <- c("log10_max_cells_prior_7d","log10_max_cells_prior_14d",
                   "days_since_last_positive","max_severity_prior_14d",
                   "log10_max_cells_neighbors_prior_7d")
a_ab <- cbind(a_ab, keyrows[, ..armB_lag_cols])          # keyrows is row-aligned to a_ab (rid = .I)

# ============================================================
# 6. ASSEMBLE ARMS — identical rows/order; Arm A drops all HABSOS-derived cols
# ============================================================
setorder(a_ab, cell_id, date_T, horizon)                 # deterministic order for BOTH arms (D-16)
# HABSOS-derived columns that must NOT appear in Arm A:
habsos_derived <- c(armB_lag_cols, "label_max_count",
                    "max_cells_prior_7d","max_cells_prior_14d","max_cells_neighbors_prior_7d")
drop_from_a <- intersect(habsos_derived, names(a_ab))
arm_a <- copy(a_ab)[, (drop_from_a) := NULL]
# Arm B keeps the continuous lags but not the leakage-prone label_max_count (cells/L at T+H).
arm_b <- copy(a_ab)
b_drop <- intersect("label_max_count", names(arm_b))
if (length(b_drop)) arm_b[, (b_drop) := NULL]

# parity assertions (D-16: same rows, same order)
stopifnot("PARITY: row counts differ" = nrow(arm_a) == nrow(arm_b))
stopifnot("PARITY: key sets/order differ" =
            identical(arm_a[, .(cell_id, date_T, horizon, label)],
                      arm_b[, .(cell_id, date_T, horizon, label)]))
cat("\n[5] Parity: identical (cell_id, date_T, horizon, label) sets + order — PASS (", nrow(arm_a), "rows)\n")

# ============================================================
# 7. WRITE
# ============================================================
write_parquet(arm_a, "data/processed/model_dataset_arm_a.parquet")
write_parquet(arm_b, "data/processed/model_dataset_arm_b.parquet")
cat("\nArm A:", nrow(arm_a), "rows x", ncol(arm_a), "cols ->", "model_dataset_arm_a.parquet\n")
cat("Arm B:", nrow(arm_b), "rows x", ncol(arm_b), "cols ->", "model_dataset_arm_b.parquet\n")
cat("\nPer-horizon row counts + positive rate:\n")
for (H in horizons) {
  s <- arm_a[horizon == H]
  cat(sprintf("  H=%2d: %d rows | pos_rate=%.4f\n", H, nrow(s), mean(s$label == 1)))
}
cat("\n=== 06b_build_arms.R DONE ===\n")
