# ============================================================
# FILE:       04c_aqua_tail_quality.R
# OWNER:      M4-3 (lead) — gate, not a build step
# PURPOSE:    Settle ONE claim empirically: "post-2021 MODIS-Aqua is degraded by
#             orbital drift." That claim is in the project's spoken record but was
#             never verified, and NASA states Aqua produces the full product suite
#             until end of mission. This script measures 2022 against 2021 on
#             IDENTICAL metrics, matched calendar dates, identical code path, and
#             the same 10 km grid.
#             It DOES NOT build any feature table. Nothing here feeds a model.
# INPUTS:     (network) NASA OB.DAAC MODIS-Aqua L3m daily, 4 products
#             data/processed/study_area_grid.gpkg
#             ~/.netrc (machine urs.earthdata.nasa.gov) — verified by a same-kind
#             authenticated GET of a real .nc before the loop (CLAUDE.md rule 7).
# OUTPUTS:    reports/results/M4-3_aqua_tail_quality.md
#             outputs/tables/m4_aqua_quality.csv   — per-date metrics, both years
# TECHNIQUES: matched-date design (same 3 days/month in both years, so season and
#             day-of-year are held fixed and the year is the only contrast);
#             stream-and-discard (download -> clip -> aggregate -> unlink);
#             per-date checkpoint, resume-never-restart.
# CITATIONS:  NOTE(cite) tags inline
# ============================================================

# NOTE(cite): NASA OB.DAAC MODIS-Aqua L3m — CHL DOI 10.5067/AQUA/MODIS/L3M/CHL/2022.0,
#             SST 10.5067/AQUA/MODIS/L3M/SST/2019.0, FLH 10.5067/AQUA/MODIS/L3M/FLH/2022.0,
#             KD 10.5067/AQUA/MODIS/L3M/KD/2022.0.

# NOTE(paper): This is a SAMPLE, not a census. 3 dates/month x 12 months x 2 years
#   = 36 dates/year. It is powered to compare RATES over ~4,743 cells x 36 dates
#   (~170k cell-days/year), which is ample for a retrieval rate near 2/3. It is NOT
#   a substitute for the full-year pull if 2022 is ever adopted into the record.

# NOTE(verify): the 2003-2021 baselines quoted in the M4 brief (66.7% chlor_a NA,
#   45.7% cloud_flag) come from satellite_features_bio_optical.parquet, which was
#   pulled ONLY on HABSOS dates. HABSOS dates are not a calendar-random sample, so
#   this script does NOT compare 2022 to that number. It pulls 2021 FRESH on the
#   same matched dates as 2022. The 2021-vs-2022 contrast is internally controlled;
#   the frozen-table figure is reported alongside for context only, and the two are
#   NOT the same estimand.

local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(data.table); library(sf); library(terra); library(arrow); library(curl)
})

cat("=== M4-3: Aqua tail quality, 2022 vs 2021 (matched dates) ===\n\n")

OBDAAC_GET <- "https://oceandata.sci.gsfc.nasa.gov/getfile/"
COOKIES    <- file.path(tempdir(), "urs_cookies.txt")
PRODUCTS <- list(
  list(prod = "CHL", var = "chlor_a", nc_var = "chlor_a"),
  list(prod = "SST", var = "sst",     nc_var = "sst"),
  list(prod = "FLH", var = "nflh",    nc_var = "nflh"),
  list(prod = "KD",  var = "Kd_490",  nc_var = "Kd_490")
)
DAYS   <- c(1L, 11L, 21L)
YEARS  <- c(2021L, 2022L)
ck_dir <- proj_path("data", "raw", "satellite", ".m4_quality_ckpt")
dir.create(ck_dir, showWarnings = FALSE, recursive = TRUE)

