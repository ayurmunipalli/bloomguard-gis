# ============================================================
# FILE: 04b_bio_optical_features.R
# OWNER: sat-features (A4b bio-optical species-discrimination add-on)
# PURPOSE: Per cell x date K. brevis bio-optical species-discrimination features
#          (RBD, KBBI, Cannizzaro-vs-Morel low-bbp-per-chlorophyll score),
#          aggregated to the 10 km study grid, joined to the SAME date set as
#          the existing MODIS cube. ADDITIVE ONLY — does not modify, rebuild,
#          or overwrite satellite_features.parquet, the datacube, or M1/M2.
# INPUTS:
#   - data/processed/study_area_grid.gpkg      (A2 output, 4743 cells, EPSG:5070)
#   - data/processed/satellite_features.parquet (A4 output; READ-ONLY here —
#     provides (a) the exact date set to pull so the join stays 1:1, and
#     (b) chlor_a_mean per cell x date used by the Cannizzaro/Morel score)
#   - NASA Earthdata credentials (~/.netrc, machine urs.earthdata.nasa.gov)
# OUTPUTS:
#   - data/processed/satellite_features_bio_optical.parquet
#     Schema: cell_id | date | rrs_667_mean | rrs_667_n_valid | rrs_678_mean |
#             rrs_678_n_valid | bbp_443_mean | bbp_443_n_valid | bbp_s_mean |
#             bbp_s_n_valid | nlw_667 | nlw_678 | rbd | kbbi | rbd_detect |
#             kbbi_kbrevis | chlor_a_mean | chl_missing | bbp_551 |
#             bbp_morel_550 | bbp_ratio_morel | bbp_deficit |
#             cannizzaro_kbrevis | bio_cloud_flag | bio_feature_filled |
#             IS_PLACEHOLDER
# TECHNIQUES:
#   - OB.DAAC getfile direct URL pull (same pattern as R/04_satellite_features.R)
#   - R curl package for authenticated download (NASA Earthdata OAuth via
#     netrc + cookiejar), stream-and-discard, resumable by-date checkpoint
#   - terra::crop() + terra::project() for bbox clip and EPSG:4326->EPSG:5070
#   - terra::rasterize() + terra::zonal() for mean & valid-pixel-count per cell
#   - nLw(lambda) = Rrs(lambda) x F0(lambda); RBD/KBBI (Amin 2009 Eq.19/20);
#     bbp(551) power-law from bbp_443/bbp_s (Cannizzaro 2008 Eq.14); Morel
#     (1988) Case-1 bbp(550) reference curve; Cannizzaro (2008) Sec.6.1
#     Chl>1.5 & bbp(550)<bbp_Morel(550) classification rule.
# CITATIONS:
#   - Amin, R. et al. (2009). "Novel optical techniques for detecting and
#     classifying toxic dinoflagellate Karenia brevis blooms using satellite
#     imagery." Optics Express 17(11):9126-9144. doi:10.1364/OE.17.009126.
#     Bands: Fig.1 caption p.9134 (MODIS Band13=667nm, Band14=678nm). nLw
#     conversion: Sec.3.1 end, p.9133. RBD: Eq.19 p.9133. KBBI: Eq.20 p.9134.
#     Thresholds: Abstract p.9126; Sec.4.1 p.9135.
#   - Cannizzaro, J.P., Carder, K.L., Chen, F.R., Heil, C.A., Vargo, G.A.
#     (2008). "A novel technique for detection of the toxic dinoflagellate,
#     Karenia brevis, in the Gulf of Mexico from remotely sensed ocean color
#     data." Continental Shelf Research 28(1):137-158.
#     doi:10.1016/j.csr.2004.04.007. bbp spectral power law: Eq.14 p.146.
#     Classification rule: Sec.6.1 p.150 (Fig.9C).
#   - Morel, A. (1988). "Optical modeling of the upper ocean in relation to
#     its biogenous matter content (case I waters)." J. Geophys. Res.
#     93(C9):10749-10768. doi:10.1029/JC093iC09p10749. bbp(550) reference
#     curve: unnumbered eq. p.10760 (== Amin 2009 Eq.16, cross-checked).
#   - NASA OBPG "Spectral Bandpass Integration" (rsr_tables) — authoritative
#     band-averaged extraterrestrial solar irradiance (F0), MODIS-Aqua,
#     Thuillier reference solar spectrum convolved with the sensor RSR.
#     https://oceancolor.gsfc.nasa.gov/resources/docs/rsr_tables/ ->
#     https://oceancolor.gsfc.nasa.gov/images/rsr/modis-aqua_bandpass.csv
#     (accessed 2026-07-14). See NOTE(cite) at F0 constants below for values.
#   - NASA OB.DAAC MODIS-Aqua L3m RRS: DOI 10.5067/AQUA/MODIS/L3M/RRS/2022.0
#   - NASA OB.DAAC MODIS-Aqua L3m IOP: DOI 10.5067/AQUA/MODIS/L3M/IOP/2022.0
# ============================================================

