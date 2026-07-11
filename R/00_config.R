# ============================================================
# FILE: 00_config.R
# PURPOSE: Central config loader + shared constants/paths for the pipeline.
#          Sourced first by every other R script. Reads config.yaml (PLAN.md §2).
# INPUTS:  config.yaml
# OUTPUTS: `cfg` list in the calling environment; helper paths.
# TECHNIQUES: yaml config, project-root resolution.
# CITATIONS: none (infrastructure).
# ============================================================

# NOTE(paper): all pinned decisions (study box, cell size, threshold, horizons,
#              trend windows, splits) live in config.yaml so the write-up cites one source.

# ── ARROW SINGLE-THREAD GUARD ────────────────────────────────────────────────
# CRITICAL: arrow::read_parquet deadlocks in multi-threaded mode on this
# machine (observed: 7 R processes stuck at 95% CPU for 15h reading parquets).
# Set the env var BEFORE library(arrow) loads so the C++ thread pool is
# initialised at 1. arrow::set_cpu_count(1L) is also called in each script
# that loads arrow, as belt-and-suspenders. A7 and all downstream scripts
# inherit this via sourcing 00_config.R.
# NOTE(paper): This is a host-specific workaround, not a model choice.
Sys.setenv(ARROW_NUM_THREADS = "1")

suppressWarnings(suppressMessages({
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' required. Install via renv::restore() or install.packages('yaml').")
  }
}))

# Resolve project root (dir containing config.yaml), robust to sourced-from location.
.find_project_root <- function(start = getwd()) {
  d <- normalizePath(start, mustWork = FALSE)
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "config.yaml"))) {
    stop("config.yaml not found above ", start)
  }
  d
}

PROJECT_ROOT <- .find_project_root()
cfg <- yaml::read_yaml(file.path(PROJECT_ROOT, "config.yaml"))

# Convenience: absolute path from a repo-relative path.
proj_path <- function(...) file.path(PROJECT_ROOT, ...)

# Reproducibility
set.seed(cfg$random_seed %||% 42)

# tiny null-coalesce
`%||%` <- function(a, b) if (is.null(a)) b else a

message("Loaded config for: ", cfg$project$name,
        " | grid ", cfg$grid$cellsize_m, "m | horizons ",
        paste(cfg$forecast$horizons_days, collapse = ","))
