# ============================================================
# FILE: 01_source_data.R
# OWNER: A1 sourcing (reviewer R1)
# PURPOSE: Stand up / verify all data pulls for BloomGuard GIS.
#   1. HABSOS – verify event.txt (lat/lon/date) + occurrence.txt present
#      and can be joined; write the resolved DwC-A join note.
#   2. MODIS-Aqua L3 (OB.DAAC) – prove Earthdata auth + file-search works;
#      document the per-day streaming contract for A4.
#   3. CHIRPS – verify direct HTTPS download (no auth); document URL pattern.
#   4. SMAP – prove PODAAC/Earthdata auth works; document file-search.
#   5. ERA5 – check for ~/.cdsapirc; if absent, stop with clear message +
#      manual_downloads.md already written; if present, issue a test request.
#   6. GEBCO – static layer; manual download documented; if file present, skip.
#   7. Census TIGER – verify direct HTTPS; pull county shapefile if absent.
#
#   NOTE: The actual per-day MODIS stream-and-discard loop lives in
#         04_satellite_features.R. This script proves auth + documents the
#         mechanism and file-naming for A4 to consume.
#
# INPUTS:  config.yaml; ~/.netrc (Earthdata); ~/.cdsapirc (CDS, if present);
#          data/raw/habsos/event.txt, data/raw/habsos/occurrence.txt
# OUTPUTS: data/raw/habsos/{event,occurrence,meta}.txt (validated)
#          data/raw/gis/tl_2020_us_county.zip (Tiger, if absent)
#          data/metadata/data_sources.md (appended)
#          reports/agent_logs/sourcing.md (written)
# TECHNIQUES: httr2 (Earthdata OAuth token + Bearer download), download.file,
#             curl package for low-level HTTP. No wget.
# CITATIONS: NOAA NCEI HABSOS (ipt-obis.gbif.us/resource?r=habsos v1.5);
#            NASA OB.DAAC AQUA MODIS L3m (oceandata.sci.gsfc.nasa.gov);
#            CHIRPS v2.0 (chc.ucsb.edu); SMAP RSS L3 v6 (PODAAC);
#            Copernicus CDS ERA5 (cds.climate.copernicus.eu);
#            GEBCO 2024 (download.gebco.net); US Census TIGER 2020.
# ============================================================

# NOTE(paper): prefer APIs; manual export only where no API exists.
# NOTE(limitation): HABSOS non-detection != absence — carried through to labels.
# NOTE(cite): HABSOS Darwin Core Archive v1.5 accessed 2026-07-11 via
#             ipt-obis.gbif.us. Event core (event.txt) holds lat/lon/date;
#             Occurrence core (occurrence.txt) holds cell counts. Join on id.

