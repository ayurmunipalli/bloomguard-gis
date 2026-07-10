# ============================================================
# FILE: utils_spatial.R
# OWNER: shared (A2 seeds; used across A2/A4/A5/A6/A9)
# PURPOSE: Shared spatial helpers — CRS constants, bbox->grid, point->cell join,
#          adjacency/spatial-cluster flags for grouped splits.
# INPUTS:  config.yaml (via 00_config.R).
# OUTPUTS: functions only (sourced, no side effects).
# TECHNIQUES: sf reprojection; st_make_grid; st_contains/st_join; poly adjacency.
# CITATIONS: sf (Pebesma 2018).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# Placeholder for shared helpers; A2 fills these first, others reuse.
# e.g. build_study_grid(), points_to_cells(), flag_spatial_clusters()

message("utils_spatial.R loaded (helpers to be implemented by A2).")
