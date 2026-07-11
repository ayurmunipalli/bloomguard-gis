# ============================================================
# FILE: 03_habsos_labels.R
# OWNER: A3 habsos-label (reviewer R3, sonnet-5)
# PURPOSE: Aggregate HABSOS K. brevis to cell x date; assign binary HAB label
#          (>100,000 cells/L, D2). Joins Darwin Core event.txt + occurrence.txt,
#          filters to study area, spatial-joins to A2 grid, aggregates per cell-day.
# INPUTS:  data/raw/habsos/occurrence.txt (DwC-A occurrence extension)
#          data/raw/habsos/event.txt      (DwC-A event core — lat, lon, date)
#          data/processed/study_area_grid.gpkg  (from A2 grid-clean)
#          config.yaml
# OUTPUTS: data/processed/habsos_labels.parquet  — cell x date with HAB label
#          (console) labels summary: positive/negative cell-day counts + balance
# TECHNIQUES:
#   - Darwin Core Archive join (event core + occurrence extension on eventID)
#   - sf point-in-polygon spatial join (st_join / st_within) in Albers EPSG:5070
#   - Daily aggregation: max(organism_quantity) per cell x date
#   - Binary label: HAB = 1 if max > 100,000 cells/L (D2, PLAN.md §2)
#   - Placeholder mode if A2 grid not yet available (IS_PLACEHOLDER = TRUE)
# CITATIONS:
#   - HABSOS: NOAA NCEI HABSOS v1.5, ipt-obis.gbif.us/resource?r=habsos (2022-09-30)
#   - Threshold D2: standard bloom-level threshold in remote-sensing studies
#   - DwC-A standard: https://www.tdwg.org/standards/dwc/
# ============================================================

# NOTE(paper): positive label = K. brevis > 100,000 cells/L aggregated to cell x date (D2/D3).
#              This threshold is the standard bloom-level in remote-sensing K. brevis literature.
# NOTE(cite): HABSOS dataset: NOAA NCEI HABSOS v1.5 (downloaded 2026-07-11 via ipt-obis.gbif.us).
# NOTE(limitation): HABSOS non-detection != proven absence. An "absent" record or a cell-day
#                   with no HABSOS sample may simply be unsampled — not a confirmed non-bloom.
#                   Negative labels are soft negatives under sparse sampling. Stated in every
#                   summary and passed to downstream agents as IS_ABSENCE_UNCERTAIN = TRUE.

# ---- Bootstrap: walk up to the repo root (dir with config.yaml) and load config. ----
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(data.table)
  library(sf)
  library(arrow)
})

cat("=== A3 habsos-label: building cell x date labels ===\n\n")

# -----------------------------------------------------------------------
# 1. READ EVENT CORE (lat, lon, date) + OCCURRENCE EXTENSION (cell count)
# -----------------------------------------------------------------------
event_path <- proj_path(cfg$paths$raw_habsos, "event.txt")
occ_path   <- proj_path(cfg$paths$raw_habsos, "occurrence.txt")

if (!file.exists(event_path)) {
  stop("event.txt not found at ", event_path,
       "\nRe-pull from: https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5",
       "\nExtract the zip and place event.txt in data/raw/habsos/")
}

# NOTE(paper): the HABSOS DwC-A (v1.5) ships as a Sampling Event archive:
#   event.txt (core) carries eventDate, decimalLatitude, decimalLongitude;
#   occurrence.txt (extension) carries organismQuantity (cells/L) and occurrenceStatus.
#   Join key: event.txt$id = occurrence.txt$eventID (identical value: habsos_<N>_<state>).

cat("Reading event.txt (lat/lon/date)...\n")
events <- fread(event_path,
                select   = c("id", "eventDate", "decimalLatitude", "decimalLongitude"),
                encoding = "UTF-8", showProgress = FALSE)
setnames(events, c("id", "eventDate", "decimalLatitude", "decimalLongitude"),
                 c("event_id", "eventDate", "lat", "lon"))