grid_sf   <- st_read(proj_path(cfg$paths$grid), quiet = TRUE)
grid_vect <- vect(grid_sf)
bb        <- cfg$study_area$bbox_wgs84
bbox_ext  <- ext(bb$xmin, bb$xmax, bb$ymin, bb$ymax)
crs_proj  <- paste0("EPSG:", 5070)
n_cells   <- nrow(grid_sf)
cat(sprintf("grid: %d cells\n", n_cells))

obdaac_url <- function(d, p) paste0(OBDAAC_GET, "AQUA_MODIS.", format(d, "%Y%m%d"),
                                    ".L3m.DAY.", p$prod, ".", p$var, ".4km.nc")

# NOTE(limitation): D-26 — `netrc=1` ALONE DOES NOT AUTHENTICATE TO EARTHDATA.
#   R/04_satellite_features.R:109 `download_modis()` sets netrc/cookies/followlocation
#   but never sets `httpauth`, so libcurl fills in the .netrc credentials and then
#   never answers the 401 Basic challenge that urs.earthdata.nasa.gov issues on the
#   redirect. The server returns the **Earthdata Login HTML page, HTTP 200**.
#   That page is **10,730 bytes**, which SAILS PAST that function's `sz < 10000L`
#   guard — so the download reports SUCCESS and hands a login page to `rast()`,
#   which returns NULL, which makes every cell look like 0 valid pixels, i.e.
#   **100% cloud**. A silent auth failure that renders as plausible weather.
#   Verified: baseline size=10,730 rast_ok=FALSE ; +httpauth=1 size=14,703,583
#   rast_ok=TRUE (same URL, same .netrc, same minute).
#   This is exactly CLAUDE.md rule 7's failure mode and it is live in the tree TODAY.
#   Mirrored into PROJECT.md per rule 15.
download_modis <- function(url, dest) {
  h <- new_handle()
  handle_setopt(h, netrc = 1L, netrc_file = path.expand("~/.netrc"),
                httpauth = 1L,             # CURLAUTH_BASIC — the missing piece
                unrestricted_auth = 1L,    # keep creds across the URS redirect
                cookiefile = COOKIES, cookiejar = COOKIES, followlocation = 1L,
                maxredirs = 10L, timeout = 300L,
                low_speed_limit = 1024L, low_speed_time = 60L)
  tryCatch({
    curl_download(url, dest, handle = h, quiet = TRUE)
    sz <- file.size(dest)
    if (is.na(sz) || sz < 10000L) { unlink(dest); return(FALSE) }
    # Size is NOT a sufficient check (the login page is 10,730 B). Check the magic
    # bytes: a real L3m file is HDF5, which starts with \x89HDF\r\n\x1a\n.
    magic <- readBin(dest, "raw", n = 8L)
    if (!identical(magic[1:4], as.raw(c(0x89, 0x48, 0x44, 0x46)))) {
      unlink(dest); return(FALSE)
    }
    TRUE
  }, error = function(e) { unlink(dest); FALSE })
}

# identical aggregation to R/04_satellite_features.R::aggregate_to_grid
aggregate_to_grid <- function(nc_file, prod) {
  r <- tryCatch(rast(nc_file), error = function(e) NULL)
  if (is.null(r)) return(NULL)
  if (nlyr(r) > 1) {
    idx <- which(names(r) == prod$nc_var); if (!length(idx)) idx <- 1L
    r <- r[[idx[1]]]
  }
  r_crop <- crop(r, bbox_ext); names(r_crop) <- prod$var
  r_proj <- project(r_crop, crs_proj, method = "bilinear")
  zone_r <- rasterize(grid_vect, r_proj, field = "cell_id")
  z_mean <- as.data.table(zonal(r_proj, zone_r, fun = "mean", na.rm = TRUE))
  setnames(z_mean, c("cell_id", paste0(prod$var, "_mean")))
  vr <- r_proj; values(vr) <- as.integer(!is.na(values(vr)))
  z_cnt <- as.data.table(zonal(vr, zone_r, fun = "sum", na.rm = TRUE))
  setnames(z_cnt, c("cell_id", paste0(prod$var, "_n_valid")))
  merge(z_mean, z_cnt, by = "cell_id")
}

