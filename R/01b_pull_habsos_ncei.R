# ============================================================
# FILE:       01b_pull_habsos_ncei.R
# OWNER:      M4-1 (lead)
# PURPOSE:    Pull the LIVE NCEI HABSOS Karenia brevis cell-count record from the
#             NCEI ArcGIS REST service, replacing the stale GBIF/OBIS IPT DwC-A
#             mirror (v1.5, published 2022-09-30, ends 2022-01-11).
#             This script ACQUIRES ONLY. It does not label, filter, or aggregate;
#             03_habsos_labels.R owns that.
# INPUTS:     (network) https://gis.ncdc.noaa.gov/arcgis/rest/services/ms/
#                       HABSOS_CellCounts/MapServer/0/query
#             No authentication required (open service, verified by a same-kind
#             paginated GET returning 2,000 attribute rows — CLAUDE.md rule 7).
# OUTPUTS:    data/raw/habsos/ncei/habsos_ncei_raw.parquet   — all attributes, all dates
#             data/raw/habsos/ncei/pull_manifest.csv         — page-level provenance
#             data/raw/habsos/ncei/.checkpoint/page_*.rds    — resumable page cache
# TECHNIQUES: ArcGIS REST paginated query (resultOffset/resultRecordCount,
#             orderByFields=OBJECTID ASC for a stable page window);
#             serial access with exponential backoff (PLAN.md §12 carve-out — the
#             CHIRPS CrowdSec ban was caused by a parallel burst, so this endpoint
#             gets one request at a time);
#             checkpoint-by-page, resume-never-restart (CLAUDE.md, long pulls).
# CITATIONS:  NOTE(cite) tags inline
# ============================================================

# NOTE(cite): HABSOS — NOAA National Centers for Environmental Information (NCEI),
#             Harmful Algal BloomS Observing System. Live ArcGIS MapServer
#             "ms/HABSOS_CellCounts". Public domain / CC0. A-DOC must add a row to
#             data/metadata/data_sources.md with the mandated schema.

# NOTE(limitation): This service carries GENUS='Karenia', SPECIES='brevis' ONLY
#   (verified: returnDistinctValues on both fields returns a single value each).
#   It is therefore NOT a general HAB record — it is the K. brevis record. That
#   matches D2/D3 (the label is K. brevis > 100,000 cells/L) and matches the DwC-A
#   mirror, whose scientificName is likewise 'Karenia brevis' on every row. Mirrored
#   into PROJECT.md per rule 15.

# NOTE(verify): SAMPLE_DATE is returned as epoch milliseconds in the service's own
#   time reference. The service reports no timezone in its layer JSON; the DwC-A
#   eventDate strings are Zulu ('...T23:23:00Z'). Sub-day alignment between the two
#   sources is therefore UNVERIFIED. All downstream use is date-only (D4: cell x
#   date), so a sub-day offset can only matter at a midnight boundary; the overlap
#   audit (R/01c) quantifies the residual.

local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(curl)
  library(jsonlite)
})

cat("=== M4-1: pull live NCEI HABSOS ===\n\n")

SERVICE <- paste0("https://gis.ncdc.noaa.gov/arcgis/rest/services/ms/",
                  "HABSOS_CellCounts/MapServer/0/query")
PAGE     <- 2000L    # server caps a page at 2,000 (exceededTransferLimit=TRUE above this)
MAX_TRY  <- 5L
out_dir  <- proj_path(cfg$paths$raw_habsos, "ncei")
ckpt_dir <- file.path(out_dir, ".checkpoint")
dir.create(ckpt_dir, showWarnings = FALSE, recursive = TRUE)

