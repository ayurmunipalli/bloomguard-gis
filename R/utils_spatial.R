# ============================================================
# FILE: utils_spatial.R
# OWNER: shared (A2 seeds; used across A2/A4/A5/A6/A9)
# PURPOSE: Shared spatial helpers — CRS constants, bbox->grid, point->cell join,
#          adjacency/spatial-cluster flags for grouped splits.
# INPUTS:  config.yaml (via 00_config.R).
# OUTPUTS: functions only (sourced, no side effects).
# TECHNIQUES: sf reprojection; st_make_grid; st_contains/st_join; poly adjacency
#             via st_relate (Queen contiguity). Ref: Pebesma (2018).
# CITATIONS: sf (Pebesma 2018, J Stat Softw); EPSG:5070 (USGS CONUS Albers).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(sf)
})

# NOTE(cite): sf package — Pebesma E (2018). "Simple Features for R: Standardized
#             Support for Spatial Vector Data." The R Journal, 10(1):439-446.
#             https://doi.org/10.32614/RJ-2018-009

# NOTE(paper): EPSG:5070 (NAD83 / Conus Albers) chosen because it is equal-area
#              and metric, ensuring consistent 10 km x 10 km cells across the study
#              extent. WGS84 (EPSG:4326) used for all data ingestion and export.

# ---- CRS constants -------------------------------------------------------

CRS_GEO  <- 4326L   # WGS84 geographic (all raw inputs)
CRS_PROJ <- 5070L   # Albers Equal Area metric (grid construction)

# ---- build_study_grid ----------------------------------------------------
#
# Build the West Florida Shelf study-area bounding box and 10 km grid.
#
# Steps:
#   1. Construct bbox from config (xmin/ymin/xmax/ymax in WGS84).
#   2. Convert to sfc polygon (st_as_sfc).
#   3. Reproject to EPSG:5070.
#   4. Tile with st_make_grid(cellsize = cellsize_m).
#   5. Assign an integer id column named `id_col`.
#   6. Return as sf data frame with crs = EPSG:5070.
#
# NOTE(paper): Grid is built from a projected rectangle (EPSG:5070), not from
#              WGS84 coordinates, ensuring each cell is truly 10 km x 10 km
#              (equal-area projection). Only cells inside or touching the projected
#              study bbox are retained; no hand-drawn polygon required (PLAN.md §2.1).
#
# Args:
#   bbox_wgs84  : named numeric list with xmin/ymin/xmax/ymax (degrees).
#   cellsize_m  : numeric; cell edge length in meters (default 10000).
#   id_col      : character; name for the cell id column (default "cell_id").
#
# Returns: sf data frame, EPSG:5070, one row per 10 km cell, columns: <id_col>, geometry.

