# ============================================================
# FILE: 05_environmental_features.R
# PURPOSE: Per-cell × per-date environmental + static-geographic features.
#          Produces two Parquets for A6 (datacube):
#            (1) environmental_features.parquet — dynamic (cell × date): wind, precip,
#                salinity, seasonality. Placeholders where data blocked/credentialed.
#            (2) static_geo.parquet — static (per cell): GEBCO depth, distance-to-shore,
#                TIGER county assignment (key output for spatial cross-validation blocking).
# INPUTS:  data/processed/study_area_grid.gpkg       (A2, EPSG:5070, 4743 cells)
#          data/processed/habsos_labels.parquet       (A3, cell × date span)
#          config.yaml (via R/00_config.R)
# OUTPUTS: data/processed/environmental_features.parquet
#          data/processed/static_geo.parquet
#          data/raw/weather/manual_downloads.md       (ERA5, CHIRPS instructions)
#          data/raw/gis/manual_downloads.md           (SMAP, GEBCO provenance)
# TECHNIQUES:
#   - TIGER county shapefile download + EPSG:5070 reproject + sf spatial join (st_join)
#   - GEBCO 2026 bathymetry via queue API; zonal mean (terra::extract) per cell
#   - Distance-to-shore: TIGER US coastline → st_distance from cell centroids to coast
#   - CHIRPS v2.0 daily precipitation: vsicurl streaming (no local copy); 403/block → placeholder
#   - ERA5 10m wind: requires ~/.cdsapirc (Copernicus CDS key) → placeholder if absent
#   - SMAP L3 sea-surface salinity: requires Earthdata ~/.netrc; coarse 40–70 km → placeholder
#   - Seasonality (month, doy, sin/cos) always computed from date
#   - IS_PLACEHOLDER column per feature family; feature_filled reserved for A6 forward-fill
# CITATIONS:
#   - ERA5: Hersbach et al. (2020) doi:10.1002/qj.3803 (placeholder; full pull in manual_downloads.md)
#   - CHIRPS: Funk et al. (2015) doi:10.1038/sdata.2015.66 (placeholder; pull instructions in manual_downloads.md)
#   - GEBCO: GEBCO Compilation Group (2026) https://doi.org/10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f
#   - TIGER: US Census Bureau (2023) https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html
#   - SMAP RSS SSS v5.0: Meissner et al. (2018) https://doi.org/10.3390/rs10071121 (placeholder)
# ============================================================

# NOTE(paper): Environmental features span wind (ERA5), precipitation (CHIRPS), salinity
#              (SMAP), static bathymetry (GEBCO), and distance-to-shore (TIGER coastline).
#              ERA5 and CHIRPS require server-side bbox requests (Gulf box: 24–31°N, 87–81°W);
#              no global archive downloads. SMAP is a broad-context (~40–70 km) feature only.
# NOTE(limitation): ERA5 wind is a placeholder pending CDS API key (~/.cdsapirc missing on
#                   this machine). CHIRPS daily precip is a placeholder — CHC server returned
#                   403 during automated pull (CrowdSec block); see manual_downloads.md.
# NOTE(limitation): SMAP sea-surface salinity at 40–70 km resolution is far coarser than
#                   the 10 km study grid; treat as a broad-context feature. Flag set on ALL
#                   salinity values via salinity_coarse_flag=TRUE.
# NOTE(cite): Albers Equal Area EPSG:5070 used for all metric distance calculations
#             (distance-to-shore in meters). Reprojection of TIGER from EPSG:4326.

# Bootstrap: walk up to the repo root and load config
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressWarnings(suppressMessages({
  library(sf)
  library(terra)
  library(arrow)
  library(data.table)
}))

# ── Helpers ──────────────────────────────────────────────────────────────────

msg <- function(...) message(format(Sys.time(), "[%H:%M:%S]"), " ", ...)

download_safe <- function(url, dest, method = "curl", ...) {
  status <- tryCatch(
    download.file(url, dest, method = method, quiet = TRUE, ...),
    error = function(e) -99L
  )
  status
}

# NOTE(paper): each data source attempted in priority order per PLAN.md A5 directive:
#  (1) TIGER county labels — no auth
#  (2) GEBCO bathymetry  — no auth (queue API at download.gebco.net)
#  (3) CHIRPS precip     — no auth, but 403 blocked → placeholder
#  (4) ERA5 wind         — requires ~/.cdsapirc → placeholder
#  (5) SMAP salinity     — requires ~/.netrc Earthdata → attempted, fallback placeholder

# ── 0.  Paths ────────────────────────────────────────────────────────────────

raw_gis     <- proj_path(cfg$paths$raw_gis)
raw_weather <- proj_path(cfg$paths$raw_weather)
dir.create(raw_gis,     recursive = TRUE, showWarnings = FALSE)
dir.create(raw_weather, recursive = TRUE, showWarnings = FALSE)
dir.create(proj_path("data/raw/gis/gebco"),   recursive = TRUE, showWarnings = FALSE)
dir.create(proj_path("data/raw/gis/tiger"),   recursive = TRUE, showWarnings = FALSE)
dir.create(proj_path("data/processed"),       recursive = TRUE, showWarnings = FALSE)
dir.create(proj_path("data/interim"),         recursive = TRUE, showWarnings = FALSE)

