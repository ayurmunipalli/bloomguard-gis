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