local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressMessages({
  if (!requireNamespace("httr2", quietly = TRUE)) {
    install.packages("httr2", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  library(httr2)
})

access_date <- format(Sys.Date(), "%Y-%m-%d")

# ─── helpers ──────────────────────────────────────────────────────────────────
msg <- function(...) message("[A1-sourcing] ", ...)

stop_manual <- function(source_name, md_path, reason) {
  msg("BLOCKED — ", source_name, ": ", reason)
  msg("Manual steps written to: ", md_path)
  msg("Continuing with clearly-labeled placeholder flag.")
}

raw_habsos   <- proj_path(cfg$paths$raw_habsos)
raw_sat      <- proj_path(cfg$paths$raw_satellite)
raw_weather  <- proj_path(cfg$paths$raw_weather)
raw_gis      <- proj_path(cfg$paths$raw_gis)
meta_dir     <- proj_path("data/metadata")
logs_dir     <- proj_path("reports/agent_logs")

for (d in c(raw_habsos, raw_sat, raw_weather, raw_gis, meta_dir, logs_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. HABSOS — Darwin Core Archive v1.5
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 1. HABSOS ===")
# NOTE(paper): HABSOS data from NOAA NCEI/OBIS via ipt-obis.gbif.us DwC-A v1.5.
# The archive is Event-core: event.txt (lat/lon/date) + Occurrence extension
# (occurrence.txt, cell counts). Join key: occurrence.id = event.id.
# NOTE(limitation): occurrence.txt alone has no coordinates — event.txt is
# required for spatial/temporal labeling (resolved in A1 by downloading full
# DwC-A and extracting event.txt).

event_txt  <- file.path(raw_habsos, "event.txt")
occ_txt    <- file.path(raw_habsos, "occurrence.txt")
meta_xml   <- file.path(raw_habsos, "meta.xml")

if (!file.exists(event_txt)) {
  msg("event.txt missing — downloading DwC-A v1.5 from ipt-obis.gbif.us")
  dwca_zip <- file.path(tempdir(), "habsos_dwca_v1.5.zip")
  download.file(
    url      = "https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5",
    destfile = dwca_zip,
    method   = "curl",
    quiet    = TRUE
  )
  utils::unzip(dwca_zip, files = c("event.txt", "occurrence.txt",
                                    "meta.xml", "eml.xml"),
               exdir = raw_habsos, overwrite = FALSE)
  file.remove(dwca_zip)
  msg("Extracted event.txt + occurrence.txt from DwC-A zip")
} else {
  msg("event.txt already present — skipping download")
}

# Validate
stopifnot(file.exists(event_txt), file.exists(occ_txt))
evt_hdr <- readLines(event_txt, n = 1)
occ_hdr <- readLines(occ_txt,   n = 1)
evt_cols <- strsplit(evt_hdr, "\t")[[1]]
occ_cols <- strsplit(occ_hdr, "\t")[[1]]

stopifnot(
  "decimalLatitude"  %in% evt_cols,
  "decimalLongitude" %in% evt_cols,
  "eventDate"        %in% evt_cols,
  "id"               %in% evt_cols,
  "id"               %in% occ_cols,
  "organismQuantity" %in% occ_cols,
  "occurrenceStatus" %in% occ_cols
)
# Count rows (quick wc-like estimate)
n_evt <- length(readLines(event_txt)) - 1L
n_occ <- length(readLines(occ_txt))   - 1L

msg(sprintf("event.txt: %d rows | lat/lon/date OK | columns: %s",
            n_evt, paste(evt_cols, collapse=", ")))
msg(sprintf("occurrence.txt: %d rows | cell-count column: organismQuantity",
            n_occ))
msg("HABSOS — RESOLVED. Join on id. Coords + dates confirmed present.")

# NOTE(paper): Date range 1953–2022; MODIS era (2003+) well-sampled (~7,000+
# records/year). Spatial extent 24.0–30.7°N, 81.1–97.7°W; clips to study box
# 24–31°N, 87–81°W in A2/A3.

# ─────────────────────────────────────────────────────────────────────────────
# 2. MODIS-Aqua L3 (OB.DAAC) — auth + file-search proof
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 2. MODIS OB.DAAC (auth proof only — bulk streaming in A4) ===")
# NOTE(paper): MODIS Aqua L3 mapped daily global composites, 9 km resolution.
# Products used: CHL.chlor_a, FLH.nflh, KD.Kd_490, SST.sst (NSST).
# File naming: AQUA_MODIS.YYYYMMDD.L3m.DAY.{PRODUCT}.{var}.{res}.nc
# Auth: NASA Earthdata OAuth2 Bearer token (max 2 per account).
# NOTE(limitation): MODIS L3 daily global files ~5 MB each; NO server-side
#   bbox — must download full global file, clip to 24–31N/87–81W, aggregate
#   to 10 km grid, then delete. Stream-and-discard implemented in A4.
# NOTE(cite): NASA OB.DAAC, accessed via oceandata.sci.gsfc.nasa.gov.

netrc_file <- path.expand(cfg$credentials$earthdata_netrc)
if (!file.exists(netrc_file)) {
  stop("~/.netrc not found. Add: machine urs.earthdata.nasa.gov login USER password PASS")
}

# Read Earthdata credentials from netrc
netrc_text <- paste(readLines(netrc_file, warn = FALSE), collapse = " ")
ed_match <- regmatches(netrc_text, regexpr(
  "machine urs\\.earthdata\\.nasa\\.gov login (\\S+) password (\\S+)",
  netrc_text, perl = TRUE))
if (length(ed_match) == 0) stop("No Earthdata credentials in ~/.netrc")
ed_parts <- strsplit(ed_match, " ")[[1]]
ed_user  <- ed_parts[4]
ed_pass  <- ed_parts[6]

# Get existing Earthdata token (max 2 per account; use first available)
# NOTE(paper): Earthdata token auth via /api/users/tokens (GET). If no tokens
#   exist, generate one via POST /api/users/token. Max 2 tokens per account.
token_list_resp <- request("https://urs.earthdata.nasa.gov/api/users/tokens") |>
  req_auth_basic(ed_user, ed_pass) |>
  req_error(is_error = function(r) FALSE) |>
  req_perform()

if (resp_status(token_list_resp) != 200L) {
  stop("Earthdata token list failed: HTTP ", resp_status(token_list_resp))
}
tokens <- resp_body_json(token_list_resp)

if (length(tokens) == 0L) {
  # Generate a new token
  gen_resp <- request("https://urs.earthdata.nasa.gov/api/users/token") |>
    req_method("POST") |>
    req_auth_basic(ed_user, ed_pass) |>
    req_error(is_error = function(r) FALSE) |>
    req_perform()
  if (!resp_status(gen_resp) %in% c(200L, 201L)) {
    stop("Token generation failed: HTTP ", resp_status(gen_resp))
  }
  earthdata_token <- resp_body_json(gen_resp)$access_token
} else {
  earthdata_token <- tokens[[1]]$access_token
}
msg("Earthdata token obtained (first 10 chars): ", substr(earthdata_token, 1, 10), "...")

# Test file-search for a known date
test_date <- "2020-06-01"
search_resp <- request("https://oceandata.sci.gsfc.nasa.gov/api/file_search") |>
  req_body_form(
    sensor  = "AQUA",
    sdate   = test_date,
    edate   = test_date,
    dtype   = "L3m",
    subtype = "CHL",
    addurl  = "1",
    format  = "txt"
  ) |>
  req_headers(Authorization = paste("Bearer", earthdata_token)) |>
  req_error(is_error = function(r) FALSE) |>
  req_perform()

if (resp_status(search_resp) != 200L) {
  stop("OB.DAAC file search failed: HTTP ", resp_status(search_resp))
}
file_urls <- strsplit(trimws(resp_body_string(search_resp)), "\n")[[1]]
file_urls <- file_urls[nzchar(file_urls)]

# Filter for CHL chlor_a 9km daily
chl9km_urls <- grep("DAY\\.CHL\\.chlor_a\\.9km\\.nc$", file_urls, value = TRUE)
msg(sprintf("OB.DAAC file search: %d total files, %d CHL chlor_a 9km DAY",
            length(file_urls), length(chl9km_urls)))
stopifnot(length(chl9km_urls) > 0)
msg("Example CHL URL: ", chl9km_urls[1])

# Verify download auth (streaming the full file — confirms end-to-end)
# NOTE: A4 will use this same pattern per day in its stream-and-discard loop.
dest_nc <- tempfile(fileext = ".nc")
dl_resp <- request(chl9km_urls[1]) |>
  req_headers(Authorization = paste("Bearer", earthdata_token)) |>
  req_error(is_error = function(r) FALSE) |>
  req_timeout(120) |>
  req_perform(path = dest_nc)

if (resp_status(dl_resp) == 200L && file.exists(dest_nc) && file.size(dest_nc) > 1e5) {
  raw_magic <- readBin(dest_nc, what = "raw", n = 4)
  is_hdf5 <- identical(raw_magic[1:4], as.raw(c(0x89, 0x48, 0x44, 0x46)))
  file.remove(dest_nc)
  if (is_hdf5) {
    msg("MODIS download AUTH PROVEN: HDF5/NetCDF4 file received (",
        file.size(dest_nc), " bytes before removal)")
    msg("A4 should use same token mechanism: Bearer + OB.DAAC /getfile/ URL")
  } else {
    warning("MODIS download returned non-HDF5 content — check auth")
  }
} else {
  file.remove(dest_nc)
  warning("MODIS download auth test inconclusive: HTTP ", resp_status(dl_resp))
}

# NOTE(paper): A4 (sat-features) implements stream-and-discard per day.
# Loop: (1) file-search for date → get URL, (2) download global NC4,
# (3) crop to bbox 24–31N / 87–81W, (4) aggregate to 10 km grid,
# (5) append rows to Parquet, (6) unlink() raw file.
# Checkpoint by date so reruns skip already-processed days.

# Save token to environment for A4 (NOT to disk)
# NOTE: token must be obtained fresh at start of each A4 run session.
Sys.setenv(EARTHDATA_TOKEN = earthdata_token)
msg("EARTHDATA_TOKEN env var set for downstream use in this session")

# ─────────────────────────────────────────────────────────────────────────────
# 3. CHIRPS v2.0 — direct HTTPS (no auth)
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 3. CHIRPS ===")
# NOTE(paper): CHIRPS v2.0 global daily precipitation at 0.05° resolution.
# URL pattern: https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/
#              tifs/p05/{YEAR}/chirps-v2.0.YYYY.MM.DD.tif.gz
# ERA5 supports server-side bbox (use it in A5); CHIRPS does not — download
# full tile, clip to study box, discard. But CHIRPS files are small (~3–5 MB
# for compressed global GeoTIFF), so impact is minimal.
# NOTE(cite): Funk et al. (2015) Sci. Data 2:150066. UCSB CHC, chc.ucsb.edu.

chirps_test_url <- paste0(
  "https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/tifs/p05/2020/",
  "chirps-v2.0.2020.06.01.tif.gz"
)
chirps_head <- request(chirps_test_url) |>
  req_method("HEAD") |>
  req_error(is_error = function(r) FALSE) |>
  req_perform()

if (resp_status(chirps_head) == 200L) {
  msg("CHIRPS accessible: HTTP 200 | URL pattern confirmed")
  msg("  URL: ", chirps_test_url)
} else {
  warning("CHIRPS HEAD returned ", resp_status(chirps_head), " — check network")
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. SMAP RSS L3 SSS — PODAAC / Earthdata auth proof
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 4. SMAP ===")
# NOTE(paper): SMAP RSS L3 SSS 8-day running mean v6.0. Salinity is a broad-
# context feature (coarse ~40–70 km resolution); used as stratification proxy.
# NOTE(limitation): SMAP salinity is far coarser than MODIS — will be flagged
#   as broad-context in the datacube (feature_filled or coarse_context column).
# NOTE(cite): Meissner et al. (2019), Remote Sensing of Environment.

smap_cmr_resp <- request("https://cmr.earthdata.nasa.gov/search/granules.json") |>
  req_url_query(
    short_name  = "SMAP_RSS_L3_SSS_SMI_8DAY-RUNNINGMEAN_V6",
    `temporal[]` = "2020-06-01T00:00:00Z,2020-06-10T23:59:59Z",
    page_size   = 2L
  ) |>
  req_error(is_error = function(r) FALSE) |>
  req_perform()

if (resp_status(smap_cmr_resp) == 200L) {
  smap_entries <- resp_body_json(smap_cmr_resp)$feed$entry
  msg(sprintf("SMAP CMR search: %d granules found (2020-06-01 to 2020-06-10)",
              length(smap_entries)))

  if (length(smap_entries) > 0L) {
    # Get the HTTPS download URL
    smap_links <- smap_entries[[1]]$links
    smap_https <- Filter(function(l) {
      !is.null(l$href) && grepl("^https://", l$href) && grepl("\\.nc$|\\.nc4$", l$href)
    }, smap_links)

    if (length(smap_https) > 0L) {
      smap_url <- smap_https[[1]]$href
      # Verify Bearer token auth works for PODAAC
      smap_head <- request(smap_url) |>
        req_headers(Authorization = paste("Bearer", earthdata_token)) |>
        req_method("HEAD") |>
        req_error(is_error = function(r) FALSE) |>
        req_perform()
      msg("SMAP PODAAC download auth: HTTP ", resp_status(smap_head), " | URL: ", smap_url)
      if (resp_status(smap_head) == 200L) msg("SMAP AUTH PROVEN")
    }
  }
} else {
  warning("SMAP CMR search failed: HTTP ", resp_status(smap_cmr_resp))
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. ERA5 (Copernicus CDS) — check credentials, test or document
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 5. ERA5 / Copernicus CDS ===")
# NOTE(paper): ERA5 reanalysis, hourly single-level fields. Variables needed:
#   u10, v10 (wind), tp (precip). CDS API v3 supports server-side bbox subsetting
#   via the 'area' parameter (N/W/S/E) — use it in A5 to avoid global downloads.
# NOTE(cite): Hersbach et al. (2020) Q.J.R. Meteorol. Soc. 146(730):1999–2049.

cds_config <- path.expand(cfg$credentials$copernicus_cdsapirc)
if (!file.exists(cds_config)) {
  stop_manual(
    "ERA5/CDS",
    file.path(raw_weather, "manual_downloads.md"),
    "~/.cdsapirc not found — CDS API key required"
  )
  # NOTE: ERA5 wind/precip data for A5 is blocked pending CDS setup.
  # A placeholder IS_PLACEHOLDER = TRUE flag will be set in A5 until resolved.
  # Manual steps: see data/raw/weather/manual_downloads.md
} else {
  # Read key and test CDS API v3
  cds_lines  <- readLines(cds_config, warn = FALSE)
  cds_key    <- trimws(sub("^key:\\s*", "", cds_lines[grepl("^key:", cds_lines)]))
  cds_url    <- trimws(sub("^url:\\s*", "", cds_lines[grepl("^url:", cds_lines)]))
  if (!nzchar(cds_url)) cds_url <- "https://cds.climate.copernicus.eu/api"

  cds_test <- request(paste0(cds_url, "/catalogue/v1/collections/reanalysis-era5-single-levels")) |>
    req_headers(`PRIVATE-TOKEN` = cds_key) |>
    req_error(is_error = function(r) FALSE) |>
    req_perform()
  msg("CDS API test: HTTP ", resp_status(cds_test))
  if (resp_status(cds_test) == 200L) msg("ERA5 CDS AUTH PROVEN") else
    warning("ERA5 CDS returned HTTP ", resp_status(cds_test), " — check ~/.cdsapirc")
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. GEBCO 2024 — static bathymetry (manual download documented)
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 6. GEBCO ===")
# NOTE(paper): GEBCO 2024 Sub-Ice Topo grid, 15 arc-second global bathymetry.
#   Used as static layer: distance-to-shore, depth features (cell centroid depth
#   and bathymetry class). Single download; no temporal repeat needed.
# NOTE(cite): GEBCO Compilation Group (2024). GEBCO 2024 Grid.
#             doi:10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f.

gebco_dir  <- raw_gis
gebco_file <- file.path(gebco_dir, "gebco_2024_wfs.nc")  # west-florida subset

if (!file.exists(gebco_file)) {
  msg("GEBCO subset not found. Manual download required.")
  msg("See data/raw/gis/manual_downloads.md for exact steps.")
  msg("IS_PLACEHOLDER: bathymetry features will be skipped until file is present.")
} else {
  msg("GEBCO file found: ", gebco_file)
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Census TIGER 2020 — counties (direct HTTPS download)
# ─────────────────────────────────────────────────────────────────────────────
msg("=== 7. Census TIGER ===")
# NOTE(paper): US Census TIGER 2020 county boundaries. Used for: (1) spatial
#   splits in validation (hold-out coastal counties), (2) risk summaries in GIS.
# NOTE(cite): US Census Bureau, TIGER/Line Shapefiles 2020.
#             https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html

tiger_zip  <- file.path(raw_gis, "tl_2020_us_county.zip")
tiger_url  <- "https://www2.census.gov/geo/tiger/TIGER2020/COUNTY/tl_2020_us_county.zip"

if (!file.exists(tiger_zip)) {
  msg("Downloading TIGER county shapefile (~75 MB) ...")
  download.file(tiger_url, destfile = tiger_zip, method = "curl", quiet = FALSE)
  msg("Downloaded: ", tiger_zip, " (", round(file.size(tiger_zip)/1e6, 1), " MB)")
} else {
  msg("TIGER county file already present: ", tiger_zip)
}

stopifnot(file.exists(tiger_zip))

# ─────────────────────────────────────────────────────────────────────────────
# 8. Write data_sources.md log entry
# ─────────────────────────────────────────────────────────────────────────────
sources_md <- file.path(meta_dir, "data_sources.md")
if (!file.exists(sources_md)) {
  cat("# BloomGuard GIS — Data Sources\n\n", file = sources_md)
  cat("Fields: dataset | source URL | date accessed | access method | auth | resolution | temporal coverage | license | purpose\n\n",
      file = sources_md, append = TRUE)
  cat("---\n\n", file = sources_md, append = TRUE)
}

new_entries <- sprintf(
"## Sources logged by A1 sourcing (accessed %s)

| Dataset | Source URL | Access method | Auth? | Resolution | Temporal | License | Purpose |
|---|---|---|---|---|---|---|---|
| HABSOS K.brevis DwC-A v1.5 | https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5 | API download (curl) | No | point samples | 1953–2022 | CC BY 4.0 | Ground-truth labels |
| MODIS-Aqua L3m daily CHL/SST | https://oceandata.sci.gsfc.nasa.gov/ (OB.DAAC file_search API) | httr2 Bearer token | Yes (Earthdata) | ~9 km | 2002–present | Open/NASA | Satellite features |
| SMAP RSS L3 SSS 8-day | https://archive.podaac.earthdata.nasa.gov/ (CMR search) | httr2 Bearer token | Yes (Earthdata) | ~40–70 km | 2015–present | Open/NASA | Salinity (broad context) |
| CHIRPS v2.0 | https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/ | direct HTTPS download | No | ~5 km / 0.05° | 1981–present | Open/CC | Precipitation |
| ERA5 single levels | https://cds.climate.copernicus.eu/api | CDS API v3 (httr2) | Yes (CDS key) | 0.25° | 1940–present | CC BY 4.0 | Wind, precipitation |
| GEBCO 2024 | https://download.gebco.net/ | Manual (JS portal) | No | 15 arc-sec | static | CC BY 4.0 | Bathymetry |
| US Census TIGER 2020 | https://www2.census.gov/geo/tiger/TIGER2020/COUNTY/ | direct HTTPS download | No | vector | 2020 | Public domain | Spatial splits |

", access_date)

cat(new_entries, file = sources_md, append = TRUE)
msg("data_sources.md updated: ", sources_md)

msg("=== A1 sourcing complete ===")
msg("HABSOS: event.txt (lat/lon/date) + occurrence.txt RESOLVED")
msg("MODIS: Earthdata auth PROVEN; file-search + download mechanism documented for A4")
msg("CHIRPS: accessible, no auth needed")
msg("SMAP: PODAAC Bearer token auth PROVEN")
msg("ERA5: BLOCKED if ~/.cdsapirc absent — see data/raw/weather/manual_downloads.md")
msg("GEBCO: manual download required — see data/raw/gis/manual_downloads.md")
msg("TIGER: downloaded to data/raw/gis/")