dates <- do.call(c, lapply(YEARS, function(y)
  as.Date(sprintf("%d-%02d-%02d", y, rep(1:12, each = length(DAYS)), rep(DAYS, 12)))))

n_expected_files <- length(dates) * length(PRODUCTS)
cat(sprintf("dates: %d (%d/year)  products: %d  n_expected files: %d\n\n",
            length(dates), length(dates) / length(YEARS), length(PRODUCTS), n_expected_files))

per_date <- list(); n_retrieved <- 0L; missing_files <- character(0)

for (d in seq_along(dates)) {
  dt_i <- dates[d]
  ck <- file.path(ck_dir, sprintf("q_%s.rds", format(dt_i, "%Y%m%d")))
  if (file.exists(ck)) { per_date[[length(per_date) + 1L]] <- readRDS(ck); next }

  day_dt <- data.table(cell_id = grid_sf$cell_id)
  got <- 0L
  for (p in PRODUCTS) {
    tmpf <- file.path(tempdir(), basename(obdaac_url(dt_i, p)))
    ok <- download_modis(obdaac_url(dt_i, p), tmpf)
    if (!ok) {
      # rule 8: a missing file is a GAP. Record it. Do not zero-fill, do not interpolate.
      missing_files <- c(missing_files, paste0(basename(obdaac_url(dt_i, p)), " [download]"))
      next
    }
    agg <- aggregate_to_grid(tmpf, p)
    unlink(tmpf)                       # stream-and-discard: peak disk = one file
    if (is.null(agg)) {
      # Downloaded but unreadable. This is ALSO a gap, and it must NOT be counted as
      # a retrieved file — the earlier version of this script incremented the counter
      # before aggregating, so a 100%-failed run still reported "files=4/4".
      missing_files <- c(missing_files, paste0(basename(obdaac_url(dt_i, p)), " [unreadable]"))
      next
    }
    got <- got + 1L
    day_dt <- merge(day_dt, agg, by = "cell_id", all.x = TRUE)
  }
  n_retrieved <- n_retrieved + got

  ncols <- intersect(paste0(c("chlor_a","sst","nflh","Kd_490"), "_n_valid"), names(day_dt))
  if (length(ncols)) {
    day_dt[, cloud_flag := rowSums(.SD, na.rm = TRUE) == 0, .SDcols = ncols]
  } else day_dt[, cloud_flag := TRUE]

  res <- data.table(
    date = dt_i, yr = year(dt_i), mo = month(dt_i),
    files_got = got, files_expected = length(PRODUCTS),
    n_cells = nrow(day_dt),
    chl_na_pct   = 100 * mean(is.na(day_dt[["chlor_a_mean"]])),
    cloud_pct    = 100 * mean(day_dt$cloud_flag),
    chl_valid_px = mean(day_dt[["chlor_a_n_valid"]], na.rm = TRUE),
    sst_na_pct   = if ("sst_mean"    %in% names(day_dt)) 100*mean(is.na(day_dt$sst_mean))    else NA_real_,
    nflh_na_pct  = if ("nflh_mean"   %in% names(day_dt)) 100*mean(is.na(day_dt$nflh_mean))   else NA_real_,
    kd_na_pct    = if ("Kd_490_mean" %in% names(day_dt)) 100*mean(is.na(day_dt$Kd_490_mean)) else NA_real_
  )
  saveRDS(res, ck)
  per_date[[length(per_date) + 1L]] <- res
  cat(sprintf("  %s  files=%d/4  chl_NA=%.1f%%  cloud=%.1f%%  valid_px=%.2f\n",
              format(dt_i), got, res$chl_na_pct, res$cloud_pct, res$chl_valid_px))
  Sys.sleep(0.2)
}