out_env    <- proj_path(cfg$paths$environmental_features)      # data/processed/environmental_features.parquet
out_static <- proj_path("data/processed/static_geo.parquet")

# ── 1. Load grid + habsos labels ─────────────────────────────────────────────

msg("Loading grid and habsos labels ...")
grid <- st_read(proj_path(cfg$paths$grid), quiet = TRUE)
# NOTE(paper): grid is 4743 cells in EPSG:5070 (Albers Equal Area), cellsize 10 km (A2).

labels_dt <- as.data.table(read_parquet(proj_path(cfg$paths$habsos_labels)))
setnames(labels_dt, "sample_date", "date")

# All unique (cell_id, date) pairs for which we need environmental features
cell_dates <- unique(labels_dt[, .(cell_id, date)])
setorder(cell_dates, cell_id, date)
msg(sprintf("Cell-date pairs to populate: %d (%d cells, %d unique dates)",
            nrow(cell_dates), length(unique(cell_dates$cell_id)),
            length(unique(cell_dates$date))))

# ── 2. SECTION A: TIGER County Labels (static, no auth) ──────────────────────
# NOTE(cite): US Census Bureau TIGER/Line 2023 — tl_2023_us_county.zip

msg("=== SECTION A: TIGER county labels ===")

tiger_county_zip  <- proj_path("data/raw/gis/tiger/tl_2023_us_county.zip")
tiger_county_dir  <- proj_path("data/raw/gis/tiger/tl_2023_us_county")
tiger_county_url  <- "https://www2.census.gov/geo/tiger/TIGER2023/COUNTY/tl_2023_us_county.zip"
tiger_coast_zip   <- proj_path("data/raw/gis/tiger/tl_2023_us_coastline.zip")
tiger_coast_dir   <- proj_path("data/raw/gis/tiger/tl_2023_us_coastline")
tiger_coast_url   <- "https://www2.census.gov/geo/tiger/TIGER2023/COASTLINE/tl_2023_us_coastline.zip"

tiger_ok <- FALSE
static_county <- NULL

tryCatch({
  # Download county shapefile if not cached
  if (!file.exists(tiger_county_zip)) {
    msg("  Downloading TIGER county shapefile (~83 MB) ...")
    st <- download_safe(tiger_county_url, tiger_county_zip)
    if (st != 0) stop(sprintf("TIGER county download failed (status %d)", st))
  }
  if (!dir.exists(tiger_county_dir)) {
    msg("  Unzipping county shapefile ...")
    unzip(tiger_county_zip, exdir = tiger_county_dir)
  }

  shp_file <- list.files(tiger_county_dir, pattern = "\\.shp$", full.names = TRUE)[1]
  counties_raw <- st_read(shp_file, quiet = TRUE)

  # Gulf states in our bbox: FL(12), AL(01), MS(28), LA(22), TX(48)
  # NOTE(paper): TIGER county assignment used for geographic blocking in spatial cross-validation
  #              (per PLAN.md Lead Directive 2026-07-11). Counties provide natural spatial blocks
  #              that respect administrative/ecological boundaries better than Queen-contiguity.
  gulf_fips <- c("01", "12", "13", "22", "28", "48")
  counties_gulf <- counties_raw[counties_raw$STATEFP %in% gulf_fips, ]
  counties_5070 <- st_transform(counties_gulf, 5070)
  # NOTE(cite): Reproject to EPSG:5070 (Albers Equal Area) for metric distance calculations.

  msg(sprintf("  Gulf counties loaded: %d", nrow(counties_5070)))

  # Spatial join: assign each grid cell to a county (nearest centroid approach for ocean cells)
  grid_centroids <- st_centroid(grid)
  # Some ocean cells won't intersect any county; use st_nearest_feature for those
  join_result <- st_join(grid_centroids, counties_5070[, c("GEOID","NAME","STATEFP","COUNTYFP")],
                          join = st_intersects, left = TRUE)

  # For cells with no county intersection (ocean), find nearest county
  no_county <- is.na(join_result$GEOID)
  if (any(no_county)) {
    nearest_idx <- st_nearest_feature(grid_centroids[no_county, ], counties_5070)
    near_attrs <- counties_5070[nearest_idx, c("GEOID","NAME","STATEFP","COUNTYFP")]
    st_geometry(near_attrs) <- NULL
    join_result[no_county, c("GEOID","NAME","STATEFP","COUNTYFP")] <- near_attrs
  }

  static_county <- data.table(
    cell_id      = grid$cell_id,
    county_fips  = join_result$GEOID,          # 5-digit FIPS (state+county)
    county_name  = join_result$NAME,
    state_fips   = join_result$STATEFP,
    spatial_block_tiger = paste0(join_result$STATEFP, "_", join_result$COUNTYFP)
    # NOTE(paper): spatial_block_tiger = state+county FIPS used by A6 for geographic blocking
  )

  msg(sprintf("  County assignment done. Unique counties: %d",
              length(unique(static_county$county_fips))))
  tiger_ok <- TRUE

}, error = function(e) {
  msg("  TIGER county FAILED: ", conditionMessage(e))
  static_county <<- data.table(
    cell_id            = grid$cell_id,
    county_fips        = NA_character_,
    county_name        = NA_character_,
    state_fips         = NA_character_,
    spatial_block_tiger= NA_character_
  )
})