build_study_grid <- function(bbox_wgs84 = cfg$study_area$bbox_wgs84,
                             cellsize_m = cfg$grid$cellsize_m,
                             id_col     = cfg$grid$id_col) {

  stopifnot(
    is.list(bbox_wgs84),
    all(c("xmin", "ymin", "xmax", "ymax") %in% names(bbox_wgs84)),
    is.numeric(cellsize_m), cellsize_m > 0,
    is.character(id_col), nchar(id_col) > 0
  )

  # Step 1-2: bbox -> sfc polygon in WGS84
  study_bbox <- sf::st_bbox(
    c(xmin = bbox_wgs84$xmin, ymin = bbox_wgs84$ymin,
      xmax = bbox_wgs84$xmax, ymax = bbox_wgs84$ymax),
    crs = sf::st_crs(CRS_GEO)
  )
  study_poly_wgs84 <- sf::st_as_sfc(study_bbox)

  # Step 3: reproject to Albers EPSG:5070
  study_poly_proj <- sf::st_transform(study_poly_wgs84, crs = CRS_PROJ)

  # Step 4: tile into cellsize_m x cellsize_m squares
  # NOTE(paper): square=TRUE creates rectangular cells; what=polygons (default)
  #              returns polygons (not centroids), so each row is a full cell footprint.
  grid_sfc <- sf::st_make_grid(study_poly_proj, cellsize = cellsize_m, what = "polygons", square = TRUE)

  # Step 5: retain only cells that intersect the study polygon
  # (st_make_grid tiles the full bbox extent; no cells fall outside because
  #  our bbox IS the study area, so this is idempotent but explicit)
  keep <- sf::st_intersects(grid_sfc, study_poly_proj, sparse = FALSE)[, 1]
  grid_sfc <- grid_sfc[keep]

  # Step 6: build sf data frame with id column
  grid_sf <- sf::st_sf(stats::setNames(list(seq_len(length(grid_sfc))), id_col),
                       geometry = grid_sfc,
                       crs = CRS_PROJ)

  message(sprintf("[build_study_grid] n_cells=%d  cellsize=%.0f m  crs=EPSG:%d",
                  nrow(grid_sf), cellsize_m, CRS_PROJ))

  # Sanity: bbox of resulting grid should contain the study area
  grid_bbox   <- sf::st_bbox(grid_sf)
  study_bbox5 <- sf::st_bbox(study_poly_proj)
  stopifnot(
    grid_bbox["xmin"] <= study_bbox5["xmin"],
    grid_bbox["ymin"] <= study_bbox5["ymin"],
    grid_bbox["xmax"] >= study_bbox5["xmax"],
    grid_bbox["ymax"] >= study_bbox5["ymax"]
  )

  grid_sf
}

# ---- points_to_cells ------------------------------------------------------
#
# Spatially join a point sf/data.frame to the study grid, reduce datetime to
# date, and aggregate per cell x date.
#
# Supports any numeric quantity column (e.g. organism count). Returns a
# data.table with one row per (id_col, date) with summary statistics.
#
# NOTE(paper): st_join with largest=TRUE uses st_contains semantics (a point
#              on a cell boundary falls into the cell that contains it).
#              datetime -> date reduction collapses intra-day samples before
#              aggregation (mentor's gulf script pattern).
# NOTE(limitation): HABSOS non-detection != proven absence. Rows with
#                   occurrenceStatus == "absent" are retained as count=0 but
#                   flagged; presence of zeros does NOT imply the area was
#                   sampled. A3 (habsos-label) must propagate this caveat.
#
# Args:
#   pts       : sf object or data.frame with lon/lat columns (WGS84).
#               Must have column `date_col` (Date or datetime) and `qty_col` (numeric).
#   grid      : sf from build_study_grid() (EPSG:5070).
#   lon_col   : name of longitude column (default "decimalLongitude").
#   lat_col   : name of latitude column (default "decimalLatitude").
#   date_col  : name of date/datetime column (default "eventDate").
#   qty_col   : name of quantity column to aggregate (default "organismQuantity").
#   id_col    : name of grid cell id column (default from cfg$grid$id_col).
#
# Returns: data.table with columns: <id_col>, date, n_samples, qty_mean,
#          qty_max, qty_sum, has_positive (any > 0), all_absent_flag (all = 0).