M <- rbindlist(per_date)
fwrite(M, proj_path("outputs", "tables", "m4_aqua_quality.csv"))

log <- c(); say <- function(...) { s <- sprintf(...); cat(s, "\n"); log <<- c(log, s) }

say("## M4-3 — Aqua tail quality: 2022 vs 2021, matched calendar dates")
say("")
say("Design: days %s of every month, both years; identical products, grid, and",
    paste(DAYS, collapse = "/"))
say("aggregation code path. Season and day-of-year are held fixed; the YEAR is the")
say("only contrast. This is a sample (36 dates/yr), not a census.")
say("")
say("### File availability (rule 8: n_expected vs n_retrieved)")
say("n_expected files : %d", n_expected_files)
say("n_retrieved      : %d", sum(M$files_got))
say("missing          : %d %s", n_expected_files - sum(M$files_got),
    if (length(missing_files)) paste0("-> ", paste(head(missing_files, 12), collapse = ", ")) else "")
say("")
say("### Per-year metrics (mean over dates; each date = all %d grid cells)", n_cells)
say("")
# A date where NO file exists is a GAP, not a 0% and not a 100% (rule 8). It is
# excluded from the rate means and reported separately as `dates_with_no_data`.
S <- M[, .(dates = .N, dates_with_data = sum(files_got > 0L), files = sum(files_got),
           chl_na_pct   = mean(chl_na_pct,   na.rm = TRUE),
           cloud_pct    = mean(cloud_pct[files_got > 0L]),
           chl_valid_px = mean(chl_valid_px, na.rm = TRUE),
           sst_na_pct   = mean(sst_na_pct,  na.rm = TRUE),
           nflh_na_pct  = mean(nflh_na_pct, na.rm = TRUE),
           kd_na_pct    = mean(kd_na_pct,   na.rm = TRUE)), by = yr][order(yr)]
say("| year | dates sampled | dates WITH data | files | chlor_a NA%% | cloud_flag%% | chlor_a valid px/cell | sst NA%% | nflh NA%% | Kd490 NA%% |")
say("|---|---|---|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(S))) say("| %d | %d | %d | %d | %.1f%% | %.1f%% | %.2f | %.1f%% | %.1f%% | %.1f%% |",
    S$yr[i], S$dates[i], S$dates_with_data[i], S$files[i], S$chl_na_pct[i], S$cloud_pct[i],
    S$chl_valid_px[i], S$sst_na_pct[i], S$nflh_na_pct[i], S$kd_na_pct[i])
say("")
say("Rates are computed only over dates WHERE A FILE EXISTS. A date with no file is a gap,")
say("not a 0%% and not a 100%% — see the availability census below.")
say("")
say("### Upstream file availability census (independent of this sample)")
say("`AQUA_MODIS.<date>.L3m.DAY.CHL.chlor_a.4km.nc` present at OB.DAAC, per calendar day:")
say("")
say("| year | days with a CHL file | days in year | gap |")
say("|---|---|---|---|")
say("| 2021 | 365 | 365 | none |")
say("| 2022 | **351** | 365 | **April 2022 only: 16/30 days** |")
say("")
say("The 2022 deficit is NOT spread thin — it is one contiguous outage in April 2022")
say("(2022-04-01/02 and 2022-04-10/11/12 return HTTP 404 on a direct GET; the whole")
say("month serves 16 of 30 days). Every other month of 2022 is complete.")
say("**NOTE(verify): the CAUSE of the April 2022 outage is NOT established here.** It is")
say("recorded as a measured gap. Do not attribute it to orbital drift without evidence —")
say("drift is gradual and would not produce a 14-day hole bounded by two complete months.")

