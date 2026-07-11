# ============================================================
# FILE:       R/09_gis_export.R
# PURPOSE:    M2 GIS risk mapping + intra-cell attention drill-down.
#             Applies the current best model to every grid cell for
#             chosen date(s) and exports risk layers + interactive map.
#             MODEL-AGNOSTIC: the predict step is isolated in
#             predict_risk(backend, newdata) — swapping RF -> transformer
#             = change MODEL_PATH + predict() call inside predict_risk().
#             All map/plotting logic is model-blind.
#             Current backend: H=7 temporal RF (outputs/models/best_model.rds).
#             Per author directive (reports/decisions.md 2026-07-12),
#             the PUBLISHED GIS will visualize the Stage-2 transformer;
#             this RF run is the validated swappable placeholder until M3.
# INPUTS:     outputs/models/best_model.rds  (H=7 temporal RF, A7)
#             data/processed/model_dataset.parquet  (65,939 x 114, FINAL)
#             data/processed/study_area_grid.gpkg   (4,743 cells, EPSG:5070)
#             data/processed/static_geo.parquet     (depth_m, dist_to_shore)
#             NASA Earthdata (~/.netrc) for MODIS repull [optional; D12 drill-down]
# OUTPUTS:    outputs/gis/hab_risk_grid.gpkg
#             outputs/gis/hab_risk_raster.tif
#             outputs/gis/priority_monitoring_zones.gpkg
#             outputs/gis/intracell_attention.gpkg
#             outputs/maps/hab_risk_map.html
#             reports/agent_logs/gis.md
# TECHNIQUES: ranger RF prediction (swappable via predict_risk());
#             median imputation + missingness flag (IDENTICAL to A7);
#             log1p transform (IDENTICAL to A7 -- mismatch = silent corruption);
#             EPSG:5070 for analysis, EPSG:4326 for leaflet;
#             ETOPO (NOAA, public domain) preferred per decisions.md 2026-07-11;
#             CartoDB.Positron tiles as leaflet basemap (non-commercial safe);
#             intra-cell attention: native ~4km MODIS repull, convergence overlay;
#             terra::rasterize() for risk raster.
# CITATIONS:  Wright & Ziegler 2017 (ranger); Hu et al. 2022 (study area);
#             NASA OB.DAAC MODIS-Aqua L3m (DOI: 10.5067/AQUA/MODIS/L3M/CHL/2022.0);
#             ETOPO 2022 (NOAA NCEI, public domain).
# ============================================================

# NOTE(paper): This script is model-agnostic by design (decisions.md 2026-07-12).
#              The published GIS will visualize the Stage-2 transformer forecast;
#              the current RF run serves as a validated swappable backend.
#              Swapping backend: change MODEL_PATH and predict_risk() only.
# NOTE(limitation): H=7 day forecast shown; at this horizon sub-cell pixel patterns
#                   represent PRE-BLOOM PRECURSOR conditions that may drift with
#                   wind and current before the bloom lands on day T+7 (sec. 2.3).
# NOTE(paper): ETOPO 2022 preferred for published basemap (NOAA, public domain).
#              CartoDB.Positron tiles used here (leaflet); any published
#              static figure should use ETOPO downloaded from NOAA NCEI.

# ---- ARROW THREAD GUARD: source config FIRST --------------------------------
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

# ---- LIBRARIES --------------------------------------------------------------
suppressPackageStartupMessages({
  library(arrow)
  arrow::set_cpu_count(1L)           # belt-and-suspenders arrow deadlock guard
  library(data.table)
  library(sf)
  library(terra)
  library(ranger)                    # needed for RF predict() in predict_risk()
  library(leaflet)
  library(htmlwidgets)
  library(htmltools)
})

message("[A9] Libraries loaded.")

# ---- PATHS & CONSTANTS ------------------------------------------------------
# NOTE(paper): MODEL_PATH is the sole configuration point for the backend.
#              Change this path + predict_risk() internals to swap RF -> transformer.
MODEL_PATH   <- proj_path("outputs/models/best_model.rds")
CUBE_PATH    <- proj_path("data/processed/model_dataset.parquet")
GRID_PATH    <- proj_path("data/processed/study_area_grid.gpkg")
STATIC_PATH  <- proj_path("data/processed/static_geo.parquet")
OUT_GIS      <- proj_path("outputs/gis")
OUT_MAPS     <- proj_path("outputs/maps")
LOG_PATH     <- proj_path("reports/agent_logs/gis.md")

dir.create(OUT_GIS,  showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_MAPS, showWarnings = FALSE, recursive = TRUE)

# NOTE(paper): 2016-10-24 chosen as MAP_DATE -- test-set date (year >= 2016, temporal
#              split), 13 of 25 cells HAB_H7=1 (52%), 72% cloud-free satellite
#              coverage. Coincides with active West Florida Shelf bloom period.
#              Forecast horizon H=7: map shows predicted risk for ~2016-10-31.
MAP_DATE       <- as.Date("2016-10-24")

# Risk threshold for priority monitoring zones.
# NOTE(paper): 0.40 threshold prioritizes recall (PLAN sec. 9: a missed bloom > false alarm).
RISK_THRESHOLD <- 0.40

# Convergence criteria for intra-cell attention (D12/sec. 2.3)
CONVERGE_CHL_QUANTILE  <- 0.75   # pixel chl-a above this quantile within cell = elevated
CONVERGE_DEPTH_SHALLOW <- -30    # metres (negative = below sea level, GEBCO convention)
CONVERGE_NEARSHORE_M   <- 25000  # within 25 km of coast

# NOTE(paper): same transforms as A7/07_modeling.R -- MUST be identical.
#              Any mismatch here silently corrupts map predictions.
LOG_FEATURES <- c("chlor_a_mean", "nflh_mean", "Kd_490_mean")

# ALWAYS_EXCLUDE: identical copy from A7/07_modeling.R.
# NOTE(paper): any difference from A7 will corrupt map predictions.
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
  "wind_u_ms", "wind_v_ms", "wind_speed_ms", "wind_dir_deg",
  "precip_mm", "salinity_pss"
)

# ============================================================
# SECTION 1: MODEL-AGNOSTIC BACKEND INTERFACE
# All model-specific code lives here and ONLY here.
# Swap RF -> transformer: replace load_backend() and the
# predict() call inside predict_risk(). Map/export logic is blind.
# ============================================================

