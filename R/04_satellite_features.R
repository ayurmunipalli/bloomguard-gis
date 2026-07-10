# ============================================================
# FILE: 04_satellite_features.R
# OWNER: A4 sat-features (reviewer R4)
# PURPOSE: Per cell x date MODIS features (chlor_a, nFLH, FAI, Kd490, SST + anomaly, Rrs)
#          over T-1/3/5/7/14 windows; rolling means; cloud/quality filtering.
# INPUTS:  grid (A2) + label cell-days (A3); MODIS L3 via OB.DAAC (A1 credentials).
# OUTPUTS: data/processed/satellite_features.parquet (filled rows flagged).
# TECHNIQUES: stars/terra raster clip to box; aggregate to 10 km grid; rolling stats;
#             SST monthly anomaly. STREAM-AND-DISCARD loop (mandatory, §6-A4).
# CITATIONS: NASA OB.DAAC MODIS-Aqua L3; FAI (Hu 2009); nFLH.
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): STREAM-AND-DISCARD — download one global daily file -> clip to box ->
#              aggregate to grid -> append rows -> unlink() raw. Resumable by date.
# NOTE(limitation): MODIS ~4.6 km pixels; ~4-6 per 10 km cell — no sub-km precision.
# NOTE(paper): nFLH (fluorescence) and FAI (floating-algae index) are DISTINCT — label each.
# NOTE(paper): cells with no usable imagery flagged (feature_filled=TRUE), never zero-filled.

stop("TODO(A4 sat-features): implement stream-and-discard MODIS features. See PLAN.md §6-A4/§8-A.")
