# ============================================================
# FILE: 02_build_grid.R
# OWNER: A2 grid-clean (reviewer R2)
# PURPOSE: Build the study-area box (24-31N, 87-81W; Hu et al. 2022) in code and
#          grid it into 10 km cells (Green method). Write data/processed/study_area_grid.gpkg.
#          Point cleaning/joining helpers live in utils_spatial.R; this script exercises
#          them once A1 delivers geocoded HABSOS points.
# INPUTS:  config.yaml (study_area bbox, grid cellsize/id_col).
#          [deferred] data/raw/habsos/ geocoded points from A1.
# OUTPUTS: data/processed/study_area_grid.gpkg  — grid with cell_id, EPSG:5070.
# TECHNIQUES: sf::st_bbox -> st_as_sfc (WGS84) -> st_transform EPSG:5070 ->
#             st_make_grid(cellsize=10000) -> cell_id; flag_spatial_clusters for splits.
#             Ref: Green (2022) RTM gridding; Hu et al. (2022) study extent.
# CITATIONS: Hu et al. (2022) Harmful Algae 117:102289 (study bbox);
#            Green (2022) RTM paper (gridding method);
#            Pebesma (2018) J Stat Softw (sf package);
#            EPSG:5070 NAD83/Conus Albers (USGS).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

source(proj_path("R", "utils_spatial.R"))
suppressPackageStartupMessages(library(sf))

# NOTE(paper): 10 km cells exceed the ~4 km MODIS L3 pixel -> real spatial
#              aggregation, no false sub-pixel precision; cells sit below coarse
#              wind/salinity fields (~0.25 deg ~28 km). Study extent (24-31N,
#              87-81W) follows Hu et al. (2022), the established ocean-color study
#              area for K. brevis on the West Florida Shelf.
# NOTE(cite): Albers Equal Area (EPSG:5070) chosen for metric distances — all
#             cellsize_m values are true meters under this projection.
# NOTE(cite): Grid construction method mirrors the mentor's gulf script
#             (Green 2022): lay a projected grid, aggregate points into cells,
#             predict per-cell risk.

# ============================================================
# 1. Build the study-area grid
# ============================================================

message("=== 02_build_grid.R  step 1: build study-area grid ===")

grid <- build_study_grid(
  bbox_wgs84 = cfg$study_area$bbox_wgs84,
  cellsize_m = cfg$grid$cellsize_m,
  id_col     = cfg$grid$id_col
)

# --- Verification: cell count and bbox coverage ---
n_cells    <- nrow(grid)
grid_bbox  <- sf::st_bbox(grid)

# Reproject bbox to WGS84 for human-readable check
study_poly_wgs84 <- sf::st_as_sfc(
  sf::st_bbox(c(xmin = cfg$study_area$bbox_wgs84$xmin,
                ymin = cfg$study_area$bbox_wgs84$ymin,
                xmax = cfg$study_area$bbox_wgs84$xmax,
                ymax = cfg$study_area$bbox_wgs84$ymax),
              crs = sf::st_crs(4326L))
)
study_poly_proj <- sf::st_transform(study_poly_wgs84, crs = 5070L)
study_bbox5     <- sf::st_bbox(study_poly_proj)

# NOTE(paper): Expected cell count ~ (6 deg lon * ~111 km/deg) * (7 deg lat * ~111 km/deg)
#              / (10 km)^2 ~ 666*777/100 ~ 5177 cells (rough upper bound before edge trimming).
#              Actual count ≤ this; cells outside the projected bbox are dropped.
message(sprintf("Grid: %d cells  (expected ~4600-5200 for the 24-31N/87-81W box)", n_cells))
message(sprintf("Grid bbox (EPSG:5070): xmin=%.0f  ymin=%.0f  xmax=%.0f  ymax=%.0f",
                grid_bbox["xmin"], grid_bbox["ymin"],
                grid_bbox["xmax"], grid_bbox["ymax"]))

# Assert grid fully covers the study polygon (non-negotiable spatial check)
stopifnot(
  "Grid xmin does not cover study area xmin" = grid_bbox["xmin"] <= study_bbox5["xmin"],
  "Grid ymin does not cover study area ymin" = grid_bbox["ymin"] <= study_bbox5["ymin"],
  "Grid xmax does not cover study area xmax" = grid_bbox["xmax"] >= study_bbox5["xmax"],
  "Grid ymax does not cover study area ymax" = grid_bbox["ymax"] >= study_bbox5["ymax"]
)
message("PASS: grid fully covers the study-area bbox.")

# CRS check
stopifnot("Grid CRS is not EPSG:5070" = sf::st_crs(grid)$epsg == 5070L)
message("PASS: grid CRS = EPSG:5070.")

# ============================================================
# 2. Add spatial cluster labels (for grouped splits in A7/A11)
# ============================================================

message("=== step 2: flag spatial clusters ===")

grid <- flag_spatial_clusters(grid, id_col = cfg$grid$id_col)

# NOTE(paper): Spatial clusters (Queen contiguity connected components) prevent
#              adjacent cells from straddling train/test splits, reducing spatial
#              autocorrelation leakage (see PLAN.md §6-A7, R-SPLIT).

# ============================================================
# 3. Write the grid
# ============================================================

message("=== step 3: write study_area_grid.gpkg ===")

out_path <- proj_path(cfg$paths$grid)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

sf::st_write(grid, out_path, layer = "study_area_grid", delete_layer = TRUE, quiet = FALSE)

# Verify the written file
grid_check <- sf::st_read(out_path, layer = "study_area_grid", quiet = TRUE)
stopifnot(
  "Written cell count mismatch" = nrow(grid_check) == n_cells,
  "Written CRS mismatch"        = sf::st_crs(grid_check)$epsg == 5070L
)
message(sprintf("WRITTEN & VERIFIED: %s  (%d cells, EPSG:5070)", out_path, nrow(grid_check)))

# ============================================================
# 4. Point cleaning (deferred — awaiting geocoded HABSOS from A1)
# ============================================================
#
# NOTE(limitation): The current data/raw/habsos/occurrence.txt (DwC-A export)
#   contains no decimalLatitude / decimalLongitude / eventDate columns.
#   Point-to-cell spatial join (points_to_cells()) is implemented in
#   utils_spatial.R but cannot run until A1 delivers geocoded points.
#   See data/raw/habsos/manual_downloads.md for re-pull instructions.
#   IS_PLACEHOLDER: point-cleaning section is a deferred stub.
#
# Once A1 delivers geocoded HABSOS (e.g. data/raw/habsos/habsos_geo.csv), run:
#
#   habsos_raw <- data.table::fread(proj_path("data/raw/habsos/habsos_geo.csv"))
#   cell_days  <- points_to_cells(
#     pts      = habsos_raw,
#     grid     = grid,
#     lon_col  = "decimalLongitude",
#     lat_col  = "decimalLatitude",
#     date_col = "eventDate",
#     qty_col  = "organismQuantity",
#     id_col   = cfg$grid$id_col
#   )
#   # cell_days is handed to A3 (habsos-label) for binary HAB labeling.
#
# BLOCKER: no coordinates in current occurrence.txt — A1 (sourcing) must
#          resolve the DwC-A companion files or re-export from HABSOS portal
#          with lat/lon/date fields.

message("=== 02_build_grid.R complete ===")
message(sprintf("OUTPUT: %s  |  cells: %d  |  clusters: %d",
                out_path, n_cells, max(grid$spatial_cluster)))
message("DEFERRED: point cleaning awaits geocoded HABSOS from A1.")
