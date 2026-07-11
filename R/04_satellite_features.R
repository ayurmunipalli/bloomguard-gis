# ============================================================
# FILE: 04_satellite_features.R
# OWNER: A4 sat-features (reviewer R4)
# PURPOSE: Per cell x date MODIS-Aqua Level-3 daily mapped satellite features
#          (chlor_a, SST, nFLH, Kd_490) aggregated to the 10 km study grid.
#          Implements mandatory STREAM-AND-DISCARD loop (PLAN.md §6-A4, CLAUDE.md).
# INPUTS:
#   - data/processed/study_area_grid.gpkg (A2 output, 4743 cells, EPSG:5070)
#   - data/processed/habsos_labels.parquet (A3 output, for satellite-era dates)
#   - NASA Earthdata credentials (~/.netrc, machine urs.earthdata.nasa.gov)
# OUTPUTS:
#   - data/processed/satellite_features.parquet
#     Schema: cell_id | date | chlor_a_mean | chlor_a_n_valid | sst_mean |
#             sst_n_valid | nflh_mean | nflh_n_valid | Kd_490_mean |
#             Kd_490_n_valid | cloud_flag | feature_filled | IS_PLACEHOLDER
# TECHNIQUES:
#   - OB.DAAC file-search API to resolve daily file URLs
#   - R curl package for authenticated download (NASA Earthdata OAuth via netrc+cookies)
#   - terra::crop() + terra::project() for bbox clip and EPSG:4326->EPSG:5070
#   - terra::rasterize() + terra::zonal() for mean & valid-pixel-count per cell
#   - Stream-and-discard: download 1 day -> clip -> aggregate -> append -> unlink()
#   - Checkpoint by date: dates in existing parquet are skipped on re-run
# CITATIONS:
#   - NASA OB.DAAC MODIS-Aqua L3m CHL: DOI 10.5067/AQUA/MODIS/L3M/CHL/2022.0
#   - NASA OB.DAAC MODIS-Aqua L3m SST: DOI 10.5067/AQUA/MODIS/L3M/SST/2019.0
#   - NASA OB.DAAC MODIS-Aqua L3m FLH: DOI 10.5067/AQUA/MODIS/L3M/FLH/2022.0
#   - NASA OB.DAAC MODIS-Aqua L3m KD490: DOI 10.5067/AQUA/MODIS/L3M/KD/2022.0
#   - Hu et al. (2022) Harmful Algae 117:102289 (study area definition)
# ============================================================

# NOTE(paper): STREAM-AND-DISCARD mandatory — MODIS L3m is global-file-only
#              (no server-side bbox). Per day: download one global file (~13 MB)
#              -> clip to bbox (24-31N/87-81W) -> aggregate to 10 km grid ->
#              append rows -> unlink() raw file. Peak disk <= one file + Parquet.
# NOTE(paper): MODIS-Aqua operational from ~mid-2002; satellite era defined
#              as 2003-01-01 to 2021-12-31 intersected with HABSOS sample dates.
#              Pre-2003 label rows have no satellite features (handled by A6 join).
# NOTE(paper): MODIS ~4.6 km pixels -> ~4-6 pixels per 10 km cell.
#              Cell statistics are means of those 4-6 pixels; no sub-pixel precision.
# NOTE(paper): FAI (Floating Algae Index, Hu 2009) requires MODIS bands at ~859 nm
#              and ~1240 nm which are NOT distributed in OB.DAAC L3m products.
#              FAI would require L2 processing — documented as a limitation;
#              nFLH is retained as the bloom-detection proxy available from L3m.
# NOTE(cite): NASA OB.DAAC file search API: https://oceandata.sci.gsfc.nasa.gov/api/file_search
# NOTE(limitation): Cloud cover causes many cells to have zero valid pixels on a
#                   given day (cloud_flag = TRUE). These are NOT zero-filled;
#                   A6 handles gap-filling with feature_filled flag.
# NOTE(limitation): nFLH can be negative over clear/low-biomass water (sensor noise);
#                   these values are retained and should be treated with caution.
# NOTE(limitation): Dates are intersected with HABSOS sample dates to limit download
#                   volume. A full satellite-era pull (2003-2021 daily) would require
#                   ~300+ GB of download and is beyond single-session scope.
#                   The checkpoint system allows the loop to be extended incrementally.
# NOTE(paper): SST daytime product used (L3m.DAY.SST.sst.4km). Night SST4 has
#              fewer atmospheric aerosol effects but lower coverage in the Gulf.