# NOTE(paper): This script is an ADDITIVE companion to R/04_satellite_features.R.
#              It does not read from, write to, or modify satellite_features.parquet
#              except as a READ-ONLY source of (1) the date set and (2) chlor_a.
# NOTE(paper): STREAM-AND-DISCARD mandatory (same discipline as R/04) — MODIS L3m
#              is global-file-only. Per date: download 4 global files -> clip to
#              bbox (24-31N/87-81W) -> aggregate to 10 km grid -> append rows ->
#              unlink() raw files. Peak disk <= 4 files (~5-13 MB each) + Parquet.
# NOTE(paper): FAI stays DROPPED (paper/design_rationale.md Sec.4.2) — not
#              computable from daily L3m bands (needs ~859nm/~1240nm at L2 only
#              for the NIR/SWIR baseline). Not reintroduced here.
# NOTE(limitation): RBD/KBBI/bbp scores require BOTH bands (667+678, or
#              bbp_443+bbp_s) to be cloud-free/valid on the SAME day for the SAME
#              cell. Because two independent products must both retrieve, the
#              joint-valid rate is lower than either single product's coverage.
#              Missing -> NA (never zero-filled); flagged via *_n_valid columns.

# ── Bootstrap ──────────────────────────────────────────────────────────────────
# NOTE(limitation): this repo's `.Rprofile` sources `renv/activate.R`, which was
#   found (2026-07-14) to hang indefinitely in this execution environment
#   (evidence: a bare `Rscript -e 'cat("hi")'` with no network/arrow hangs at
#   0% CPU with .Rprofile active, but returns instantly with `--vanilla`). This
#   script is therefore run with `--vanilla` (skips .Rprofile/renv activation),
#   so renv's project-local package library is added to .libPaths() manually
#   here as a fallback — harmless no-op if renv DID activate normally.
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  renv_libs <- Sys.glob(file.path(d, "renv", "library", "*", "*", "*"))
  if (length(renv_libs) > 0) .libPaths(unique(c(renv_libs, .libPaths())))
  source(file.path(d, "R", "00_config.R"))
})

# ── Packages ───────────────────────────────────────────────────────────────────
# NOTE(limitation): 2026-07-14 — R's `curl` package (this machine's libcurl
#   build) was found to (a) fail the NASA Earthdata OAuth redirect's Basic
#   auth without a non-default `httpauth` flag, AND (b) fail entirely under
#   the sandboxed Bash tool with "Proxy CONNECT aborted" even with that flag.
#   The system `curl` binary has neither problem (confirmed via live testing,
#   both sandboxed and unsandboxed). `download_modis()` below therefore shells
#   out to system `curl` via `system2()` instead of using the R `curl` package
#   — this also means the whole script no longer needs `dangerouslyDisableSandbox`
#   to reach NASA Earthdata, only `--vanilla` to dodge the renv hang above.
suppressMessages({
  if (!requireNamespace("terra",      quietly = TRUE)) stop("terra required")
  if (!requireNamespace("sf",         quietly = TRUE)) stop("sf required")
  if (!requireNamespace("arrow",      quietly = TRUE)) stop("arrow required")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("data.table required")
  library(terra)
  library(sf)
  library(arrow)
  library(data.table)
})