# ---- helper: one GET with exponential backoff ------------------------------
# PLAN.md §12 carve-out: serial + backoff. A 429/403 is NOT retried into a ban.
fetch_url <- function(url, what) {
  for (attempt in seq_len(MAX_TRY)) {
    h <- new_handle(timeout = 180L, useragent = "BloomGuard/1.0 (research; R curl)")
    res <- try(curl_fetch_memory(url, handle = h), silent = TRUE)
    if (!inherits(res, "try-error") && res$status_code == 200L) {
      txt <- rawToChar(res$content); Encoding(txt) <- "UTF-8"
      j <- try(fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
      if (!inherits(j, "try-error")) {
        # An ArcGIS error is HTTP 200 with an {"error":...} body. Rule 8: do not
        # let that become a silent empty page.
        if (!is.null(j$error)) stop(what, ": service error ", j$error$code, " ",
                                    paste(unlist(j$error$message), collapse = "; "))
        return(j)
      }
    }
    code <- if (inherits(res, "try-error")) "conn-fail" else res$status_code
    if (identical(as.character(code), "403") || identical(as.character(code), "429")) {
      stop(what, ": HTTP ", code, " — rate-limited or banned. STOPPING, not retrying ",
           "(CLAUDE.md: a ban is not transient; parallel/aggressive retry is what ",
           "caused the CHIRPS CrowdSec ban).")
    }
    wait <- 2^attempt
    cat(sprintf("   ! %s attempt %d/%d failed (%s) — backoff %ds\n",
                what, attempt, MAX_TRY, code, wait))
    Sys.sleep(wait)
  }
  stop(what, ": failed after ", MAX_TRY, " attempts.")
}

q <- function(params) paste0(SERVICE, "?", paste(names(params), vapply(params, curl_escape, ""),
                                                 sep = "=", collapse = "&"))

# ---- 1. n_expected, straight from the server (rule 8) ----------------------
cnt <- fetch_url(q(list(where = "1=1", returnCountOnly = "true", f = "json")), "count")
n_expected <- as.integer(cnt$count)
cat(sprintf("n_expected (server returnCountOnly): %s\n", format(n_expected, big.mark = ",")))

n_pages <- ceiling(n_expected / PAGE)
cat(sprintf("pages to fetch: %d @ %d/page\n\n", n_pages, PAGE))

# ---- 2. paginated pull, checkpointed --------------------------------------
FIELDS <- c("OBJECTID","DESCRIPTION","LATITUDE","LONGITUDE","STATE_ID","SAMPLE_DATE",
            "SAMPLE_DEPTH","GENUS","SPECIES","CATEGORY","CELLCOUNT","CELLCOUNT_UNIT",
            "CELLCOUNT_QA","SALINITY","SALINITY_UNIT","SALINITY_QA","WATER_TEMP",
            "WATER_TEMP_UNIT","WATER_TEMP_QA","WIND_DIR","WIND_DIR_UNIT","WIND_DIR_QA",
            "WIND_SPEED","WIND_SPEED_UNIT","WIND_SPEED_QA","QA_COMMENT")

flatten_page <- function(j) {
  feats <- j$features
  if (length(feats) == 0L) return(NULL)
  rows <- lapply(feats, function(f) {
    a <- f$attributes
    # NULL -> NA, one scalar per field. Never drop a field, never zero-fill (rule 8).
    as.list(setNames(lapply(FIELDS, function(k) {
      v <- a[[k]]
      if (is.null(v)) NA else v
    }), FIELDS))
  })
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}

manifest <- vector("list", n_pages)
t0 <- Sys.time()
for (i in seq_len(n_pages)) {
  off  <- (i - 1L) * PAGE
  ck   <- file.path(ckpt_dir, sprintf("page_%04d.rds", i))
  if (file.exists(ck)) {
    dt <- readRDS(ck)
    manifest[[i]] <- data.table(page = i, offset = off, n = nrow(dt), source = "checkpoint")
    next
  }
  j <- fetch_url(q(list(where = "1=1", outFields = paste(FIELDS, collapse = ","),
                        returnGeometry = "false", orderByFields = "OBJECTID ASC",
                        resultOffset = off, resultRecordCount = PAGE, f = "json")),
                 sprintf("page %d", i))
  dt <- flatten_page(j)
  if (is.null(dt)) {
    cat(sprintf("   page %d returned 0 rows — recording the gap, not filling it\n", i))
    dt <- data.table()
  }
  saveRDS(dt, ck)
  manifest[[i]] <- data.table(page = i, offset = off, n = nrow(dt), source = "network")
  if (i %% 10L == 0L || i == n_pages) {
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("   page %3d/%3d  rows=%s  elapsed=%.0fs\n", i, n_pages,
                format(sum(vapply(manifest[seq_len(i)], function(m) m$n, 0L)), big.mark=","), el))
  }
  Sys.sleep(0.25)   # serial + polite. This endpoint is not a target.
}