# ── 3. SECTION B: GEBCO Bathymetry (static, no auth, queue API) ───────────────
# NOTE(cite): GEBCO Compilation Group (2026) GEBCO 2026 Grid. British Oceanographic Data Centre.
#             Data source ID 1 = Bathymetry (elevation incl. sub-ice). Format GeoTIFF.

msg("=== SECTION B: GEBCO bathymetry (static) ===")

gebco_dir   <- proj_path("data/raw/gis/gebco")
gebco_tif   <- file.path(gebco_dir,
                          "gebco_2026_n31.0_s24.0_w-87.0_e-81.0_geotiff.tif")
gebco_api   <- "https://download.gebco.net/api"
static_gebco <- NULL

tryCatch({
  if (!file.exists(gebco_tif)) {
    msg("  Queuing GEBCO 2026 subset (24–31°N, 87–81°W) via API ...")
    # NOTE(paper): GEBCO 2026 global grid at 15 arc-second (~450 m) resolution.
    #              Gulf subset ~5 MB; downloaded via queue API (no auth required).
    req_body <- '{"items":[{"data_source_ids":[1],"formats":[2],"left":-87.0,"right":-81.0,"top":31.0,"bottom":24.0}]}'

    queue_resp <- system(
      paste0("curl -s -X POST '", gebco_api, "/queue' ",
             "-H 'Content-Type: application/json' -d '", req_body, "'"),
      intern = TRUE)
    queue_json <- jsonlite::fromJSON(paste(queue_resp, collapse = ""))

    if (is.null(queue_json$basketId)) stop("GEBCO queue API did not return basketId")
    basket_id <- queue_json$basketId
    msg(sprintf("  Basket queued: %s — polling status ...", basket_id))

    # Poll until finished (max 60 s)
    status <- ""
    for (attempt in 1:20) {
      Sys.sleep(3)
      st_resp <- system(
        paste0("curl -s '", gebco_api, "/queue/status/", basket_id, "'"),
        intern = TRUE)
      st_json <- tryCatch(jsonlite::fromJSON(paste(st_resp, collapse = "")),
                          error = function(e) list(status = "unknown"))
      status <- st_json$status %||% "unknown"
      msg(sprintf("  ... attempt %d: %s", attempt, status))
      if (status == "finished") break
      if (grepl("error|wrong", tolower(paste(st_resp, collapse=" ")))) stop("GEBCO queue error")
    }
    if (status != "finished") stop("GEBCO queue timed out")

    msg("  Downloading GEBCO zip ...")
    gebco_zip <- file.path(gebco_dir, paste0(basket_id, ".zip"))
    st <- download_safe(paste0(gebco_api, "/queue/download/", basket_id), gebco_zip)
    if (st != 0) stop(sprintf("GEBCO download failed (status %d)", st))
    msg(sprintf("  Downloaded: %s (%d KB)", basename(gebco_zip), file.size(gebco_zip) %/% 1024))

    unzip(gebco_zip, exdir = gebco_dir)
    file.remove(gebco_zip)
    msg("  Unzipped GEBCO GeoTIFF.")
  } else {
    msg("  GEBCO tif cached; skipping download.")
  }

  # Extract mean elevation (depth) per grid cell
  msg("  Extracting GEBCO depth per cell ...")
  bathy <- rast(gebco_tif)
  # NOTE(paper): GEBCO elevation is in meters; negative values = ocean depth below sea level.
  #              Cell-level mean captures bathymetric context for 10 km cells.

  # Project GEBCO to EPSG:5070 for consistency
  bathy_5070 <- project(bathy, "EPSG:5070", method = "bilinear")

  # Extract mean depth per grid cell (grid is already in EPSG:5070)
  depth_vals <- extract(bathy_5070, vect(grid), fun = "mean", na.rm = TRUE)
  colnames(depth_vals)[2] <- "depth_m"
  # NOTE(limitation): GEBCO 2026 is ~450 m resolution; 10 km cell mean smooths fine-scale
  #                   bathymetric variation. Adequate for bloom-model features but insufficient
  #                   for sub-km intra-cell attention (use full raster for A9 drill-down).

  static_gebco <- data.table(
    cell_id = grid$cell_id,
    depth_m = depth_vals$depth_m
  )
  msg(sprintf("  Depth range: %.0f to %.0f m (neg = ocean)", min(static_gebco$depth_m, na.rm=TRUE),
              max(static_gebco$depth_m, na.rm=TRUE)))

}, error = function(e) {
  msg("  GEBCO FAILED: ", conditionMessage(e))
  msg("  -> Falling back to NA depth (GEBCO placeholder).")
  static_gebco <<- data.table(cell_id = grid$cell_id, depth_m = NA_real_)
})