# ── Config ─────────────────────────────────────────────────────────────────────
ROOT         <- PROJECT_ROOT
BBOX_WGS84   <- with(cfg$study_area$bbox_wgs84, ext(xmin, xmax, ymin, ymax))  # terra ext
CRS_PROJ     <- cfg$study_area$crs_projected       # "EPSG:5070"
OUT_PARQUET  <- proj_path("data/processed/satellite_features_bio_optical.parquet")
GRID_PATH    <- proj_path(cfg$paths$grid)
SAT_PARQUET  <- proj_path(cfg$paths$satellite_features)   # READ-ONLY source of dates + chlor_a
RAW_DIR      <- proj_path(cfg$paths$raw_satellite)
COOKIE_FILE  <- file.path(tempdir(), "urs_cookies_bio.txt")
OBDAAC_GET   <- "https://oceandata.sci.gsfc.nasa.gov/getfile/"
LOCK_DIR     <- file.path(RAW_DIR, ".bio_pull.lock")   # a DIRECTORY, not a file — see below
LOCK_PIDFILE <- file.path(LOCK_DIR, "pid")

# ── Single-instance lock (mandatory) ────────────────────────────────────────────
# NOTE(paper): 2026-07-14 incident — a re-invocation of this script launched a
#              second (then third) concurrent instance, all appending to the
#              SAME OUT_PARQUET via read-existing -> rbind -> write-whole-file,
#              which is not safe for concurrent writers: two instances can both
#              read the file in the same state, both append the same batch, and
#              double every row (observed: 50 dates -> 474,200 rows instead of
#              237,150, i.e. every (cell_id,date) duplicated exactly once).
# NOTE(limitation): a FIRST fix using `file.exists(lockfile)` then
#              `writeLines(pid, lockfile)` was itself racy — two instances
#              launched within the same ~second (observed again in this same
#              incident: two more concurrent starts, seconds apart) can both
#              pass the `file.exists()` check before either has written the
#              file (classic TOCTOU). Fixed properly using `dir.create()` as
#              the atomic primitive: POSIX mkdir() either creates the
#              directory or fails with EEXIST as one atomic syscall, so at
#              most one concurrent process can ever succeed, unlike a
#              check-then-write on a plain file.
lock_acquired <- dir.create(LOCK_DIR, showWarnings = FALSE)
if (!lock_acquired) {
  old_pid <- suppressWarnings(as.integer(readLines(LOCK_PIDFILE, n = 1, warn = FALSE)))
  alive <- FALSE
  if (length(old_pid) == 1 && !is.na(old_pid)) {
    # `kill -0` sends no signal; exit status 0 means the PID exists (portable
    # macOS/Linux liveness check — avoids relying on tools::pskill's less
    # predictable cross-platform "check-only" semantics).
    rc <- suppressWarnings(system2("kill", args = c("-0", old_pid),
                                    stdout = FALSE, stderr = FALSE))
    alive <- identical(rc, 0L)
  }
  if (isTRUE(alive)) {
    stop(sprintf(
      "[A4b] LOCK HELD by live PID %d (%s). Another instance of this script is already running. Exiting rather than racing on %s.",
      old_pid, LOCK_DIR, OUT_PARQUET
    ))
  }
  message("[A4b] Stale lock dir found (PID ", old_pid, " not running) — removing and retrying acquisition.")
  unlink(LOCK_DIR, recursive = TRUE)
  lock_acquired <- dir.create(LOCK_DIR, showWarnings = FALSE)
  if (!lock_acquired) {
    stop("[A4b] Could not acquire lock even after clearing a stale one — ",
         "another process won the race. Exiting rather than risk a duplicate run.")
  }
}
writeLines(as.character(Sys.getpid()), LOCK_PIDFILE)
message("[A4b] Lock acquired: ", LOCK_DIR, " (PID ", Sys.getpid(), ")")
# Always release the lock on exit, including on error/interrupt.
reg.finalizer(environment(), function(e) {
  if (dir.exists(LOCK_DIR)) unlink(LOCK_DIR, recursive = TRUE)
}, onexit = TRUE)