# ── Bootstrap ──────────────────────────────────────────────────────────────────
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

# ── Packages ───────────────────────────────────────────────────────────────────
suppressMessages({
  if (!requireNamespace("terra",      quietly = TRUE)) stop("terra required")
  if (!requireNamespace("sf",         quietly = TRUE)) stop("sf required")
  if (!requireNamespace("arrow",      quietly = TRUE)) stop("arrow required")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("data.table required")
  if (!requireNamespace("curl",       quietly = TRUE)) stop("curl required")
  library(terra)
  library(sf)
  library(arrow)
  library(data.table)
  library(curl)
})

# ── Config ─────────────────────────────────────────────────────────────────────
ROOT        <- PROJECT_ROOT
BBOX_WGS84  <- with(cfg$study_area$bbox_wgs84, ext(xmin, xmax, ymin, ymax))  # terra ext
CRS_PROJ    <- cfg$study_area$crs_projected       # "EPSG:5070"
SAT_START   <- as.Date("2003-01-01")
SAT_END     <- as.Date("2021-12-31")
OUT_PARQUET <- proj_path(cfg$paths$satellite_features)  # data/processed/satellite_features.parquet
GRID_PATH   <- proj_path(cfg$paths$grid)
LABELS_PATH <- proj_path(cfg$paths$habsos_labels)
RAW_DIR     <- proj_path(cfg$paths$raw_satellite)
COOKIE_FILE <- file.path(tempdir(), "urs_cookies.txt")
OBDAAC_SEARCH <- "https://oceandata.sci.gsfc.nasa.gov/api/file_search"
OBDAAC_GET    <- "https://oceandata.sci.gsfc.nasa.gov/getfile/"

# MODIS-Aqua L3m daily products: (product_code, variable_name, nc_varname)
# NOTE(cite): product codes per OB.DAAC naming convention AQUA_MODIS.YYYYMMDD.L3m.DAY.<PROD>.<var>.4km.nc
PRODUCTS <- list(
  list(prod = "CHL",  var = "chlor_a", nc_var = "chlor_a", units = "mg m-3"),
  list(prod = "SST",  var = "sst",     nc_var = "sst",     units = "celsius"),
  list(prod = "FLH",  var = "nflh",    nc_var = "nflh",    units = "mW cm-2 um-1 sr-1"),
  list(prod = "KD",   var = "Kd_490",  nc_var = "Kd_490",  units = "m-1")
)

# ── Helper: build file URL for a given date and product ────────────────────────
obdaac_url <- function(date_val, prod) {
  ds <- format(date_val, "%Y%m%d")
  paste0(OBDAAC_GET, "AQUA_MODIS.", ds, ".L3m.DAY.", prod$prod, ".", prod$var, ".4km.nc")
}

# ── Helper: authenticated download using curl package ──────────────────────────
# Returns TRUE on success, FALSE on failure (network/auth/missing date)
download_modis <- function(url, destfile, cookie_file = COOKIE_FILE,
                           netrc_file = path.expand("~/.netrc"),
                           timeout = 300) {
  h <- new_handle()
  handle_setopt(h,
    netrc          = 1L,
    netrc_file     = netrc_file,
    cookiefile     = cookie_file,
    cookiejar      = cookie_file,
    followlocation = 1L,
    maxredirs      = 10L,
    timeout        = timeout,
    low_speed_limit = 1024L,   # abort if < 1 KB/s
    low_speed_time  = 60L
  )
  tryCatch({
    curl_download(url, destfile, handle = h, quiet = TRUE)
    sz <- file.size(destfile)
    if (is.na(sz) || sz < 10000L) {   # file too small -> likely auth error page
      unlink(destfile)
      return(FALSE)
    }
    TRUE
  }, error = function(e) {
    unlink(destfile)
    FALSE
  })
}