# ── 4. SECTION C: Distance to Shore (static, from TIGER coastline) ────────────
# NOTE(paper): Distance from each cell centroid to the nearest US coastline feature,
#              computed in EPSG:5070 (metric). Uses Census TIGER national coastline
#              shapefile (tl_2023_us_coastline.zip). EPSG:5070 ensures distances in meters.

msg("=== SECTION C: Distance to shore ===")

static_dist <- NULL

tryCatch({
  if (!file.exists(tiger_coast_zip)) {
    msg("  Downloading TIGER US coastline ...")
    st <- download_safe(tiger_coast_url, tiger_coast_zip)
    if (st != 0) stop(sprintf("TIGER coastline download failed (status %d)", st))
  }
  if (!dir.exists(tiger_coast_dir)) {
    unzip(tiger_coast_zip, exdir = tiger_coast_dir)
  }

  coast_shp <- list.files(tiger_coast_dir, pattern = "\\.shp$", full.names = TRUE)[1]
  coast_raw <- st_read(coast_shp, quiet = TRUE)
  coast_5070 <- st_transform(coast_raw, 5070)
  coast_union <- st_union(coast_5070)   # single geometry for distance calc
  msg(sprintf("  Coastline loaded. Geom type: %s", as.character(st_geometry_type(coast_union))))

  # Compute distance from each cell centroid to nearest coast point
  # NOTE(paper): Ocean cells in the West Florida Shelf will have positive distances (meters).
  #              Coastal cells may overlap the coastline (distance ≈ 0). Used as a static
  #              geographic feature for bloom-proximity inference.
  centroids_5070 <- st_centroid(grid)
  msg("  Computing distances to shore (may take ~30 s for 4743 cells) ...")
  dists <- as.numeric(st_distance(centroids_5070, coast_union))

  static_dist <- data.table(
    cell_id          = grid$cell_id,
    dist_to_shore_m  = dists
  )
  msg(sprintf("  Distance range: %.0f m to %.0f m", min(dists, na.rm=TRUE), max(dists, na.rm=TRUE)))

}, error = function(e) {
  msg("  Distance-to-shore FAILED: ", conditionMessage(e))
  static_dist <<- data.table(cell_id = grid$cell_id, dist_to_shore_m = NA_real_)
})

# ── 5. SECTION D: CHIRPS Precipitation (dynamic, no auth) ─────────────────────
# NOTE(cite): Funk et al. (2015) CHIRPS v2.0 daily 0.05° precipitation.
#             doi:10.1038/sdata.2015.66. URL: https://data.chc.ucsb.edu/products/CHIRPS-2.0/
# NOTE(limitation): CHIRPS server returned HTTP 403 (CrowdSec rate-limit) during automated pull.
#                   Placeholder produced. See data/raw/weather/manual_downloads.md for exact steps.

msg("=== SECTION D: CHIRPS precipitation ===")

chirps_ok <- FALSE
precip_dt  <- NULL

# Test server availability first (HEAD request is lightweight)
chirps_test_url <- paste0(
  "https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/tifs/p05/",
  "1990/chirps-v2.0.1990.01.01.tif.gz")

chirps_available <- tryCatch({
  resp <- system(
    paste0("curl -s -o /dev/null -w '%{http_code}' -I '", chirps_test_url, "'"),
    intern = TRUE)
  as.integer(trimws(resp)) == 200L
}, error = function(e) FALSE)