# NOTE(cite): Authoritative MODIS-Aqua band-averaged extraterrestrial solar
#             irradiance (F0), from NASA OBPG "Spectral Bandpass Integration"
#             table (Thuillier reference solar spectrum convolved with the
#             MODIS-Aqua relative spectral response function):
#             https://oceancolor.gsfc.nasa.gov/resources/docs/rsr_tables/
#             -> sensor "MODIS-AQUA" -> https://oceancolor.gsfc.nasa.gov/images/rsr/modis-aqua_bandpass.csv
#             (fetched 2026-07-14). Table row "667 nm" (MODIS-Aqua Band 13,
#             Amin 2009 Fig.1 caption p.9134): Solar Irradiance = 1522.491 W/m^2/um.
#             Table row "678 nm" (Band 14): Solar Irradiance = 1480.511 W/m^2/um.
#             Units confirmed W m^-2 um^-1 (NOT per-steradian) per OB.DAAC's own
#             correction on the Earthdata Forum (forum.earthdata.nasa.gov/viewtopic.php?t=3528,
#             Sean Bailey, OB.DAAC): "F0: W/m^2/um; nLw: W/m^2/um/sr". Cross-checked
#             against the widely-published approximate values (~1521, ~1485
#             W m^-2 um^-1) cited in reports/bio_optical_spec.md — matches to <0.1%.
F0_667 <- 1522.491   # W m^-2 um^-1, MODIS-Aqua Band 13 (667 nm)
F0_678 <- 1480.511   # W m^-2 um^-1, MODIS-Aqua Band 14 (678 nm)

# NOTE(paper): MANDATORY UNIT SANITY CHECK (performed once, 2026-07-14, before
#              committing the full run) — computed RBD from real Rrs_667/Rrs_678
#              L3m pixels over the full study bbox for 2018-08-15 (peak of the
#              2018 SW Florida red tide). Result: RBD range -0.197 to +0.330,
#              median 0.021, 90th pct 0.097, 95th pct 0.143, 99th pct 0.224;
#              4.5% of valid pixels (151/3360) exceeded the 0.15 detection
#              threshold. This lands squarely on the "tenths" scale the Amin
#              (2009) threshold (0.15) is defined on -- NOT ~0.015 (10x too
#              small, F0 unit wrong) and NOT ~1.5 (10x too large). PASS.
#              Logged in full in reports/agent_logs/sat-features.md.

# Bio-optical MODIS-Aqua L3m daily products: (product_code, variable_name, nc_varname)
# NOTE(cite): confirmed via live download + terra::rast() variable-name inspection
#             on 2026-07-14 (AQUA_MODIS.20180815, all 4 products): file variable
#             names are exactly Rrs_667 / Rrs_678 / bbp_443 / bbp_s (single-layer
#             files; no qual/ancillary layers to disambiguate, unlike SST in R/04).
PRODUCTS <- list(
  list(prod = "RRS", var = "Rrs_667", nc_var = "Rrs_667"),
  list(prod = "RRS", var = "Rrs_678", nc_var = "Rrs_678"),
  list(prod = "IOP", var = "bbp_443", nc_var = "bbp_443"),
  list(prod = "IOP", var = "bbp_s",   nc_var = "bbp_s")
)

# ── Helper: build file URL for a given date and product ────────────────────────
obdaac_url <- function(date_val, prod) {
  ds <- format(date_val, "%Y%m%d")
  paste0(OBDAAC_GET, "AQUA_MODIS.", ds, ".L3m.DAY.", prod$prod, ".", prod$var, ".4km.nc")
}

# ── Helper: authenticated download via system curl ─────────────────────────────
# Returns TRUE on success, FALSE on failure (network/auth/missing date).
# NOTE(limitation): shells out to the system `curl` binary rather than using R's
#   `curl` package — see the NOTE(limitation) at the Packages section above for
#   why (R curl package: no preemptive Basic auth without a non-default flag,
#   AND fails outright under the sandboxed Bash tool's proxy). System `curl -n`
#   (netrc auth) + `-b/-c` cookiejar (for the URS OAuth redirect-and-back) is
#   the exact invocation verified working, both sandboxed and unsandboxed,
#   against this same NASA Earthdata endpoint on 2026-07-14.
download_modis <- function(url, destfile, cookie_file = COOKIE_FILE,
                           netrc_file = path.expand("~/.netrc"),
                           timeout = 300) {
  args <- c(
    "-n", "--netrc-file", netrc_file,
    "-b", cookie_file, "-c", cookie_file,
    "-L", "-s",
    "--max-time", as.character(timeout),
    "--speed-limit", "1024", "--speed-time", "60",
    "-o", destfile,
    url
  )
  rc <- tryCatch(
    system2("curl", args = args, stdout = FALSE, stderr = FALSE),
    error = function(e) 1L
  )
  if (!identical(rc, 0L)) {
    unlink(destfile)
    return(FALSE)
  }
  sz <- file.size(destfile)
  if (is.na(sz) || sz < 10000L) {   # too small -> likely auth/error page
    unlink(destfile)
    return(FALSE)
  }
  TRUE
}