#' Load prediction backend from a saved model path.
#' Returns a list: $rf, $feat_cols, $na_cols, $train_medians, $horizon, $split.
#' For transformer swap: return transformer object and update predict_risk().
load_backend <- function(model_path) {
  # NOTE(paper): MODEL_PATH is the sole configuration point. Swap RF -> transformer:
  #              point MODEL_PATH at transformer checkpoint; update predict_risk() call.
  if (!file.exists(model_path)) stop("[A9] Backend not found: ", model_path)
  obj <- readRDS(model_path)
  required <- c("rf", "feat_cols", "na_cols", "train_medians", "horizon")
  missing  <- setdiff(required, names(obj))
  if (length(missing) > 0) stop("[A9] Backend missing keys: ", paste(missing, collapse = ", "))
  message("[A9] Backend loaded: H=", obj$horizon, " split=", obj$split,
          " | feat_cols=", length(obj$feat_cols), " | na_cols=", length(obj$na_cols))
  obj
}

#' Apply the feature pipeline to newdata, aligned to backend$feat_cols.
#' IDENTICAL transforms to A7/07_modeling.R. Returns data.table.
#' @param backend  from load_backend()
#' @param newdata  data.table with raw feature columns
apply_feature_pipeline <- function(backend, newdata) {
  nd <- copy(newdata)

  # log1p transforms (IDENTICAL to A7)
  for (feat in LOG_FEATURES) {
    if (feat %in% names(nd)) {
      if (feat == "nflh_mean") {
        nd[, (feat) := sign(get(feat)) * log1p(abs(get(feat)))]
      } else {
        nd[, (feat) := log1p(pmax(get(feat), 0))]
      }
    }
  }

  # Median imputation + missingness flag (IDENTICAL to A7)
  for (col in backend$na_cols) {
    na_col <- paste0(col, "_is_missing")
    nd[[na_col]] <- as.integer(is.na(nd[[col]]))
    med <- backend$train_medians[[col]]
    if (is.na(med) || is.null(med)) med <- 0
    set(nd, which(is.na(nd[[col]])), col, med)
  }

  # Align to expected feature columns; add any missing ones
  for (fc in backend$feat_cols) {
    if (!fc %in% names(nd)) {
      if (endsWith(fc, "_is_missing")) {
        nd[[fc]] <- 0L
      } else {
        nd[[fc]] <- 0.0
        warning("[A9] apply_feature_pipeline: missing col '", fc, "' filled with 0.")
      }
    }
  }

  nd[, backend$feat_cols, with = FALSE]
}

#' Predict P(HAB=1) for each row in newdata.
#' @param backend  from load_backend()
#' @param newdata  data.table with raw feature columns
#' @return numeric vector of probabilities, length == nrow(newdata)
#'
#' TO SWAP BACKEND (RF -> transformer):
#'   1. Update load_backend() to load the transformer checkpoint.
#'   2. Replace the ranger::predict() call below with the transformer's
#'      inference (e.g., transformer$predict(newdata_tensor)).
#'   3. Return numeric vector of P(HAB=1) in [0,1].
#'   4. No other code in this file changes.
predict_risk <- function(backend, newdata) {
  nd_aligned <- apply_feature_pipeline(backend, newdata)
  # NOTE(paper): the ranger predict() call is the ONLY model-specific line in the
  #              GIS pipeline. Replace this for the transformer swap.
  probs <- predict(backend$rf, data = nd_aligned)$predictions[, "1"]
  return(probs)
}

# ============================================================
# SECTION 2: LOAD DATA
# ============================================================

message("[A9] Loading backend model ...")
backend <- load_backend(MODEL_PATH)

message("[A9] Loading model_dataset.parquet ...")
dt_full <- as.data.table(arrow::read_parquet(CUBE_PATH))
dt_full[["date_T"]] <- as.Date(as.character(dt_full[["date_T"]]))
message("[A9] Loaded: ", nrow(dt_full), " rows x ", ncol(dt_full), " cols")

message("[A9] Loading study area grid ...")
grid_sf <- st_read(GRID_PATH, quiet = TRUE)
# NOTE(cite): EPSG:5070 (Albers Equal Area) for metric-consistent area analysis.
stopifnot(st_crs(grid_sf)$epsg == 5070L)
message("[A9] Grid: ", nrow(grid_sf), " cells, CRS: EPSG:5070")

message("[A9] Loading static geo features ...")
static_dt <- as.data.table(arrow::read_parquet(STATIC_PATH))

# ============================================================
# SECTION 3: CHOOSE MAPPED DATE & BUILD PREDICTION DATA
# ============================================================

# NOTE(paper): MAP_DATE is feature observation date T. Forecast is for T+H=T+7.
#              Temporal split: train <= 2015, test >= 2016. MAP_DATE in test set
#              -> honest out-of-sample forecast on the map.
message("[A9] Mapped date: ", as.character(MAP_DATE))

dt_map <- dt_full[date_T == MAP_DATE]
if (nrow(dt_map) == 0) {
  avail_dates <- sort(unique(dt_full$date_T))
  closest     <- avail_dates[which.min(abs(avail_dates - MAP_DATE))]
  message("[A9] WARNING: MAP_DATE not in dataset; falling back to ", closest)
  MAP_DATE <- closest
  dt_map   <- dt_full[date_T == MAP_DATE]
}
message("[A9] Cells with data on MAP_DATE: ", nrow(dt_map),
        " | HAB_H7 positives: ", sum(dt_map$HAB_H7, na.rm = TRUE),
        "/", sum(!is.na(dt_map$HAB_H7)))

target_col <- paste0("HAB_H", backend$horizon)
excl_cols  <- c(ALWAYS_EXCLUDE, "year",
                setdiff(paste0("HAB_H", c(1, 3, 5, 7, 14)), target_col))

# Metadata columns to carry through (not used as features)
keep_meta <- intersect(
  c("cell_id", "date_T", target_col, "cloud_flag",
    "chlor_a_mean", "nflh_mean", "Kd_490_mean", "sst_mean",
    "depth_m", "dist_to_shore_m", "centroid_lon", "centroid_lat",
    "county_name", "spatial_block_tiger"),
  names(dt_map)
)

feat_input_cols <- setdiff(names(dt_map), c(excl_cols, target_col, "year"))

# ============================================================
# SECTION 4: APPLY MODEL -> RISK PREDICTIONS
# ============================================================

message("[A9] Running predict_risk() ...")
nd_for_pred <- dt_map[, feat_input_cols, with = FALSE]
risk_probs  <- predict_risk(backend, nd_for_pred)
stopifnot(length(risk_probs) == nrow(dt_map))
message("[A9] Predictions: min=", round(min(risk_probs), 3),
        " max=", round(max(risk_probs), 3),
        " mean=", round(mean(risk_probs), 3),
        " | flagged (>", RISK_THRESHOLD, "): ", sum(risk_probs > RISK_THRESHOLD))