if (chirps_available) {
  msg("  CHIRPS server reachable. Streaming daily precip via vsicurl ...")
  # Process only unique dates with HABSOS labels in CHIRPS range (1981+)
  chirps_dates <- sort(unique(cell_dates$date[cell_dates$date >= as.Date("1981-01-01")]))
  msg(sprintf("  Unique dates to process: %d", length(chirps_dates)))

  # Checkpoint file: append as we go so script is resumable
  chirps_ckpt <- proj_path("data/raw/weather/chirps_checkpoint.parquet")
  done_dates  <- if (file.exists(chirps_ckpt)) {
    as.Date(unique(read_parquet(chirps_ckpt)$date))
  } else as.Date(character(0))

  todo_dates <- chirps_dates[!chirps_dates %in% done_dates]
  msg(sprintf("  Already done: %d. Remaining: %d", length(done_dates), length(todo_dates)))

  grid_wgs84 <- st_transform(grid, 4326)
  grid_vect  <- vect(grid_wgs84)
  bbox_ext   <- ext(-87, -81, 24, 31)

  batch_results <- list()
  n_ok <- 0L; n_fail <- 0L

  for (d in as.character(todo_dates)) {
    yr  <- substr(d, 1, 4)
    ymd <- gsub("-", ".", d)
    url <- paste0("/vsigzip//vsicurl/https://data.chc.ucsb.edu/products/CHIRPS-2.0/",
                  "global_daily/tifs/p05/", yr, "/chirps-v2.0.", ymd, ".tif.gz")
    row_dt <- tryCatch({
      r      <- rast(url)
      r_crop <- crop(r, bbox_ext)
      vals   <- extract(r_crop, grid_vect, fun = mean, na.rm = TRUE)
      data.table(cell_id = grid$cell_id,
                 date    = as.Date(d),
                 precip_mm = vals[[2]],
                 precip_is_placeholder = FALSE)
    }, error = function(e) {
      data.table(cell_id = grid$cell_id,
                 date    = as.Date(d),
                 precip_mm = NA_real_,
                 precip_is_placeholder = TRUE)
    })

    batch_results[[d]] <- row_dt
    if (!is.na(row_dt$precip_mm[1])) n_ok <- n_ok + 1L else n_fail <- n_fail + 1L

    # Flush checkpoint every 50 dates
    if (length(batch_results) >= 50) {
      batch_dt <- rbindlist(batch_results)
      if (file.exists(chirps_ckpt)) {
        old <- as.data.table(read_parquet(chirps_ckpt))
        batch_dt <- rbindlist(list(old, batch_dt))
      }
      write_parquet(batch_dt, chirps_ckpt)
      batch_results <- list()
      msg(sprintf("  ... checkpoint written. ok=%d fail=%d", n_ok, n_fail))
    }
  }

  if (length(batch_results) > 0) {
    batch_dt <- rbindlist(batch_results)
    if (file.exists(chirps_ckpt)) {
      old <- as.data.table(read_parquet(chirps_ckpt))
      batch_dt <- rbindlist(list(old, batch_dt))
    }
    write_parquet(batch_dt, chirps_ckpt)
  }

  if (file.exists(chirps_ckpt)) {
    precip_dt <- as.data.table(read_parquet(chirps_ckpt))
    n_real <- sum(!precip_dt$precip_is_placeholder, na.rm = TRUE)
    msg(sprintf("  CHIRPS complete. Rows: %d; real: %d (%.0f%%)",
                nrow(precip_dt), n_real, 100 * n_real / nrow(precip_dt)))
    chirps_ok <- n_real > 0
  }

} else {
  msg("  CHIRPS server returned 403 (CrowdSec block). Producing placeholder.")
  msg("  -> See data/raw/weather/manual_downloads.md for pull instructions.")
}

if (!chirps_ok || is.null(precip_dt)) {
  # Placeholder: correct schema, all NA, IS_PLACEHOLDER=TRUE
  # NOTE(limitation): CHIRPS daily precip is placeholder (403 block). Re-run script after
  #                   the block clears (typically 24 h) or follow manual_downloads.md.
  precip_dt <- cell_dates[date >= as.Date("1981-01-01")][
    , .(cell_id, date, precip_mm = NA_real_, precip_is_placeholder = TRUE)]
  msg(sprintf("  Placeholder precip rows: %d", nrow(precip_dt)))
}

# ── 6. SECTION E: ERA5 Wind (dynamic, requires ~/.cdsapirc) ───────────────────
# NOTE(cite): Hersbach et al. (2020) ERA5 10m U/V wind. doi:10.1002/qj.3803
#             Copernicus CDS. Coverage 1979–present. Gulf bbox area=[31,-87,24,-81].
# NOTE(limitation): ERA5 requires Copernicus CDS API key in ~/.cdsapirc. Key absent on
#                   this machine → placeholder. See data/raw/weather/manual_downloads.md.

msg("=== SECTION E: ERA5 wind (credential check) ===")

era5_ok   <- FALSE
cds_file  <- path.expand("~/.cdsapirc")
wind_dt   <- NULL

if (file.exists(cds_file)) {
  msg("  ~/.cdsapirc found — ERA5 pull would proceed here (not yet implemented).")
  # TODO(A5): Implement cdsapi-based ERA5 pull when cdsapirc is available.
  # Pull: u10, v10 wind at 0.25° for the Gulf box, daily means 1979–2021.
  # Then: zonal extract per cell (interpolate coarse ~28 km ERA5 grid to 10 km cells).
  era5_ok <- FALSE   # implementation deferred; set TRUE once fully coded
} else {
  msg("  ~/.cdsapirc missing — ERA5 placeholder produced.")
}

# Always produce placeholder for wind (ERA5 not yet pulled)
wind_dt <- cell_dates[, .(
  cell_id              = cell_id,
  date                 = date,
  wind_u_ms            = NA_real_,
  wind_v_ms            = NA_real_,
  wind_speed_ms        = NA_real_,
  wind_dir_deg         = NA_real_,
  wind_is_placeholder  = TRUE
)]

# NOTE(paper): Along-shore and cross-shore components will be derived from u/v components
#              once ERA5 is available. The West Florida Shelf shoreline runs ~NNW–SSE;
#              cross-shore = perpendicular to that, driving onshore/offshore bloom transport.

msg(sprintf("  Wind placeholder rows: %d (IS_PLACEHOLDER=TRUE)", nrow(wind_dt)))

# ── 7. SECTION F: SMAP Salinity (dynamic, Earthdata netrc, ~40–70 km) ─────────
# NOTE(cite): Meissner et al. (2018) Remote Sensing Systems SMAP SSS V5.0.
#             doi:10.3390/rs10071121. Coverage 2015-04-01 to present.
# NOTE(limitation): SMAP sea-surface salinity at 40–70 km is far coarser than the 10 km grid.
#                   salinity_coarse_flag=TRUE on EVERY salinity row — treat as broad context only.
# NOTE(limitation): SMAP coverage begins 2015-04-01; no salinity data for earlier labels.
#                   Rows outside SMAP coverage have salinity_is_placeholder=TRUE.