man <- rbindlist(manifest)
all_dt <- rbindlist(lapply(seq_len(n_pages),
                          function(i) readRDS(file.path(ckpt_dir, sprintf("page_%04d.rds", i)))),
                    use.names = TRUE, fill = TRUE)

# ---- 3. type the columns; SAMPLE_DATE epoch-ms -> Date ---------------------
num_cols <- c("LATITUDE","LONGITUDE","SAMPLE_DEPTH","CELLCOUNT","SALINITY",
              "WATER_TEMP","WIND_DIR","WIND_SPEED")
for (cc in num_cols) if (cc %in% names(all_dt)) all_dt[, (cc) := as.numeric(get(cc))]
int_cols <- c("OBJECTID","CELLCOUNT_QA","SALINITY_QA","WATER_TEMP_QA","WIND_DIR_QA","WIND_SPEED_QA")
for (cc in int_cols) if (cc %in% names(all_dt)) all_dt[, (cc) := as.integer(get(cc))]

all_dt[, SAMPLE_DATE_MS := as.numeric(SAMPLE_DATE)]
all_dt[, sample_datetime := as.POSIXct(SAMPLE_DATE_MS / 1000, origin = "1970-01-01", tz = "UTC")]
all_dt[, sample_date := as.IDate(sample_datetime)]

# ---- 4. n_expected vs n_retrieved (rule 8) --------------------------------
n_retrieved <- nrow(all_dt)
n_dupe      <- n_retrieved - uniqueN(all_dt$OBJECTID)
cat("\n=== PULL ACCOUNTING (rule 8) ===\n")
cat(sprintf("n_expected      : %s\n", format(n_expected,  big.mark = ",")))
cat(sprintf("n_retrieved     : %s\n", format(n_retrieved, big.mark = ",")))
cat(sprintf("gap             : %s\n", format(n_expected - n_retrieved, big.mark = ",")))
cat(sprintf("duplicate OBJECTID: %d\n", n_dupe))
cat(sprintf("date range      : %s .. %s\n", min(all_dt$sample_date, na.rm = TRUE),
                                            max(all_dt$sample_date, na.rm = TRUE)))
cat(sprintf("NA sample_date  : %d\n", sum(is.na(all_dt$sample_date))))
if (n_retrieved != n_expected)
  cat("*** MISMATCH — recorded, NOT filled. Investigate before use. ***\n")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write_parquet(all_dt, file.path(out_dir, "habsos_ncei_raw.parquet"))
fwrite(man,           file.path(out_dir, "pull_manifest.csv"))
writeLines(c(
  sprintf("pulled_utc,%s",   format(Sys.time(), tz = "UTC")),
  sprintf("service,%s",      SERVICE),
  sprintf("n_expected,%d",   n_expected),
  sprintf("n_retrieved,%d",  n_retrieved),
  sprintf("min_date,%s",     as.character(min(all_dt$sample_date, na.rm = TRUE))),
  sprintf("max_date,%s",     as.character(max(all_dt$sample_date, na.rm = TRUE)))
), file.path(out_dir, "pull_provenance.csv"))

cat(sprintf("\nWrote: %s (%s rows)\n", file.path(out_dir, "habsos_ncei_raw.parquet"),
            format(n_retrieved, big.mark = ",")))
cat("\n=== M4-1: done ===\n")