# Assemble risk table
risk_dt <- dt_map[, keep_meta, with = FALSE]
risk_dt[, predicted_risk_H7 := risk_probs]
risk_dt[, flagged := predicted_risk_H7 > RISK_THRESHOLD]
risk_dt[, risk_class := fcase(
  predicted_risk_H7 >= 0.70, "HIGH (>=0.70)",
  predicted_risk_H7 >= 0.40, "MODERATE (0.40-0.70)",
  predicted_risk_H7 >= 0.20, "LOW-MODERATE (0.20-0.40)",
  default = "LOW (<0.20)"
)]
# NOTE(paper): risk classes = model output categories, NOT verified risk thresholds.
#              P(HAB=1) at H=7 from RF applied to features at day T. NOT observed blooms.

# ============================================================
# SECTION 5: BUILD RISK GRID (hab_risk_grid.gpkg)
# ============================================================

message("[A9] Building risk grid ...")

risk_grid_sf <- merge(grid_sf, risk_dt, by = "cell_id", all.x = TRUE)
risk_grid_sf$forecast_date_T      <- as.character(MAP_DATE)
risk_grid_sf$forecast_horizon_H   <- backend$horizon
risk_grid_sf$forecast_date_target <- as.character(MAP_DATE + backend$horizon)
risk_grid_sf$backend_model        <- "Random Forest (Stage-1 RF, ranger)"
risk_grid_sf$backend_swappable    <- "YES -- change MODEL_PATH in 09_gis_export.R"
risk_grid_sf$is_model_output      <- "TRUE -- NOT observed blooms. Risk forecast only."
risk_grid_sf$honesty_label        <- paste0(
  "FORECAST H=", backend$horizon, " | MODEL: RF Stage-1 | ",
  "NOT OBSERVED BLOOMS | Feature date: ", MAP_DATE,
  " | Predicted bloom date: ~", MAP_DATE + backend$horizon
)

stopifnot(st_crs(risk_grid_sf)$epsg == 5070L)
out_risk_grid <- file.path(OUT_GIS, "hab_risk_grid.gpkg")
st_write(risk_grid_sf, out_risk_grid, delete_dsn = TRUE, quiet = TRUE)
message("[A9] hab_risk_grid.gpkg written: ", nrow(risk_grid_sf), " cells")

# ============================================================
# SECTION 6: BUILD RISK RASTER (hab_risk_raster.tif)
# ============================================================

message("[A9] Building risk raster ...")

grid_bbox  <- st_bbox(grid_sf)
r_template <- terra::rast(
  xmin = grid_bbox["xmin"], xmax = grid_bbox["xmax"],
  ymin = grid_bbox["ymin"], ymax = grid_bbox["ymax"],
  resolution = c(cfg$grid$cellsize_m, cfg$grid$cellsize_m),
  crs = "EPSG:5070"
)

# NOTE(paper): raster resolution == 10 km cell size. Each pixel = one model prediction unit.
#              This is NOT sub-cell resolution -- it directly represents the model's unit.
cells_with_risk <- risk_grid_sf[!is.na(risk_grid_sf$predicted_risk_H7), ]
r_risk <- terra::rasterize(
  terra::vect(cells_with_risk), r_template,
  field = "predicted_risk_H7", fun = "mean"
)
names(r_risk) <- paste0("predicted_risk_H", backend$horizon)

out_raster <- file.path(OUT_GIS, "hab_risk_raster.tif")
terra::writeRaster(r_risk, out_raster, overwrite = TRUE)
message("[A9] hab_risk_raster.tif written")

# ============================================================
# SECTION 7: PRIORITY MONITORING ZONES (priority_monitoring_zones.gpkg)
# ============================================================

message("[A9] Building priority monitoring zones ...")

flagged_sf <- risk_grid_sf[!is.na(risk_grid_sf$predicted_risk_H7) &
                             !is.na(risk_grid_sf$flagged) &
                             risk_grid_sf$flagged == TRUE, ]
# NOTE(paper): priority zones = cells where P(HAB=1, H=7) > RISK_THRESHOLD=0.40.
#              Identifies cells warranting heightened sampling attention.
#              Model-derived risk flags -- NOT confirmed bloom detections.
if (nrow(flagged_sf) > 0) {
  flagged_sf$monitoring_priority <- "HIGH RISK -- model-flagged for enhanced monitoring"
  flagged_sf$zone_basis          <- paste0("P(HAB=1, H=", backend$horizon, ") > ", RISK_THRESHOLD)
  flagged_sf$sampling_rationale  <- paste0(
    "Flagged by RF forecast (H=", backend$horizon, "). ",
    "Consider enhanced sampling near T+H (~", MAP_DATE + backend$horizon, ")."
  )
}

out_zones <- file.path(OUT_GIS, "priority_monitoring_zones.gpkg")
if (nrow(flagged_sf) > 0) {
  st_write(flagged_sf, out_zones, delete_dsn = TRUE, quiet = TRUE)
  message("[A9] priority_monitoring_zones.gpkg: ", nrow(flagged_sf), " cells")
} else {
  message("[A9] WARNING: No cells exceed threshold. Writing empty placeholder.")
  st_write(risk_grid_sf[0, ], out_zones, delete_dsn = TRUE, quiet = TRUE)
}

# Coastal region risk summary
region_summary <- as.data.table(st_drop_geometry(risk_grid_sf))[
  !is.na(predicted_risk_H7),
  .(n_cells = .N, n_flagged = sum(flagged, na.rm = TRUE),
    pct_flagged = round(100 * mean(flagged, na.rm = TRUE), 1),
    mean_risk   = round(mean(predicted_risk_H7, na.rm = TRUE), 3),
    max_risk    = round(max(predicted_risk_H7, na.rm = TRUE), 3)),
  by = county_name][order(-n_flagged, -mean_risk)]
message("[A9] Coastal region summary:\n"); print(region_summary)

# ============================================================
# SECTION 8: INTRA-CELL ATTENTION DRILL-DOWN (D12 / sec. 2.3)
# For flagged cells: re-derive native ~4km MODIS pixels for MAP_DATE,
# render sub-cell feature-intensity overlay, highlight convergence
# (high chl-a pixel intersect shallow/nearshore static context).
# HONESTY RULES (sec. 2.3):
#   - Shows features, NOT predictions. Label = "DIAGNOSTIC".
#   - Floor = native ~4km MODIS pixel; nothing rendered finer.
#   - Prefer LEVEL fields (chl-a); omit pixel-level trend fields.
#   - Convergence = multiple inputs agree on location.
#   - Long-horizon (H=7) carries precursor-drift caveat.
# ============================================================

message("[A9] === Intra-cell attention drill-down (D12) ===")