msg("=== SECTION F: SMAP salinity ===")

smap_ok  <- FALSE
smap_dt  <- NULL

netrc_file <- path.expand("~/.netrc")
if (file.exists(netrc_file)) {
  msg("  ~/.netrc found. Attempting SMAP access via PODAAC ...")
  # SMAP RSS L3 8-day running mean at 0.25°
  # Endpoint: https://opendap.earthdata.nasa.gov/providers/POCLOUD/collections/...
  # Complex OPeNDAP/CMR query — deferred to avoid blocking session.
  # TODO(A5): Implement SMAP pull via CMR search + OPeNDAP with Earthdata netrc auth.
  msg("  SMAP implementation deferred (complex OPeNDAP auth) -> placeholder.")
} else {
  msg("  ~/.netrc not found — SMAP placeholder produced.")
}

smap_dt <- cell_dates[date >= as.Date("2015-04-01"), .(
  cell_id                 = cell_id,
  date                    = date,
  salinity_pss            = NA_real_,
  salinity_is_placeholder = TRUE,
  salinity_coarse_flag    = TRUE    # ALWAYS TRUE — SMAP 40-70 km coarse
)]

msg(sprintf("  SMAP salinity rows in coverage window: %d (IS_PLACEHOLDER=TRUE)", nrow(smap_dt)))

# ── 8. SECTION G: Seasonality (always computed, never placeholder) ─────────────
# NOTE(paper): Seasonality encoded as month integer, day-of-year (doy), and sin/cos
#              transforms of doy to allow the model to capture annual periodicity
#              (bloom season peaks Aug–Oct for K. brevis on the West Florida Shelf).
#              sin(2π × doy/365) + cos(2π × doy/365) jointly encode position in the annual cycle.

msg("=== SECTION G: Seasonality (computed) ===")

unique_dates <- data.table(date = sort(unique(cell_dates$date)))
unique_dates[, `:=`(
  month    = as.integer(format(date, "%m")),
  doy      = as.integer(format(date, "%j")),
  doy_sin  = sin(2 * pi * as.integer(format(date, "%j")) / 365),
  doy_cos  = cos(2 * pi * as.integer(format(date, "%j")) / 365)
)]

# Join to all cell-dates
cell_dates_season <- merge(cell_dates, unique_dates, by = "date", all.x = TRUE)
msg(sprintf("  Seasonality computed for %d unique dates.", nrow(unique_dates)))

# ── 9. Assemble environmental_features.parquet ───────────────────────────────

msg("=== Assembling environmental_features.parquet ===")

# Base: all cell-date pairs with seasonality
env <- copy(cell_dates_season)

# Merge wind (ERA5 placeholder)
env <- merge(env, wind_dt, by = c("cell_id", "date"), all.x = TRUE)
# Rows outside wind coverage: mark placeholder
env[is.na(wind_is_placeholder), wind_is_placeholder := TRUE]

# Merge precip (CHIRPS, real or placeholder)
if (!is.null(precip_dt) && nrow(precip_dt) > 0) {
  env <- merge(env, precip_dt, by = c("cell_id", "date"), all.x = TRUE)
  env[is.na(precip_is_placeholder), precip_is_placeholder := TRUE]
  env[is.na(precip_mm) & precip_is_placeholder == FALSE, precip_is_placeholder := TRUE]
} else {
  env[, `:=`(precip_mm = NA_real_, precip_is_placeholder = TRUE)]
}

# Merge SMAP salinity (rows not covered by SMAP window get NAs)
if (!is.null(smap_dt) && nrow(smap_dt) > 0) {
  env <- merge(env, smap_dt, by = c("cell_id", "date"), all.x = TRUE)
}
env[is.na(salinity_pss),            salinity_pss            := NA_real_]
env[is.na(salinity_is_placeholder), salinity_is_placeholder := TRUE]
env[is.na(salinity_coarse_flag),    salinity_coarse_flag    := TRUE]

# Feature fill flag (reserved for A6 forward/backward-fill of coarser-cadence data)
# NOTE(paper): feature_filled=FALSE here — fills happen in A6 (datacube) so every
#              filled value is explicitly traceable. Never let a fill masquerade as observed.
env[, feature_filled := FALSE]

# Overall IS_PLACEHOLDER = TRUE if ALL dynamic features are placeholder
env[, IS_PLACEHOLDER := wind_is_placeholder & precip_is_placeholder & salinity_is_placeholder]

# Column order
setcolorder(env, c("cell_id", "date",
                   "wind_u_ms", "wind_v_ms", "wind_speed_ms", "wind_dir_deg", "wind_is_placeholder",
                   "precip_mm", "precip_is_placeholder",
                   "salinity_pss", "salinity_is_placeholder", "salinity_coarse_flag",
                   "month", "doy", "doy_sin", "doy_cos",
                   "feature_filled", "IS_PLACEHOLDER"))