# ── Helper: aggregate one raster product to 10km grid ──────────────────────────
# Returns data.table with cell_id, <var>_mean, <var>_n_valid; or NULL on failure.
aggregate_to_grid <- function(nc_file, prod, grid_vect, bbox, crs_proj) {
  r <- tryCatch(rast(nc_file), error = function(e) NULL)
  if (is.null(r)) return(NULL)

  # Select correct layer by nc_var name when file contains multiple layers
  # (e.g. MODIS SST product ships sst + qual_sst in the same NetCDF)
  if (nlyr(r) > 1) {
    idx <- which(names(r) == prod$nc_var)
    if (length(idx) == 0L) idx <- 1L   # fallback: first layer
    r <- r[[idx[1]]]
  }

  # Crop to study bbox (WGS84)
  r_crop <- crop(r, bbox)
  names(r_crop) <- prod$var

  # Reproject to projected CRS for correct area-based aggregation
  # NOTE(paper): bilinear reproject used; nearest-neighbor would be appropriate for
  #              categorical data but all MODIS ocean color variables are continuous.
  r_proj <- project(r_crop, crs_proj, method = "bilinear")

  # Zone raster: assign each ~4 km pixel to a 10 km cell
  zone_r <- rasterize(grid_vect, r_proj, field = "cell_id")

  # Mean of valid (non-NA) pixels per cell
  z_mean <- as.data.table(zonal(r_proj, zone_r, fun = "mean", na.rm = TRUE))
  setnames(z_mean, c("cell_id", paste0(prod$var, "_mean")))

  # Count of valid pixels per cell
  valid_r <- r_proj
  vals <- values(valid_r)
  values(valid_r) <- as.integer(!is.na(vals))
  z_count <- as.data.table(zonal(valid_r, zone_r, fun = "sum", na.rm = TRUE))
  setnames(z_count, c("cell_id", paste0(prod$var, "_n_valid")))

  merge(z_mean, z_count, by = "cell_id")
}

# ── Load grid ──────────────────────────────────────────────────────────────────
message("[A4] Loading study area grid from ", GRID_PATH)
grid_sf   <- st_read(GRID_PATH, quiet = TRUE)
grid_vect <- vect(grid_sf)   # terra SpatVector, EPSG:5070
message("[A4] Grid: ", nrow(grid_sf), " cells, CRS ", st_crs(grid_sf)$epsg)

# ── Get satellite-era dates to process ─────────────────────────────────────────
# NOTE(paper): dates intersected with HABSOS sample dates (2003-2021) to limit
#              download volume. Full-era daily pull requires incremental resumption.
message("[A4] Loading HABSOS label dates for satellite era filtering")
hab  <- as.data.table(read_parquet(LABELS_PATH))
# Rename for consistency (A3 uses sample_date)
if ("sample_date" %in% names(hab) && !"date" %in% names(hab)) {
  setnames(hab, "sample_date", "date")
}
all_dates <- sort(unique(hab[date >= SAT_START & date <= SAT_END, date]))
message("[A4] Satellite era: ", length(all_dates), " unique dates (",
        format(min(all_dates)), " to ", format(max(all_dates)), ")")

# ── Checkpoint: skip already-processed dates ────────────────────────────────────
done_dates <- as.Date(character(0))
if (file.exists(OUT_PARQUET)) {
  existing <- as.data.table(read_parquet(OUT_PARQUET))
  if ("date" %in% names(existing) && nrow(existing) > 0) {
    done_dates <- sort(unique(existing$date))
    message("[A4] Checkpoint: ", length(done_dates), " dates already in output; skipping.")
  }
  rm(existing)
  gc()
}

process_dates <- setdiff(as.character(all_dates), as.character(done_dates))
process_dates <- as.Date(process_dates)
message("[A4] Dates to process: ", length(process_dates))

if (length(process_dates) == 0) {
  message("[A4] All dates already processed. Output exists at ", OUT_PARQUET)
  stop("Nothing to do — pipeline is complete. Remove checkpoint to rerun.")
}

# ── Main stream-and-discard loop ───────────────────────────────────────────────
# Per day: download 4 global files -> clip -> aggregate -> append rows -> unlink()
# Peak disk usage: ~4 files × ~10-15 MB = ~50 MB at a time.

accumulated <- list()   # hold rows until flush to Parquet
FLUSH_EVERY  <- 50L     # write parquet every N dates
n_ok  <- 0L
n_err <- 0L
TOTAL <- length(process_dates)