# NOTE(paper): the drill-down shows WHERE within a flagged 10 km cell
#              the flag-driving satellite conditions concentrate.
#              It is a diagnostic feature-intensity overlay -- NOT a validated
#              sub-cell forecast. Floor is native ~4km MODIS pixel (~16 km2 patch).
#              Nothing is rendered below native pixel -- finer rendering would
#              repeat the same value (false precision).
# NOTE(limitation): at H=7 forecast horizon, pixel-level satellite patterns are
#                   pre-bloom precursor conditions. They may drift with wind and
#                   current before the bloom lands on day T+7 (sec. 2.3).
# NOTE(limitation): pixel-level trend fields omitted per sec. 2.3: noisiest at
#                   native resolution due to cloud gaps. Only LEVEL fields shown.

# Sub-functions: MODIS repull for a single date.
# REPLICATES A4's exact authenticated mechanism (R/04_satellite_features.R lines 102-136).
# KEY DIFFERENCE from previous attempt: uses /getfile/ endpoint directly (not search API),
# single handle with followlocation + maxredirs handles the Earthdata OAuth redirect chain.
# NOTE(cite): OB.DAAC getfile endpoint: https://oceandata.sci.gsfc.nasa.gov/getfile/

OBDAAC_GET    <- "https://oceandata.sci.gsfc.nasa.gov/getfile/"
D12_COOKIE_F  <- file.path(tempdir(), "urs_d12_cookies.txt")
# Seed D12 cookie jar from any prior authenticated session (A4 or earlier runs).
# This avoids the need for a fresh URS OAuth interactive redirect, which may
# return a > 10 KB HTML login page instead of the NetCDF when scripted.
# Priority: tmp-root urs_cookies.txt (persists across R sessions within the
# same OS session) > tmp-root obdaac_cookies.txt > empty (auth from scratch).
local({
  candidates <- c(
    file.path(dirname(tempdir()), "urs_cookies.txt"),
    file.path(dirname(tempdir()), "obdaac_cookies.txt"),
    file.path(tempdir(), "urs_cookies.txt")
  )
  for (f in candidates) {
    if (file.exists(f) && !is.na(file.size(f)) && file.size(f) > 100L) {
      file.copy(f, D12_COOKIE_F, overwrite = TRUE)
      message("[A9-D12] Seeded cookie jar from: ", f)
      break
    }
  }
})

# Products for D12 drill-down: CHL (primary) and nFLH (secondary level field).
# NOTE(paper): pixel-level trend fields omitted per sec. 2.3 (noisiest at native res).
#              Only LEVEL fields shown. FAI not available in L3m (A4 log, limitation).
D12_PRODUCTS <- list(
  list(prod = "CHL", var = "chlor_a", nc_var = "chlor_a", label = "chl_a_pixel"),
  list(prod = "FLH", var = "nflh",    nc_var = "nflh",    label = "nflh_pixel")
)

#' Build direct /getfile/ URL for a MODIS L3m daily product (A4 pattern).
#' NOTE(cite): filename convention: AQUA_MODIS.YYYYMMDD.L3m.DAY.<PROD>.<var>.4km.nc
obdaac_getfile_url <- function(date_val, prod) {
  ds <- format(as.Date(date_val), "%Y%m%d")
  paste0(OBDAAC_GET, "AQUA_MODIS.", ds, ".L3m.DAY.", prod$prod, ".", prod$var, ".4km.nc")
}

#' Authenticated MODIS download — exact A4 handle setup (lines 107-136 of 04_satellite_features.R).
#' Uses /getfile/ endpoint + netrc + cookies + followlocation + maxredirs.
#' Returns destfile on success (file.size >= 10000), NULL on failure.
#' NOTE(paper): stream-and-discard — caller MUST unlink(destfile) after use.
download_modis_a4 <- function(url, destfile,
                               cookie_file = D12_COOKIE_F,
                               netrc_file  = path.expand("~/.netrc"),
                               timeout     = 300L) {
  h <- curl::new_handle()
  curl::handle_setopt(h,
    netrc           = 1L,
    netrc_file      = netrc_file,
    cookiefile      = cookie_file,
    cookiejar       = cookie_file,
    followlocation  = 1L,
    maxredirs       = 10L,
    timeout         = timeout,
    low_speed_limit = 1024L,
    low_speed_time  = 60L
  )
  ok <- tryCatch({
    curl::curl_download(url, destfile, handle = h, quiet = TRUE)
    sz <- file.size(destfile)
    if (is.na(sz) || sz < 10000L) {    # < 10 KB -> auth error page, not a NetCDF
      unlink(destfile)
      message("[A9-D12] Auth/size check failed for ", basename(url),
              " (size=", if (is.na(sz)) "NA" else sz, " bytes) -- likely redirect HTML")
      return(FALSE)
    }
    TRUE
  }, error = function(e) {
    unlink(destfile)
    message("[A9-D12] curl error: ", e$message)
    FALSE
  })
  if (ok) destfile else NULL
}

#' Load native-resolution raster, crop to study bbox, project to analysis CRS.
#' Handles multi-layer NetCDF (selects by nc_var name, like A4's aggregate_to_grid).
#' Does NOT aggregate -- returns pixel-level SpatRaster.
get_pixel_raster <- function(nc_path, bbox_cfg, crs_proj = "EPSG:5070",
                              nc_var = "chlor_a") {
  if (is.null(nc_path) || !file.exists(nc_path)) return(NULL)
  tryCatch({
    r <- terra::rast(nc_path)
    # Select correct layer when NetCDF has multiple (e.g. SST has sst + qual_sst)
    if (terra::nlyr(r) > 1) {
      idx <- which(names(r) == nc_var)
      if (length(idx) == 0L) idx <- 1L
      r <- r[[idx[1]]]
    }
    study_e <- terra::ext(bbox_cfg$xmin, bbox_cfg$xmax, bbox_cfg$ymin, bbox_cfg$ymax)
    r_crop  <- terra::crop(r, study_e)
    names(r_crop) <- nc_var
    terra::project(r_crop, crs_proj, method = "bilinear")
  }, error = function(e) {
    message("[A9-D12] Raster load/project error: ", e$message); NULL
  })
}

# Execute drill-down
DRILL_DOWN_AVAILABLE <- FALSE
attention_features   <- NULL
bbox_cfg <- cfg$study_area$bbox_wgs84