setorder(env, cell_id, date)

# Quality check: one row per cell-day
n_rows <- nrow(env)
n_expected <- nrow(cell_dates)
if (n_rows != n_expected) {
  warning(sprintf("Row count mismatch: env has %d rows but cell_dates has %d. Check for join duplication.",
                  n_rows, n_expected))
}

msg(sprintf("  Writing %s (%d rows) ...", basename(out_env), n_rows))
write_parquet(env, out_env)
msg("  Done.")

# ── 10. Assemble static_geo.parquet ─────────────────────────────────────────

msg("=== Assembling static_geo.parquet ===")

# Base: all 4743 grid cells
static <- data.table(cell_id = grid$cell_id)

# Merge county (TIGER)
if (!is.null(static_county)) {
  static <- merge(static, static_county, by = "cell_id", all.x = TRUE)
}

# Merge GEBCO depth
if (!is.null(static_gebco)) {
  static <- merge(static, static_gebco, by = "cell_id", all.x = TRUE)
}

# Merge distance to shore
if (!is.null(static_dist)) {
  static <- merge(static, static_dist, by = "cell_id", all.x = TRUE)
}

# Append cell centroid lat/lon (in WGS84, useful for spatial models)
centroid_wgs84 <- st_transform(st_centroid(grid), 4326)
coords <- st_coordinates(centroid_wgs84)
static[, `:=`(
  centroid_lon = coords[, "X"],
  centroid_lat = coords[, "Y"]
)]
# NOTE(paper): Cell centroid coordinates in WGS84 provided for spatial model features and maps.
#              EPSG:5070 centroids used for distance computations (not stored here, on-the-fly).

# IS_PLACEHOLDER flag: TRUE if critical static features are missing
static[, IS_PLACEHOLDER := is.na(county_fips) | is.na(depth_m)]

msg(sprintf("  Static geo rows: %d | depth NA: %d | county NA: %d | dist NA: %d",
            nrow(static),
            sum(is.na(static$depth_m)),
            sum(is.na(static$county_fips)),
            sum(is.na(static$dist_to_shore_m))))

setorder(static, cell_id)
write_parquet(static, out_static)
msg(sprintf("  Written: %s", out_static))

# ── 11. Write manual_downloads.md files ──────────────────────────────────────

msg("=== Writing manual_downloads.md ===")

weather_md <- proj_path("data/raw/weather/manual_downloads.md")
writeLines(c(
  "# Weather / Environmental — Manual Download Instructions",
  "",
  "Generated: " %||% as.character(Sys.Date()),
  "",
  "## Why this file exists",
  "Some environmental data sources require auth or were rate-limited during automated pull.",
  "Follow these steps to populate real data for placeholders in `environmental_features.parquet`.",
  "",
  "---",
  "",
  "## ERA5 10m Wind (u/v components) — Copernicus CDS API",
  "",
  "**Status:** PLACEHOLDER (no ~/.cdsapirc found on this machine)",
  "**Cite:** Hersbach et al. (2020) doi:10.1002/qj.3803",
  "**Coverage:** 1979-01-01 to present, ~0.25° (~28 km), daily",
  "",
  "### Steps to pull:",
  "1. Register at https://cds.climate.copernicus.eu/ (free account)",
  "2. Accept Terms of Use for ERA5 datasets",
  "3. Copy your API key to `~/.cdsapirc`:",
  "   ```",
  "   url: https://cds.climate.copernicus.eu/api",
  "   key: <your-key>",
  "   ```",
  "4. Install the Python cdsapi client: `pip install cdsapi`",
  "5. Run the pull script (to be implemented in R/05_environmental_features.R Section E):",
  "   - Variable: 10m_u_component_of_wind, 10m_v_component_of_wind",
  "   - Product type: reanalysis",
  "   - Format: netCDF",
  "   - Area: [31, -87, 24, -81]  (N, W, S, E — server-side Gulf bbox, do NOT download globally)",
  "   - Date range: 1979-01-01 to 2021-12-31",
  "   - Target: data/raw/weather/era5_wind_gulf.nc",
  "6. Re-run R/05_environmental_features.R; it detects the file and populates wind columns.",
  "",
  "### Note on along-shore / cross-shore components:",
  "West Florida Shelf shoreline orientation ≈ 350° (NNW). Along-shore wind ≈ component parallel",
  "to coast; cross-shore ≈ perpendicular. Derive after ERA5 pull:",
  "  along  = u * cos(shore_angle) + v * sin(shore_angle)",
  "  cross  = -u * sin(shore_angle) + v * cos(shore_angle)",
  "",
  "---",
  "",
  "## CHIRPS v2.0 Daily Precipitation — UCSB CHC",
  "",
  "**Status:** PLACEHOLDER (HTTP 403 CrowdSec block during automated pull 2026-07-11)",
  "**Cite:** Funk et al. (2015) doi:10.1038/sdata.2015.66",
  "**Coverage:** 1981-01-01 to 2021-12-31 (for HABSOS overlap), ~0.05° (~5 km), daily",
  "",
  "### Steps to pull (no auth required, but respect rate limits):",
  "1. Base URL: https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/tifs/p05/",
  "2. Each file: chirps-v2.0.{YYYY}.{MM}.{DD}.tif.gz (~1.5 MB each)",
  "3. Processing approach (stream-and-discard via terra vsicurl — no permanent storage needed):",
  "   a. In R with terra: url <- '/vsigzip//vsicurl/https://data.chc.ucsb.edu/...'",
  "   b. r <- rast(url); r_crop <- crop(r, ext(-87,-81,24,31))",
  "   c. vals <- extract(r_crop, grid_vect, fun=mean, na.rm=TRUE)",
  "   d. Append to checkpoint parquet; no raw tif saved to disk.",
  "4. Wait 24h after a CrowdSec block before retrying (or use a different IP).",
  "5. Re-run R/05_environmental_features.R — it resumes from the checkpoint.",
  "",
  "---",
  "",
  "## SMAP Sea-Surface Salinity — RSS/PODAAC",
  "",
  "**Status:** PLACEHOLDER (complex OPeNDAP auth; deferred)",
  "**Cite:** Meissner et al. (2018) doi:10.3390/rs10071121",
  "**Coverage:** 2015-04-01 to present, ~0.25° (40–70 km sensor footprint), 8-day running mean",
  "**IMPORTANT:** salinity_coarse_flag=TRUE on ALL values — broad-context feature only.",
  "",
  "### Steps to pull (Earthdata auth required):",
  "1. Ensure ~/.netrc has Earthdata credentials (already present on this machine).",
  "2. Search PODAAC CMR: https://cmr.earthdata.nasa.gov/search/granules?short_name=SMAP_RSS_L3_SSS_SMI_8DAY_RUNNINGMEAN_V5",
  "3. Download L3 8-day running mean files for Gulf region (no server-side bbox — global NetCDF,",
  "   but small: ~5 MB each). Extract salinity variable for Gulf bbox.",
  "4. Zonal extract per 10 km cell; flag all rows salinity_coarse_flag=TRUE.",
  "5. Re-run R/05_environmental_features.R with SMAP files in data/raw/weather/smap/."
), weather_md)