# Drop 2 rows with parse-corrupt lat (multi-line locality field broke TSV)
events <- events[!is.na(lat) & !is.na(lon) & lat != "" & lon != ""]
events[, lat := as.numeric(lat)]
events[, lon := as.numeric(lon)]
events <- events[!is.na(lat) & !is.na(lon)]

cat("Reading occurrence.txt (cell counts)...\n")
occ <- fread(occ_path,
             select   = c("id", "eventID", "organismQuantity", "organismQuantityType",
                          "occurrenceStatus"),
             encoding = "UTF-8", showProgress = FALSE)
setnames(occ, c("id", "eventID", "organismQuantity"),
              c("occ_id", "event_id", "organism_quantity"))
occ[, organism_quantity := as.numeric(organism_quantity)]

# NOTE(paper): DwC-A occurrence extension links to events via eventID (= event.txt id).
hab_raw <- merge(events, occ, by = "event_id", all.x = FALSE, all.y = FALSE)
cat(sprintf("After join: %d records\n", nrow(hab_raw)))

# -----------------------------------------------------------------------
# 2. PARSE DATE + FILTER TO STUDY AREA BOUNDING BOX
# -----------------------------------------------------------------------
# NOTE(paper): Study area = 24–31°N, 87–81°W (Hu et al. 2022, D1). Bounding-box
#              pre-filter in WGS84 before reprojecting for efficiency.
bbox <- cfg$study_area$bbox_wgs84
hab_raw <- hab_raw[lon >= bbox$xmin & lon <= bbox$xmax &
                   lat >= bbox$ymin & lat <= bbox$ymax]
cat(sprintf("After bbox filter: %d records\n", nrow(hab_raw)))

# Parse ISO-8601 eventDate -> date (date only, drop time)
hab_raw[, sample_date := as.IDate(substr(eventDate, 1, 10))]
hab_raw <- hab_raw[!is.na(sample_date)]
cat(sprintf("Date range: %s to %s\n", min(hab_raw$sample_date), max(hab_raw$sample_date)))

# -----------------------------------------------------------------------
# 3. SPATIAL JOIN TO GRID (gated on A2 output)
# -----------------------------------------------------------------------
grid_path  <- proj_path(cfg$paths$grid)
out_path   <- proj_path(cfg$paths$habsos_labels)
grid_ready <- file.exists(grid_path)