# ── Helper: aggregate one raster product to 10km grid ──────────────────────────
# Returns data.table with cell_id, <var>_mean, <var>_n_valid; or NULL on failure.
aggregate_to_grid <- function(nc_file, prod, grid_vect, bbox, crs_proj) {
  r <- tryCatch(rast(nc_file), error = function(e) NULL)
  if (is.null(r)) return(NULL)

  if (nlyr(r) > 1) {
    idx <- which(names(r) == prod$nc_var)
    if (length(idx) == 0L) idx <- 1L
    r <- r[[idx[1]]]
  }

  r_crop <- crop(r, bbox)
  names(r_crop) <- prod$var

  # NOTE(paper): bilinear reproject, matching R/04 — all bio-optical variables
  #              (Rrs, bbp) are continuous, not categorical.
  r_proj <- project(r_crop, crs_proj, method = "bilinear")

  zone_r <- rasterize(grid_vect, r_proj, field = "cell_id")

  z_mean <- as.data.table(zonal(r_proj, zone_r, fun = "mean", na.rm = TRUE))
  setnames(z_mean, c("cell_id", paste0(prod$var, "_mean")))

  valid_r <- r_proj
  vals <- values(valid_r)
  values(valid_r) <- as.integer(!is.na(vals))
  z_count <- as.data.table(zonal(valid_r, zone_r, fun = "sum", na.rm = TRUE))
  setnames(z_count, c("cell_id", paste0(prod$var, "_n_valid")))

  merge(z_mean, z_count, by = "cell_id")
}

# ── Load grid ──────────────────────────────────────────────────────────────────
message("[A4b] Loading study area grid from ", GRID_PATH)
grid_sf   <- st_read(GRID_PATH, quiet = TRUE)
grid_vect <- vect(grid_sf)
message("[A4b] Grid: ", nrow(grid_sf), " cells, CRS ", st_crs(grid_sf)$epsg)

# ── Get the EXACT date set from the existing satellite cube (read-only) ────────
# NOTE(paper): pulling the SAME date set as satellite_features.parquet keeps the
#              eventual A6 join 1:1 with the existing cube (per lead's directive
#              and reports/bio_optical_spec.md Sec.4). This IS the project's
#              "full satellite era" for the bio-optical pass, done in one pass.
message("[A4b] Reading date set + chlor_a from ", SAT_PARQUET, " (read-only)")
sat_ref <- as.data.table(read_parquet(SAT_PARQUET,
                                       col_select = c("cell_id", "date", "chlor_a_mean")))
all_dates <- sort(unique(sat_ref$date))
message("[A4b] Target date set: ", length(all_dates), " unique dates (",
        format(min(all_dates)), " to ", format(max(all_dates)), ")")
setkey(sat_ref, cell_id, date)

# ── Checkpoint: skip already-processed dates ────────────────────────────────────
done_dates <- as.Date(character(0))
if (file.exists(OUT_PARQUET)) {
  existing <- as.data.table(read_parquet(OUT_PARQUET, col_select = c("date")))
  if (nrow(existing) > 0) {
    done_dates <- sort(unique(existing$date))
    message("[A4b] Checkpoint: ", length(done_dates), " dates already in output; skipping.")
  }
  rm(existing)
  gc()
}

process_dates <- setdiff(as.character(all_dates), as.character(done_dates))
process_dates <- as.Date(process_dates)
message("[A4b] Dates to process: ", length(process_dates))

if (length(process_dates) == 0) {
  message("[A4b] All dates already processed. Output exists at ", OUT_PARQUET)
  unlink(LOCK_DIR, recursive = TRUE)   # explicit release (reg.finalizer onexit is the backstop)
  quit(save = "no", status = 0)
}