for (i in seq_along(process_dates)) {
  d  <- process_dates[i]
  ds <- format(d, "%Y%m%d")

  if (i %% 10 == 0 || i == 1) {
    message(sprintf("[A4] Progress: %d/%d  date=%s  ok=%d  err=%d",
                    i, TOTAL, d, n_ok, n_err))
  }

  prod_results <- list()

  for (prod in PRODUCTS) {
    url  <- obdaac_url(d, prod)
    dest <- file.path(RAW_DIR, paste0("tmp_", ds, "_", prod$prod, ".nc"))

    ok <- download_modis(url, dest)
    if (!ok) {
      # NOTE(limitation): Missing file = no MODIS pass for this date+product
      #   (common: instrument downtime, transmission gaps, 100% cloud cover).
      next
    }

    agg <- aggregate_to_grid(dest, prod, grid_vect, BBOX_WGS84, CRS_PROJ)

    # Delete raw file immediately after processing (STREAM-AND-DISCARD)
    unlink(dest)

    if (!is.null(agg)) prod_results[[prod$var]] <- agg
  }

  # Build one row per cell for this date (all products merged)
  if (length(prod_results) == 0) {
    n_err <- n_err + 1L
    next
  }

  day_dt <- Reduce(function(a, b) merge(a, b, by = "cell_id", all = TRUE), prod_results)
  day_dt[, date         := d]
  day_dt[, feature_filled := FALSE]   # A6 sets TRUE if gap-filled
  day_dt[, cloud_flag   := TRUE]      # will be corrected below

  # cloud_flag = TRUE only if ALL 4 products have 0 valid pixels for that cell
  n_cols <- paste0(c("chlor_a", "sst", "nflh", "Kd_490"), "_n_valid")
  n_cols_present <- intersect(n_cols, names(day_dt))
  if (length(n_cols_present) > 0) {
    day_dt[, cloud_flag := rowSums(.SD, na.rm = TRUE) == 0, .SDcols = n_cols_present]
  }

  day_dt[, IS_PLACEHOLDER := FALSE]

  # Ensure all expected columns present (NULL if product failed that day)
  for (prod in PRODUCTS) {
    mc <- paste0(prod$var, "_mean");   if (!mc %in% names(day_dt)) day_dt[, (mc) := NA_real_]
    nc <- paste0(prod$var, "_n_valid"); if (!nc %in% names(day_dt)) day_dt[, (nc) := 0L]
  }

  accumulated[[length(accumulated) + 1]] <- day_dt
  n_ok <- n_ok + 1L

  # Flush to Parquet every FLUSH_EVERY dates (or on the last date)
  if (length(accumulated) >= FLUSH_EVERY || i == TOTAL) {
    new_rows <- rbindlist(accumulated, use.names = TRUE, fill = TRUE)
    accumulated <- list()

    if (file.exists(OUT_PARQUET)) {
      existing  <- as.data.table(read_parquet(OUT_PARQUET))
      combined  <- rbindlist(list(existing, new_rows), use.names = TRUE, fill = TRUE)
      rm(existing)
    } else {
      combined <- new_rows
    }

    write_parquet(combined, OUT_PARQUET)
    rm(combined, new_rows)
    gc()
    message(sprintf("[A4] Flushed to %s  (dates processed so far: %d)", OUT_PARQUET, n_ok))
  }
}

# ── Summary ────────────────────────────────────────────────────────────────────
message("")
message("=== A4 sat-features run complete ===")
message("Dates processed (ok):  ", n_ok)
message("Dates skipped (error): ", n_err)
message("Output: ", OUT_PARQUET)

if (file.exists(OUT_PARQUET)) {
  final <- as.data.table(read_parquet(OUT_PARQUET))
  message("Output rows:            ", nrow(final))
  message("Output dates:           ", length(unique(final$date)))
  message("Date range:             ", format(min(final$date)), " to ", format(max(final$date)))
  message("Cells with chlor_a:     ", sum(!is.na(final$chlor_a_mean)))
  message("Cloud-flagged rows:     ", sum(final$cloud_flag, na.rm = TRUE))
  message("IS_PLACEHOLDER rows:    ", sum(final$IS_PLACEHOLDER, na.rm = TRUE))
  message("Schema: ", paste(names(final), collapse = ", "))
  rm(final)
}

message("[A4] Done. Script is resumable — re-run to process remaining dates.")