points_to_cells <- function(pts,
                            grid,
                            lon_col  = "decimalLongitude",
                            lat_col  = "decimalLatitude",
                            date_col = "eventDate",
                            qty_col  = "organismQuantity",
                            id_col   = cfg$grid$id_col) {

  suppressPackageStartupMessages(library(data.table))

  # --- coerce pts to sf if not already ---
  if (!inherits(pts, "sf")) {
    stopifnot(lon_col %in% names(pts), lat_col %in% names(pts))
    pts <- sf::st_as_sf(pts,
                        coords = c(lon_col, lat_col),
                        crs    = CRS_GEO,
                        remove = FALSE)
  } else {
    if (sf::st_crs(pts)$epsg != CRS_GEO) {
      pts <- sf::st_transform(pts, crs = CRS_GEO)
    }
  }

  # reproject to match grid
  pts_proj <- sf::st_transform(pts, crs = CRS_PROJ)

  # --- spatial join: assign each point its cell id ---
  # NOTE(paper): st_join(left=FALSE) keeps only points inside a grid cell,
  #              dropping points outside the study area (e.g. offshore deep water
  #              or outside the 24-31N/87-81W bbox). Points on edges fall into
  #              whichever cell st_intersects resolves first (deterministic given
  #              identical CRS).
  joined <- sf::st_join(pts_proj[, c(date_col, qty_col)],
                        grid[, id_col],
                        join = sf::st_intersects,
                        left = FALSE)

  if (nrow(joined) == 0) {
    warning("[points_to_cells] No points fell within the study grid. Check CRS and bbox.")
    return(data.table::data.table())
  }

  # drop geometry after join
  dt <- data.table::as.data.table(sf::st_drop_geometry(joined))

  # --- reduce datetime -> date ---
  dt[, date := as.Date(get(date_col))]
  if (date_col != "date") dt[, (date_col) := NULL]

  # ensure qty is numeric
  dt[, qty := suppressWarnings(as.numeric(get(qty_col)))]
  if (qty_col != "qty") dt[, (qty_col) := NULL]

  # --- per-cell x date aggregation ---
  agg <- dt[!is.na(get(id_col)) & !is.na(date),
            .(n_samples   = .N,
              qty_mean    = mean(qty, na.rm = TRUE),
              qty_max     = max(qty, na.rm = TRUE),
              qty_sum     = sum(qty, na.rm = TRUE),
              has_positive = any(qty > 0, na.rm = TRUE),
              all_absent_flag = all(qty == 0, na.rm = TRUE)),
            by = c(id_col, "date")]

  message(sprintf("[points_to_cells] n_input=%d  n_in_grid=%d  n_cell_days=%d",
                  length(pts_proj$geometry), nrow(dt), nrow(agg)))

  agg
}

# ---- flag_spatial_clusters ------------------------------------------------
#
# Assign a cluster label to each grid cell based on Queen contiguity (shared
# edge or corner). Used by A7/A11 to build grouped spatial splits that prevent
# spatially adjacent cells from straddling train/test.
#
# NOTE(paper): Queen-contiguity clusters prevent spatial autocorrelation leakage
#              in train/test splits. Cells in the same cluster are held out together.
#              Connected components computed via a simple BFS/union-find over the
#              adjacency list from sf::st_relate (DE-9IM pattern "****1****" = shared
#              interior or boundary, i.e., Queen contiguity).
# NOTE(limitation): Cells that are spatially isolated (no Queen neighbors) each
#                   form their own singleton cluster — they may be distributed freely
#                   across splits.
#
# Args:
#   grid   : sf from build_study_grid() (EPSG:5070).
#   id_col : name of cell id column.
#
# Returns: grid sf with an added integer column `spatial_cluster`.

flag_spatial_clusters <- function(grid, id_col = cfg$grid$id_col) {

  n <- nrow(grid)

  # Queen contiguity adjacency: two cells are neighbors if they share any
  # point (edge or corner). DE-9IM pattern "****1****" captures this.
  adj <- sf::st_relate(grid, grid, pattern = "****1****", sparse = TRUE)
  # adj[[i]] = integer vector of neighbor row indices for row i

  # --- connected components via union-find ---
  parent <- seq_len(n)

  find <- function(x) {
    while (parent[x] != x) {
      parent[x] <<- parent[parent[x]]  # path compression
      x <- parent[x]
    }
    x
  }
  unite <- function(a, b) {
    ra <- find(a); rb <- find(b)
    if (ra != rb) parent[ra] <<- rb
  }

  for (i in seq_len(n)) {
    for (j in adj[[i]]) {
      if (j != i) unite(i, j)
    }
  }

  roots <- vapply(seq_len(n), find, integer(1))
  # recode roots to 1..K
  root_map <- match(roots, sort(unique(roots)))
  grid$spatial_cluster <- root_map

  n_clusters <- max(root_map)
  message(sprintf("[flag_spatial_clusters] n_cells=%d  n_clusters=%d", n, n_clusters))

  grid
}

message("utils_spatial.R loaded: build_study_grid / points_to_cells / flag_spatial_clusters ready.")