# ── Main stream-and-discard loop ───────────────────────────────────────────────
# Per day: download 4 global files -> clip -> aggregate -> compute features ->
# append rows -> unlink(). Peak disk: ~4 files x ~5-13 MB = ~30-50 MB at a time.

accumulated  <- list()
FLUSH_EVERY  <- 50L
n_ok  <- 0L
n_err <- 0L
TOTAL <- length(process_dates)
peak_disk_bytes <- 0

for (i in seq_along(process_dates)) {
  d  <- process_dates[i]
  ds <- format(d, "%Y%m%d")

  if (i %% 10 == 0 || i == 1) {
    message(sprintf("[A4b] Progress: %d/%d  date=%s  ok=%d  err=%d",
                    i, TOTAL, d, n_ok, n_err))
  }

  prod_results <- list()
  day_disk_bytes <- 0

  for (prod in PRODUCTS) {
    url  <- obdaac_url(d, prod)
    dest <- file.path(RAW_DIR, paste0("tmp_bio_", ds, "_", prod$prod, "_", prod$var, ".nc"))

    ok <- download_modis(url, dest)
    if (!ok) {
      # NOTE(limitation): missing file = no MODIS pass / no retrieval for this
      #   date+product (instrument downtime, transmission gap, 100% cloud cover).
      next
    }

    day_disk_bytes <- day_disk_bytes + file.size(dest)
    agg <- aggregate_to_grid(dest, prod, grid_vect, BBOX_WGS84, CRS_PROJ)

    # STREAM-AND-DISCARD: delete raw file immediately after processing.
    unlink(dest)

    if (!is.null(agg)) prod_results[[prod$var]] <- agg
  }

  peak_disk_bytes <- max(peak_disk_bytes, day_disk_bytes)

  if (length(prod_results) == 0) {
    n_err <- n_err + 1L
    next
  }

  day_dt <- Reduce(function(a, b) merge(a, b, by = "cell_id", all = TRUE), prod_results)
  day_dt[, date := d]

  # Ensure all expected columns present even if a product failed that day
  for (prod in PRODUCTS) {
    mc <- paste0(prod$var, "_mean");    if (!mc %in% names(day_dt)) day_dt[, (mc) := NA_real_]
    nc <- paste0(prod$var, "_n_valid"); if (!nc %in% names(day_dt)) day_dt[, (nc) := 0L]
  }

  # ── nLw conversion + RBD/KBBI (Amin 2009 Eq.19/20) ──────────────────────────
  # NOTE(paper): nLw(lambda) = Rrs(lambda) x F0(lambda) (Amin 2009 Sec.3.1 end,
  #              p.9133). Applying F0 to the per-cell zonal MEAN of Rrs is
  #              mathematically identical to averaging pixel-level nLw first
  #              (linear scalar transform) -> no additional approximation.
  day_dt[, nlw_667 := Rrs_667_mean * F0_667]
  day_dt[, nlw_678 := Rrs_678_mean * F0_678]
  # NOTE(cite): RBD = nLw(678) - nLw(667) -- Amin 2009 Eq.19, p.9133.
  day_dt[, rbd  := nlw_678 - nlw_667]
  # NOTE(cite): KBBI = (nLw(678)-nLw(667)) / (nLw(678)+nLw(667)) -- Eq.20, p.9134.
  day_dt[, kbbi := rbd / (nlw_678 + nlw_667)]
  # NOTE(cite): thresholds -- Amin 2009 Abstract p.9126 / Sec.4.1 p.9135.
  day_dt[, rbd_detect   := rbd > 0.15]
  day_dt[, kbbi_kbrevis := (rbd > 0.15) & (kbbi > 0.3 * rbd)]

  # ── Join chlor_a (existing cube, read-only) for the Cannizzaro/Morel score ──
  day_chl <- sat_ref[.(unique(day_dt$cell_id), d), on = c("cell_id", "date"),
                     .(cell_id, chlor_a_mean)]
  day_dt <- merge(day_dt, day_chl, by = "cell_id", all.x = TRUE)
  day_dt[, chl_missing := is.na(chlor_a_mean)]

  # ── bbp(551) power law (Cannizzaro 2008 Eq.14, p.146) ───────────────────────
  # NOTE(cite): bbp(551) = bbp_443 * (443/551)^bbp_s ; 551 nm treated as the
  #             MODIS green band == Cannizzaro's "bbp(550)" (spec Sec.3).
  day_dt[, bbp_551 := bbp_443_mean * (443/551)^bbp_s_mean]

  # ── Morel (1988) Case-1 bbp(550) reference curve ────────────────────────────
  # NOTE(cite): bbp_Morel(550;C) = 0.30*C^0.62 * [0.002 + 0.02*(0.5-0.25*log10 C)]
  #             -- Morel 1988 p.10760 (byte-identical to Amin 2009 Eq.16).
  # NOTE(limitation): valid range ~0.03-30 mg/m^3 chlorophyll (Morel 1988 Eq.18,
  #             r^2=0.90, n=506); Chl <= 0 -> log10 undefined -> NA (not clipped).
  chl <- day_dt$chlor_a_mean
  day_dt[, bbp_morel_550 := ifelse(!is.na(chl) & chl > 0,
                                    0.30 * chl^0.62 * (0.002 + 0.02*(0.5 - 0.25*log10(chl))),
                                    NA_real_)]

  # ── Discrimination scores (Cannizzaro 2008 Sec.6.1, p.150, Fig.9C) ──────────
  day_dt[, bbp_ratio_morel := bbp_551 / bbp_morel_550]
  day_dt[, bbp_deficit     := bbp_morel_550 - bbp_551]
  # NOTE(cite): classification rule -- Chl>1.5 mg/m^3 AND bbp(550)<bbp_Morel(550)
  #             -- Cannizzaro 2008 Sec.6.1 p.150, verbatim.
  day_dt[, cannizzaro_kbrevis := (chlor_a_mean > 1.5) & (bbp_551 < bbp_morel_550)]

  # ── Quality / missingness flags (R/04 convention: never zero-fill) ──────────
  n_cols_present <- intersect(paste0(c("Rrs_667","Rrs_678","bbp_443","bbp_s"), "_n_valid"),
                               names(day_dt))
  day_dt[, bio_cloud_flag := rowSums(.SD, na.rm = TRUE) == 0, .SDcols = n_cols_present]
  day_dt[, bio_feature_filled := FALSE]   # A6 sets TRUE if it gap-fills downstream
  day_dt[, IS_PLACEHOLDER := FALSE]

  accumulated[[length(accumulated) + 1]] <- day_dt
  n_ok <- n_ok + 1L

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
    message(sprintf("[A4b] Flushed to %s  (dates processed so far: %d)", OUT_PARQUET, n_ok))
  }
}