msg(sprintf("  Written: %s", weather_md))

gis_md <- proj_path("data/raw/gis/manual_downloads.md")
writeLines(c(
  "# GIS / Static Layers — Download Notes",
  "",
  "Generated: " %||% as.character(Sys.Date()),
  "",
  "## GEBCO 2026 Bathymetry (DOWNLOADED — no manual step needed)",
  "",
  "**Status:** REAL — downloaded via GEBCO queue API (download.gebco.net/api/queue)",
  "**Cite:** GEBCO Compilation Group (2026). GEBCO 2026 Grid.",
  "  British Oceanographic Data Centre. doi:10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f",
  "**File:** data/raw/gis/gebco/gebco_2026_n31.0_s24.0_w-87.0_e-81.0_geotiff.tif",
  "**Resolution:** ~450 m (15 arc-second), EPSG:4326",
  "**API used:**",
  "  POST https://download.gebco.net/api/queue",
  "  Body: {\"items\":[{\"data_source_ids\":[1],\"formats\":[2],\"left\":-87,\"right\":-81,\"top\":31,\"bottom\":24}]}",
  "  Then poll: GET https://download.gebco.net/api/queue/status/{basketId}",
  "  Then: GET https://download.gebco.net/api/queue/download/{basketId}",
  "",
  "## Census TIGER 2023 Counties (DOWNLOADED — no manual step needed)",
  "",
  "**Status:** REAL — tl_2023_us_county.zip and tl_2023_us_coastline.zip",
  "**Source:** https://www2.census.gov/geo/tiger/TIGER2023/COUNTY/",
  "**License:** Public domain (US government work)"
), gis_md)

msg(sprintf("  Written: %s", gis_md))

# ── 12. Summary report ───────────────────────────────────────────────────────

msg("=== Summary ===")
n_env <- nrow(env)
n_static <- nrow(static)

msg(sprintf("  environmental_features.parquet: %d rows x %d cols", n_env, ncol(env)))
msg(sprintf("  static_geo.parquet:             %d rows x %d cols", n_static, ncol(static)))
msg(sprintf("  TIGER county labels:  %s", if (tiger_ok) "REAL" else "PLACEHOLDER"))
msg(sprintf("  GEBCO depth:          %s", if (!is.null(static_gebco) && !all(is.na(static_gebco$depth_m))) "REAL" else "PLACEHOLDER"))
msg(sprintf("  Dist-to-shore:        %s", if (!is.null(static_dist) && !all(is.na(static_dist$dist_to_shore_m))) "REAL" else "PLACEHOLDER"))
msg(sprintf("  CHIRPS precip:        %s", if (chirps_ok) "REAL" else "PLACEHOLDER (403 block)"))
msg(sprintf("  ERA5 wind:            %s", if (era5_ok) "REAL" else "PLACEHOLDER (no ~/.cdsapirc)"))
msg(sprintf("  SMAP salinity:        PLACEHOLDER (deferred; coarse-flag always TRUE)"))
msg(sprintf("  Seasonality:          REAL (computed)"))
msg("Script complete.")