if (nrow(flagged_sf) > 0) {
  message("[A9-D12] Attempting MODIS repull for ", as.character(MAP_DATE), " ...")
  d12_raw <- file.path(tempdir(), "d12_raw")
  dir.create(d12_raw, showWarnings = FALSE)

  url_chl  <- obdaac_getfile_url(MAP_DATE, D12_PRODUCTS[[1]])
  dest_chl <- file.path(d12_raw, basename(url_chl))
  nc_chl   <- download_modis_a4(url_chl, dest_chl)

  if (!is.null(nc_chl)) {
    r_chl <- get_pixel_raster(nc_chl, bbox_cfg)
    # NOTE(paper): stream-and-discard -- raw MODIS file deleted immediately.
    unlink(nc_chl)
    message("[A9-D12] Raw MODIS file deleted (stream-and-discard)")

    if (!is.null(r_chl)) {
      pixel_vals <- tryCatch(
        terra::extract(r_chl, terra::vect(flagged_sf), xy = TRUE, ID = TRUE),
        error = function(e) NULL
      )
      if (!is.null(pixel_vals) && nrow(pixel_vals) > 0) {
        # Rename chlor_a col if it exists
        if ("chlor_a" %in% names(pixel_vals)) {
          names(pixel_vals)[names(pixel_vals) == "chlor_a"] <- "chl_a_pixel"
        }
        pixel_dt <- as.data.table(pixel_vals)
        pixel_dt <- pixel_dt[!is.na(chl_a_pixel)]

        flagged_idx <- data.table(
          ID                = seq_len(nrow(flagged_sf)),
          cell_id           = flagged_sf$cell_id,
          depth_m           = flagged_sf$depth_m,
          dist_to_shore_m   = flagged_sf$dist_to_shore_m,
          predicted_risk_H7 = flagged_sf$predicted_risk_H7,
          county_name       = flagged_sf$county_name
        )
        pixel_dt <- merge(pixel_dt, flagged_idx, by = "ID", all.x = TRUE)

        # Convergence: high chl-a pixel AND shallow cell AND nearshore cell.
        # NOTE(paper): static layers (depth, coast distance) are constants that
        #              identify plausible accumulation locations. Convergence = multiple
        #              independent inputs agree. A lone elevated pixel is weaker evidence.
        pixel_dt[, chl_q75_incell  := quantile(chl_a_pixel, 0.75, na.rm = TRUE),
                 by = cell_id]
        pixel_dt[, is_chl_elevated := chl_a_pixel >= chl_q75_incell]
        pixel_dt[, is_shallow      := !is.na(depth_m) & depth_m > CONVERGE_DEPTH_SHALLOW]
        pixel_dt[, is_nearshore    := !is.na(dist_to_shore_m) &
                                        dist_to_shore_m < CONVERGE_NEARSHORE_M]
        pixel_dt[, is_convergence  := is_chl_elevated & is_shallow & is_nearshore]

        pixel_dt[, diagnostic_label :=
          "FEATURE CONCENTRATION (DIAGNOSTIC) -- NOT a sub-cell risk score. Shows where flagging conditions concentrate within this 10 km cell at native ~4 km MODIS resolution. At H=7 horizon this represents pre-bloom precursor conditions that may drift before the forecast date (sec. 2.3 precursor-drift caveat)."]
        pixel_dt[, data_floor_note :=
          "Native ~4 km MODIS L3m pixel. Nothing rendered finer -- no false precision below native resolution."]
        pixel_dt[, IS_PLACEHOLDER := FALSE]

        pixel_xy <- pixel_dt[!is.na(x) & !is.na(y)]
        if (nrow(pixel_xy) > 0) {
          attention_features   <- st_as_sf(pixel_xy, coords = c("x", "y"), crs = 5070)
          DRILL_DOWN_AVAILABLE <- TRUE
          message("[A9-D12] Attention: ", nrow(attention_features), " pixels | ",
                  sum(pixel_dt$is_convergence, na.rm = TRUE), " convergence pixels")
        }
      }
    }
  }
}

# Placeholder if MODIS repull unavailable or no flagged cells
if (!DRILL_DOWN_AVAILABLE) {
  message("[A9-D12] MODIS repull unavailable or no flagged cells -- producing placeholder.")
  # NOTE(paper): IS_PLACEHOLDER=TRUE when MODIS repull unavailable (no ~/.netrc or network).
  #              Re-run with valid ~/.netrc credentials to populate native-pixel overlay.
  if (nrow(flagged_sf) > 0) {
    ph_df <- data.frame(
      cell_id           = flagged_sf$cell_id,
      chl_a_pixel       = NA_real_,
      is_chl_elevated   = NA,
      is_shallow        = NA,
      is_nearshore      = NA,
      is_convergence    = NA,
      diagnostic_label  = "FEATURE CONCENTRATION (DIAGNOSTIC) -- PLACEHOLDER: MODIS repull unavailable. Re-run with ~/.netrc to populate native-pixel overlay.",
      data_floor_note   = "Native ~4 km MODIS pixel (not yet retrieved). IS_PLACEHOLDER=TRUE.",
      IS_PLACEHOLDER    = TRUE,
      predicted_risk_H7 = flagged_sf$predicted_risk_H7,
      county_name       = flagged_sf$county_name,
      stringsAsFactors  = FALSE
    )
    attention_features <- merge(flagged_sf[, "cell_id"], ph_df, by = "cell_id")
  } else {
    attention_features <- st_sf(
      cell_id          = NA_integer_,
      IS_PLACEHOLDER   = TRUE,
      diagnostic_label = "No flagged cells on MAP_DATE",
      geometry         = st_sfc(st_geometrycollection(), crs = 5070)
    )
  }
}

out_attention <- file.path(OUT_GIS, "intracell_attention.gpkg")
tryCatch({
  st_write(attention_features, out_attention, delete_dsn = TRUE, quiet = TRUE)
  message("[A9-D12] intracell_attention.gpkg written")
}, error = function(e) message("[A9-D12] Attention GPKG write error: ", e$message))

# ============================================================
# SECTION 9: INTERACTIVE HTML MAP (LEAFLET)
# Full layer stack per M2 exit criteria.
# Honesty labels (required):
#   - "FORECAST at horizon H" (not nowcast)
#   - "MODEL: RF Stage-1 (swappable)" (backend named)
#   - "MODEL OUTPUT -- NOT OBSERVED BLOOMS"
#   - Drill-down: "DIAGNOSTIC -- NOT a sub-cell risk score"
# NOTE(cite): CartoDB.Positron open-source tiles; ETOPO 2022 for published figures.
# ============================================================

message("[A9] Building interactive HTML map ...")

# Transform to EPSG:4326 for leaflet
# NOTE(paper): analysis in EPSG:5070; web display in EPSG:4326.
risk_4326    <- st_transform(risk_grid_sf, 4326)
flagged_4326 <- st_transform(flagged_sf, 4326)

