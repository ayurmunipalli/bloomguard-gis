# ============================================================
# FILE: 02_build_grid.R
# OWNER: A2 grid-clean (reviewer R2)
# PURPOSE: Build the study-area box (24-31N, 87-81W; Hu et al. 2022) in code and grid it
#          into 10 km cells (Green method); clean/spatially-join point data to cells.
# INPUTS:  config.yaml (study_area bbox, grid cellsize/id_col); raw point data from A1.
# OUTPUTS: data/processed/study_area_grid.gpkg; cleaned per-variable spatial tables.
# TECHNIQUES: sf::st_bbox -> st_as_sfc (WGS84) -> st_transform EPSG:5070 ->
#             st_make_grid(cellsize=10000) -> cell_id; st_contains join; date reduce.
# CITATIONS: Green (2022) RTM gridding; Albers EPSG:5070 (USGS CONUS Albers).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): 10 km cells exceed ~4 km MODIS L3 pixel -> real aggregation, no false precision;
#              below coarse wind/salinity fields. EPSG:5070 for metric distances.
# NOTE(cite):  Albers Equal Area (EPSG:5070) used for metric grid spacing.

stop("TODO(A2 grid-clean): implement grid build + point cleaning. See PLAN.md §2.1/§6-A2.")