if (grid_ready) {
  cat("Grid found — performing spatial join to", grid_path, "\n")

  # NOTE(paper): points reprojected from WGS84 (EPSG:4326) to Albers (EPSG:5070)
  #              to match the 10 km grid; spatial join uses st_within.
  pts <- st_as_sf(hab_raw, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
  pts <- st_transform(pts, crs = 5070)

  grid <- st_read(grid_path, quiet = TRUE)
  id_col <- cfg$grid$id_col   # "cell_id"

  # st_join uses whatever geometry column the sf object carries (may be "geom" not "geometry")
  joined <- st_join(pts, grid[, id_col], join = st_within, left = FALSE)
  setDT(joined)
  # Drop the sf geometry column (whatever it's named)
  geom_cols <- c("geometry", "geom")
  for (gc in geom_cols) if (gc %in% names(joined)) joined[, (gc) := NULL]

  # -----------------------------------------------------------------------
  # 4. AGGREGATE: max cell_count per (cell_id x date) -> binary HAB label
  # -----------------------------------------------------------------------
  threshold <- cfg$label$threshold_cells_per_L   # 100,000

  # NOTE(paper): aggregation takes the max K. brevis count across all samples within
  #              a cell on a given day. If the max exceeds 100,000 cells/L (D2), HAB = 1.
  cell_day <- joined[, .(
    max_count  = max(organism_quantity, na.rm = TRUE),
    n_samples  = .N
  ), by = .(cell_id = get(id_col), sample_date)]

  cell_day[, HAB             := as.integer(max_count > threshold)]
  cell_day[, IS_PLACEHOLDER  := FALSE]
  cell_day[, IS_ABSENCE_UNCERTAIN := TRUE]  # non-detection != absence

  is_placeholder <- FALSE

} else {
  # -----------------------------------------------------------------------
  # PLACEHOLDER MODE — grid not yet available from A2
  # -----------------------------------------------------------------------
  # NOTE: IS_PLACEHOLDER = TRUE means this parquet carries NO real cell_id assignments.
  #       It only holds HABSOS points aggregated by (lat_bin, lon_bin) as a schema stub.
  #       A3 MUST re-run once data/processed/study_area_grid.gpkg is available.
  cat("*** PLACEHOLDER MODE: study_area_grid.gpkg not found. ***\n")
  cat("    Re-run 03_habsos_labels.R after A2 grid-clean completes.\n\n")

  # NOTE(paper): placeholder groups by 0.1-degree lat/lon bin rather than grid cell.
  #              NOT for modeling — schema stub only. cell_id = "PLACEHOLDER_<lat>_<lon>".
  threshold <- cfg$label$threshold_cells_per_L

  hab_raw[, lat_bin := round(lat, 1)]
  hab_raw[, lon_bin := round(lon, 1)]
  hab_raw[, cell_id := paste0("PLACEHOLDER_", lat_bin, "_", lon_bin)]

  cell_day <- hab_raw[, .(
    max_count  = max(organism_quantity, na.rm = TRUE),
    n_samples  = .N
  ), by = .(cell_id, sample_date)]

  cell_day[, HAB                 := as.integer(max_count > threshold)]
  cell_day[, IS_PLACEHOLDER      := TRUE]
  cell_day[, IS_ABSENCE_UNCERTAIN := TRUE]

  is_placeholder <- TRUE
}

# -----------------------------------------------------------------------
# 5. OUTPUT: SAVE PARQUET + LABELS SUMMARY
# -----------------------------------------------------------------------
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

write_parquet(cell_day, out_path)
cat(sprintf("\nWrote: %s\n", out_path))

# Labels summary
n_pos     <- sum(cell_day$HAB == 1)
n_neg     <- sum(cell_day$HAB == 0)
n_total   <- nrow(cell_day)
pct_pos   <- round(100 * n_pos / n_total, 2)

cat("\n=== LABELS SUMMARY ===\n")
cat(sprintf("Total cell-day rows : %d\n", n_total))
cat(sprintf("Positive (HAB=1)    : %d  (%.2f%%)\n", n_pos, pct_pos))
cat(sprintf("Negative (HAB=0)    : %d  (%.2f%%)\n", n_neg, 100 - pct_pos))
cat(sprintf("Threshold used      : > %s cells/L (D2)\n",
            format(threshold, big.mark = ",")))
cat(sprintf("Date range          : %s to %s\n",
            min(cell_day$sample_date), max(cell_day$sample_date)))
cat(sprintf("IS_PLACEHOLDER      : %s\n", is_placeholder))
cat("\n")

# NOTE(limitation): HABSOS non-detection != proven absence. Absent/zero records reflect
#                   a sample was taken and K. brevis was at or below detection; cell-days
#                   with NO sample at all are simply missing from this dataset — they
#                   are NOT represented as negatives here. Downstream agents must account
#                   for the difference between a sampled negative and an unsampled gap.
# NOTE(limitation): Label balance (~%.2f%% positive) reflects sampling effort, not true
#                   bloom frequency. Class imbalance should be addressed in modeling (A7).
cat("NOTE(limitation): negatives are SAMPLED non-detections, not confirmed absences.\n")
cat("NOTE(limitation): label balance reflects sampling effort, not true bloom frequency.\n")
if (is_placeholder) {
  cat("\n*** BLOCKER: IS_PLACEHOLDER = TRUE. Grid join deferred until A2 delivers\n")
  cat("             data/processed/study_area_grid.gpkg. Re-run this script then.\n")
}

cat("\n=== A3 habsos-label: done ===\n")