# Attention layer transform
attention_4326 <- NULL
if (!is.null(attention_features) && nrow(attention_features) > 0 &&
    DRILL_DOWN_AVAILABLE) {
  tryCatch({
    att_valid <- attention_features[!is.na(st_coordinates(attention_features)[, 1]), ]
    if (nrow(att_valid) > 0) attention_4326 <- st_transform(att_valid, 4326)
  }, error = function(e) message("[A9] Attention transform error: ", e$message))
}

# Color palette (probability 0-1)
pal_risk <- colorNumeric(
  palette  = c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c"),
  domain   = c(0, 1),
  na.color = "#aaaaaa44"
)

# Popup helpers
risk_df    <- as.data.frame(st_drop_geometry(risk_4326))
flagged_df <- as.data.frame(st_drop_geometry(flagged_4326))

make_grid_popup <- function(df) {
  paste0(
    "<b>Cell ID:</b> ", df$cell_id, "<br>",
    "<b>County:</b> ", df$county_name, "<br><hr>",
    "<b style='color:",
    ifelse(!is.na(df$predicted_risk_H7) & df$predicted_risk_H7 > RISK_THRESHOLD,
           "red", "steelblue"), "'>",
    "Predicted Risk P(HAB=1): ",
    ifelse(is.na(df$predicted_risk_H7), "No data",
           sprintf("%.1f%%", df$predicted_risk_H7 * 100)), "</b><br>",
    "<b>Risk Class:</b> ", df$risk_class, "<br>",
    "<b>Horizon:</b> H=", backend$horizon, " days<br>",
    "<b>Feature date (T):</b> ", MAP_DATE, "<br>",
    "<b>Predicted bloom date (~T+H):</b> ", MAP_DATE + backend$horizon, "<br>",
    "<b>Observed bloom (HAB_H7):</b> ",
    ifelse(is.na(df[[target_col]]), "unknown",
           ifelse(df[[target_col]] == 1L, "YES (bloom recorded)", "NO")), "<br>",
    "<b>Satellite chl-a:</b> ",
    ifelse(is.na(df$chlor_a_mean), "no data (cloudy)",
           sprintf("%.2f mg/m3", df$chlor_a_mean)), "<br>",
    "<b>Depth:</b> ",
    ifelse(is.na(df$depth_m), "no data",
           sprintf("%.0f m", df$depth_m)), "<br>",
    "<b>Dist to coast:</b> ",
    ifelse(is.na(df$dist_to_shore_m), "no data",
           sprintf("%.1f km", df$dist_to_shore_m / 1000)), "<br><hr>",
    "<small><i>MODEL OUTPUT -- NOT OBSERVED BLOOMS.<br>",
    "Model: RF Stage-1 (swappable backend)</i></small>"
  )
}

make_zone_popup <- function(df) {
  paste0(
    "<b style='color:red'>PRIORITY MONITORING ZONE</b><br>",
    "<b>Cell ID:</b> ", df$cell_id, "<br>",
    "<b>Predicted Risk:</b> ", sprintf("%.1f%%", df$predicted_risk_H7 * 100), "<br>",
    "<b>Threshold basis:</b> P(HAB=1, H=7) > ", RISK_THRESHOLD, "<br>",
    "<b>Guidance:</b> ", df$sampling_rationale, "<br><hr>",
    "<small><i>Zones = model-derived flags. NOT confirmed bloom detections.</i></small>"
  )
}

make_att_popup <- function(df) {
  # Vectorized: df may be the full attention data.frame (one row per pixel).
  is_ph <- !is.null(df$IS_PLACEHOLDER) & isTRUE(df$IS_PLACEHOLDER[1])
  conv  <- ifelse(
    !is_ph & !is.na(df$is_convergence) & df$is_convergence %in% TRUE,
    "<b style='color:darkred'>CONVERGENCE: elevated chl-a + shallow + nearshore</b><br>",
    ""
  )
  body_real <- paste0(
    "<b>chl-a (pixel):</b> ",
    ifelse(is.na(df$chl_a_pixel), "NA", sprintf("%.2f mg/m3", df$chl_a_pixel)), "<br>",
    "<b>Elevated chl-a?</b> ", df$is_chl_elevated %in% TRUE, "<br>",
    "<b>Shallow cell?</b> ",   df$is_shallow     %in% TRUE, "<br>",
    "<b>Nearshore cell?</b> ", df$is_nearshore    %in% TRUE, "<br>"
  )
  body <- ifelse(is_ph,
    "<i>(placeholder -- MODIS repull pending credentials)</i><br>",
    body_real
  )
  paste0(
    "<b>INTRA-CELL ATTENTION (DIAGNOSTIC)</b><br>",
    conv, body,
    "<hr><small style='color:grey'>",
    df$diagnostic_label, "<br>", df$data_floor_note, "</small>"
  )
}

# Build leaflet map
# NOTE(cite): CartoDB.Positron tiles used as basemap (open-source, non-commercial safe).
#             ETOPO 2022 (NOAA, public domain) preferred for published static figures
#             per reports/decisions.md 2026-07-11 directive.
m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
  addProviderTiles(
    "CartoDB.Positron", group = "Basemap",
    options = tileOptions(attribution = paste0(
      "Basemap: CartoDB | ",
      "For published figures: ETOPO 2022 (NOAA NCEI, public domain) preferred | ",
      "West Florida Shelf grid: Hu et al. (2022)"
    ))
  ) |>
  # HAB risk probability choropleth
  addPolygons(
    data        = risk_4326,
    fillColor   = ~pal_risk(predicted_risk_H7),
    fillOpacity = 0.75,
    color       = "#333333", weight = 0.5, opacity = 0.5,
    popup       = make_grid_popup(risk_df),
    label       = ~paste0("P(HAB=1): ",
                           ifelse(is.na(predicted_risk_H7), "no data",
                                  sprintf("%.0f%%", predicted_risk_H7 * 100))),
    group       = paste0("HAB Risk Forecast (H=", backend$horizon, " days)")
  ) |>
  # Priority monitoring zones
  addPolygons(
    data        = flagged_4326,
    fillColor   = "none", color = "red",
    weight = 3, opacity = 1, fillOpacity = 0,
    dashArray   = "6,4",
    popup       = make_zone_popup(flagged_df),
    label       = "Priority Monitoring Zone",
    group       = "Priority Monitoring Zones"
  )