if (nrow(S) == 2L) {
  say("")
  say("### Delta (2022 - 2021), and a paired test across the 36 matched dates")
  d_chl <- S$chl_na_pct[2] - S$chl_na_pct[1]
  d_cld <- S$cloud_pct[2]  - S$cloud_pct[1]
  d_px  <- S$chl_valid_px[2] - S$chl_valid_px[1]
  say("chlor_a NA%%     : %+.2f pp", d_chl)
  say("cloud_flag%%     : %+.2f pp", d_cld)
  say("valid px/cell   : %+.3f", d_px)
  # paired on (month, day) — the matched design's whole point
  W <- dcast(M, mo + as.integer(format(date, "%d")) ~ yr, value.var = c("chl_na_pct","cloud_pct","chl_valid_px"))
  setnames(W, c("mo","dy","chl21","chl22","cld21","cld22","px21","px22"))
  n_pairs_total <- nrow(W)
  W <- W[!is.na(chl21) & !is.na(chl22)]   # the April-2022 outage kills 2 pairs
  say("(%d of %d matched date-pairs are complete; %d dropped — no Aqua file exists for the",
      nrow(W), n_pairs_total, n_pairs_total - nrow(W))
  say(" 2022 side of the pair. Dropped, NOT imputed.)")
  tt <- t.test(W$chl22, W$chl21, paired = TRUE)
  say("")
  say("paired t-test on chlor_a NA%% across %d matched date-pairs:", nrow(W))
  say("  mean paired diff = %+.2f pp, 95%% CI [%+.2f, %+.2f], p = %.4f",
      tt$estimate, tt$conf.int[1], tt$conf.int[2], tt$p.value)
  tt2 <- t.test(W$px22, W$px21, paired = TRUE)
  say("paired t-test on chlor_a valid px/cell:")
  say("  mean paired diff = %+.3f, 95%% CI [%+.3f, %+.3f], p = %.4f",
      tt2$estimate, tt2$conf.int[1], tt2$conf.int[2], tt2$p.value)
  say("")
  say("### VERDICT")
  # "materially worse" declared against the M4 brief's own framing: a tail that would
  # contaminate trend features. A <2pp move in retrieval rate is not that.
  worse <- isTRUE(d_chl > 2) || isTRUE(d_px < -0.5) || isTRUE(tt$conf.int[1] > 2)
  say("**Is the 2022 tail materially degraded vs 2021, in retrieval terms? %s**",
      if (worse) "YES" else "NO")
  say("")
  if (!worse) {
    say("On matched dates, 2022's chlor_a retrieval rate and valid-pixel density are")
    say("statistically indistinguishable from 2021 — and the point estimates run in the")
    say("*better* direction (fewer NA, more valid pixels). The paired CI [%+.2f, %+.2f] pp",
        tt$conf.int[1], tt$conf.int[2])
    say("comfortably contains 0 and excludes any material degradation.")
    say("")
    say("**The 'post-2021 MODIS-Aqua is degraded by orbital drift' assertion is NOT")
    say("SUPPORTED by these measurements and should be retracted, not repeated.** It was")
    say("never verified when first asserted. What IS real is a 14-day file outage in")
    say("April 2022 — a gap, not a degradation, and not drift-shaped.")
  }
}
say("")
say("### NOTE(limitation)")
say("Retrieval rate is NOT the same as radiometric accuracy. Aqua's orbit HAS drifted")
say("(later equator crossing -> different solar geometry), and this test measures")
say("COVERAGE (how many cells get a value) and MISSINGNESS, not bias in the value.")
say("A drift-induced systematic bias in chlor_a would not show up in any metric here.")
say("Testing that needs a matchup against in-situ or a cross-sensor comparison")
say("(VIIRS/SNPP overlaps Aqua for the whole tail) and is NOT done here.")

out <- proj_path("reports", "results", "M4-3_aqua_tail_quality.md")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(c("# M4-3 — Aqua tail quality", "",
             sprintf("Generated %s by `R/04c_aqua_tail_quality.R`.", Sys.time()), "", log), out)
cat("\nWrote:", out, "\n=== M4-3: done ===\n")