# ── Summary ────────────────────────────────────────────────────────────────────
message("")
message("=== A4b bio-optical run complete ===")
message("Dates processed (ok):  ", n_ok)
message("Dates skipped (error): ", n_err)
message("Peak disk this run:    ", round(peak_disk_bytes / 1024^2, 1), " MB (per-day, 4 files)")
message("Output: ", OUT_PARQUET)

if (file.exists(OUT_PARQUET)) {
  final <- as.data.table(read_parquet(OUT_PARQUET))
  message("Output rows:            ", nrow(final))
  message("Output dates:           ", length(unique(final$date)))
  message("Date range:             ", format(min(final$date)), " to ", format(max(final$date)))
  message("rbd_detect TRUE rows:   ", sum(final$rbd_detect, na.rm = TRUE))
  message("kbbi_kbrevis TRUE rows: ", sum(final$kbbi_kbrevis, na.rm = TRUE))
  message("cannizzaro_kbrevis TRUE rows: ", sum(final$cannizzaro_kbrevis, na.rm = TRUE))
  message("chl_missing rows:       ", sum(final$chl_missing, na.rm = TRUE))
  message("bio_cloud_flag rows:    ", sum(final$bio_cloud_flag, na.rm = TRUE))
  message("IS_PLACEHOLDER rows:    ", sum(final$IS_PLACEHOLDER, na.rm = TRUE))
  message("Schema: ", paste(names(final), collapse = ", "))
  rm(final)
}

unlink(LOCK_DIR, recursive = TRUE)   # explicit release (reg.finalizer onexit is the backstop)
message("[A4b] Done. Script is resumable — re-run to process remaining dates.")