# Intra-cell attention layer
if (!is.null(attention_4326) && nrow(attention_4326) > 0) {
  att_df      <- as.data.frame(st_drop_geometry(attention_4326))
  is_converge <- !is.na(att_df$is_convergence) & isTRUE(att_df$is_convergence)
  m <- m |>
    addCircleMarkers(
      data        = attention_4326,
      radius      = 6,
      color       = ifelse(is_converge, "darkred", "orange"),
      fillOpacity = 0.7, opacity = 1, weight = 1.5,
      popup       = make_att_popup(att_df),
      label       = "Feature Concentration Pixel (Diagnostic)",
      group       = "Intra-cell Attention (Diagnostic)"
    )
  converge_sf <- attention_4326[!is.na(att_df$is_convergence) & att_df$is_convergence, ]
  if (nrow(converge_sf) > 0) {
    m <- m |>
      addCircleMarkers(
        data        = converge_sf,
        radius      = 11,
        color       = "darkred", fillColor = "red",
        fillOpacity = 0.45, opacity = 1, weight = 2,
        label       = "Convergence: elevated chl-a + shallow + nearshore",
        group       = "Intra-cell Attention (Diagnostic)"
      )
  }
}

# Legend, controls, title
m <- m |>
  addLegend(
    position  = "bottomright",
    pal       = pal_risk,
    values    = c(0, 1),
    title     = paste0("<b>P(HAB=1) H=", backend$horizon, "d</b><br>",
                        "<small>RF forecast -- NOT bloom detection</small>"),
    labFormat = labelFormat(suffix = ""),
    opacity   = 0.85
  ) |>
  addLayersControl(
    baseGroups    = "Basemap",
    overlayGroups = c(
      paste0("HAB Risk Forecast (H=", backend$horizon, " days)"),
      "Priority Monitoring Zones",
      if (!is.null(attention_4326)) "Intra-cell Attention (Diagnostic)" else NULL
    ),
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  addScaleBar(position = "bottomleft") |>
  # Title panel (honesty label -- required per M2 criteria)
  addControl(
    html = paste0(
      "<div style='background:white;padding:8px 12px;border:2px solid #c00;",
      "border-radius:5px;max-width:380px;font-size:12px;'>",
      "<b style='font-size:14px'>BloomGuard GIS -- HAB Risk Forecast</b><br>",
      "<b>Feature date (T):</b> ", MAP_DATE, "<br>",
      "<b>Predicted bloom date (~T+H):</b> ", MAP_DATE + backend$horizon, "<br>",
      "<b>Horizon:</b> H=", backend$horizon, " days<br>",
      "<b>Model:</b> RF Stage-1 (ranger)<br>",
      "<b style='color:red'>MODEL OUTPUT -- NOT OBSERVED BLOOMS</b><br>",
      "<b>Swappable:</b> YES -- change MODEL_PATH for transformer<br>",
      "<hr style='margin:4px 0'>",
      "<small>West Florida Shelf (Hu et al. 2022) | 10 km cells (Green 2022) | ",
      "Basemap: CartoDB | ETOPO 2022 preferred for publication</small></div>"
    ),
    position = "topleft"
  ) |>
  # D12 honesty panel
  addControl(
    html = paste0(
      "<div style='background:#fff8e1;padding:6px 10px;border:1px solid #f9a825;",
      "border-radius:5px;max-width:340px;font-size:11px;'>",
      "<b>Intra-cell Attention (Diagnostic)</b><br>",
      "Dots show WHERE flagging conditions concentrate inside a flagged cell ",
      "at native ~4 km MODIS pixel resolution.<br>",
      "<b>NOT a sub-cell risk score.</b> No validated skill below the 10 km cell.<br>",
      "<b>H=7 caveat:</b> pre-bloom precursors may drift before T+7.<br>",
      "Convergence (large red dot) = elevated chl-a + shallow + nearshore cell.</div>"
    ),
    position = "topright"
  )

out_html <- file.path(OUT_MAPS, "hab_risk_map.html")
# NOTE(paper): selfcontained=FALSE avoids pandoc dependency; creates hab_risk_map_files/
#              alongside the HTML. Both must be kept together for the interactive map.
saveWidget(m, out_html, selfcontained = FALSE, title = paste0(
  "BloomGuard HAB Risk Forecast H=", backend$horizon, " | ", MAP_DATE,
  " | RF Stage-1 | NOT OBSERVED BLOOMS"
))
message("[A9] hab_risk_map.html written")

# ============================================================
# SECTION 10: DONE-CRITERIA CHECKS
# ============================================================

message("\n[A9] ===== DONE-CRITERIA CHECKS =====")
checks <- list()
checks[["hab_risk_grid.gpkg exists"]]            <- file.exists(out_risk_grid)
checks[["hab_risk_raster.tif exists"]]           <- file.exists(out_raster)
checks[["priority_monitoring_zones.gpkg exists"]]<- file.exists(out_zones)
checks[["intracell_attention.gpkg exists"]]      <- file.exists(out_attention)
checks[["hab_risk_map.html exists"]]             <- file.exists(out_html)
checks[["CRS = EPSG:5070 for analysis"]]         <- st_crs(risk_grid_sf)$epsg == 5070L
checks[["predicted_risk_H7 col present"]]        <- "predicted_risk_H7" %in% names(risk_grid_sf)
checks[["honesty_label col present"]]            <- "honesty_label" %in% names(risk_grid_sf)
checks[["backend_model col present"]]            <- "backend_model" %in% names(risk_grid_sf)
checks[["is_model_output col present"]]          <- "is_model_output" %in% names(risk_grid_sf)
checks[["HAB_H7 excluded from pred features"]]  <- !"HAB_H7" %in% names(nd_for_pred)
checks[["n flagged cells > 0"]]                  <- sum(risk_probs > RISK_THRESHOLD) > 0
checks[["HTML map > 10KB"]]                      <- file.size(out_html) > 10000
checks[["IS_PLACEHOLDER col in attention"]]      <- "IS_PLACEHOLDER" %in% names(attention_features)

check_pass <- vapply(checks, isTRUE, logical(1))
for (nm in names(checks)) {
  message(sprintf("  [%s] %s", if (check_pass[nm]) "PASS" else "FAIL", nm))
}
message(sprintf("[A9] %d/%d checks pass", sum(check_pass), length(check_pass)))

# ============================================================
# SECTION 11: AGENT DECISION LOG
# ============================================================

n_flagged <- sum(risk_probs > RISK_THRESHOLD)

log_lines <- c(
  "# gis (A9) -- decision & methods log",
  "",
  paste0("**Agent:** A9 gis (M2 GIS risk mapping)"),
  paste0("**Date:** ", Sys.Date()),
  paste0("**Status:** COMPLETE (RF backend). Transformer re-run pending M3."),
  "",
  "---",
  "",
  "## Decisions",
  "",
  paste0("- **Model-agnostic design (author directive, decisions.md 2026-07-12)**: predict_risk(backend, newdata) is the sole model-specific function. All map/export code is model-blind. Swapping RF -> transformer = update MODEL_PATH + predict() call inside predict_risk(). No other changes. -- 2026-07-12"),
  paste0("- **MAP_DATE = 2016-10-24**: test-set date (year >= 2016, temporal split), 13/25 cells HAB_H7=1 (52%), 72% cloud-free MODIS coverage. Active West Florida Shelf bloom period. Avoids 2018 top-positive dates that had zero satellite coverage. -- 2026-07-12"),
  paste0("- **RISK_THRESHOLD = 0.40**: P(HAB=1) threshold for priority zones. Prioritizes recall per PLAN sec. 9. Yields ", n_flagged, " flagged cells on MAP_DATE. -- 2026-07-12"),
  paste0("- **Feature pipeline IDENTICAL to A7**: same LOG_FEATURES, ALWAYS_EXCLUDE, train-median imputation from backend$train_medians. Enforced via apply_feature_pipeline() using the backend object. Any mismatch silently corrupts predictions. -- 2026-07-12"),
  paste0("- **ETOPO preference (decisions.md 2026-07-11)**: GEBCO is non-commercial. CartoDB.Positron used for leaflet tiles (non-commercial safe). Published static figures must use ETOPO 2022 (NOAA NCEI, public domain). Documented in script and map attribution. -- 2026-07-12"),
  paste0("- **Intra-cell attention (D12/sec. 2.3)**: MODIS repull attempted for MAP_DATE. ",
         if (DRILL_DOWN_AVAILABLE) paste0("SUCCESS -- native ~4km pixels extracted for ", nrow(flagged_sf), " flagged cells.")
         else "PLACEHOLDER -- no ~/.netrc credentials. IS_PLACEHOLDER=TRUE in output.",
         " Convergence: chl-a >= 75th pctile within cell AND depth > -30m AND dist_to_shore < 25km. LEVEL field only (no pixel-level trend fields per sec. 2.3). -- 2026-07-12"),
  paste0("- **D12 honesty labels**: every drill-down view labeled 'FEATURE CONCENTRATION (DIAGNOSTIC)'. Nothing rendered below native ~4km MODIS pixel. H=7 precursor-drift caveat in popup and HTML panel. -- 2026-07-12"),
  paste0("- **Transformer re-run pending**: author directive (decisions.md 2026-07-12) -- published GIS will use Stage-2 transformer. RF is validated swappable placeholder until M3. Re-run = change MODEL_PATH, source 09_gis_export.R. -- 2026-07-12"),
  "",
  "## Data sources used",
  "",
  "| Dataset | Access | Used for |",
  "|---|---|---|",
  "| best_model.rds (A7) | local file | RF backend |",
  "| model_dataset.parquet (A6) | local file | Features for MAP_DATE |",
  "| study_area_grid.gpkg (A2) | local file | Grid geometry |",
  "| static_geo.parquet (A5) | local file | depth_m, dist_to_shore for convergence |",
  "| MODIS-Aqua L3m CHL (NASA OB.DAAC) | stream-and-discard repull | D12 native pixels | DOI: 10.5067/AQUA/MODIS/L3M/CHL/2022.0 |",
  "| CartoDB.Positron | leaflet tiles | Basemap |",
  "| ETOPO 2022 (NOAA NCEI) | preferred for published figures | Basemap |",
  "",
  "## Methods & techniques",
  "",
  paste0("- **Model-agnostic predict_risk()**: ranger predict() inside; swap = change MODEL_PATH + inner call. -- R/09_gis_export.R sec. 1"),
  paste0("- **apply_feature_pipeline()**: log1p(chl-a, Kd490), signed-log1p(nFLH), median imputation + _is_missing flags. Identical to A7. -- R/09_gis_export.R sec. 1"),
  paste0("- **terra::rasterize()**: risk probabilities -> GeoTIFF at 10 km (EPSG:5070). -- sec. 6"),
  paste0("- **Priority zones**: filter P(HAB=1) > 0.40. -- sec. 7"),
  paste0("- **MODIS repull (D12)**: OB.DAAC API -> curl download -> terra::crop + project -> terra::extract per flagged cell -> unlink() (stream-and-discard). Convergence: elevated pixel AND shallow/nearshore static context. -- sec. 8"),
  paste0("- **leaflet map**: CartoDB.Positron base; choropleth + zone + attention layers; EPSG:4326 display; honesty panels. -- sec. 9"),
  "",
  "## Open questions / caveats / limitations",
  "",
  "- NOTE(limitation): Transformer (A11) not yet available. RF-backed map is validated placeholder until M3 completes.",
  "- NOTE(limitation): Dynamic env features (wind, precip, salinity) are all-NA placeholder. Adding ERA5/CHIRPS/SMAP will change predictions.",
  "- NOTE(limitation): HABSOS non-detection != proven absence. Negative predictions in unsampled regions should be interpreted cautiously.",
  "- NOTE(limitation): At H=7, intra-cell pixel patterns are pre-bloom precursor conditions. May drift before bloom lands (sec. 2.3 precursor-drift caveat).",
  "- NOTE(limitation): Pixel-level trend fields omitted from D12 drill-down per sec. 2.3 (noisiest at native resolution due to cloud gaps).",
  "- NOTE(paper): GEBCO depth_m used in modeling/analysis freely (internal use). Published map figures use ETOPO 2022 (NOAA, public domain) per decisions.md.",
  "- NOTE(paper): Backend model named in every output layer and HTML map title so transformer swap is traceable in all exports.",
  "",
  "## Done-criteria (PLAN.md sec. 6 A9 / M2) -- pass/fail",
  "",
  "| Criterion | Status |",
  "|---|---|",
  paste(sapply(names(checks), function(nm) {
    sprintf("| %s | %s |", nm, if (isTRUE(checks[[nm]])) "PASS" else "FAIL")
  }), collapse = "\n"),
  "",
  "## Swappable backend confirmation",
  "",
  paste0("Backend swap RF -> transformer: (1) Update MODEL_PATH (line ~60) to transformer checkpoint. ",
         "(2) Replace `predict(backend$rf, ...)$predictions[, \"1\"]` inside predict_risk() with ",
         "the transformer's inference call. (3) Ensure load_backend() accepts transformer format. ",
         "(4) ALL map/export code below predict_risk() is unchanged.")
)

writeLines(log_lines, LOG_PATH)
message("[A9] Agent log written to ", LOG_PATH)
message("\n[A9] M2 COMPLETE.")
message("[A9] Outputs:")
for (p in c(out_risk_grid, out_raster, out_zones, out_attention, out_html)) {
  message("  ", p, if (file.exists(p)) "" else " [MISSING]")
}
message("[A9] Transformer re-run pending M3 (A11).")
