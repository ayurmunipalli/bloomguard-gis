# ============================================================
# FILE: 05_environmental_features.R
# OWNER: A5 env-features (reviewer R5)
# PURPOSE: Per cell x date environmental + static-geographic features.
# INPUTS:  grid + labels + satellite features; ERA5 wind, CHIRPS precip, SMAP salinity,
#          GEBCO bathymetry, coastline, Census counties (from A1).
# OUTPUTS: data/processed/environmental_features.parquet (one row per cell-day).
# TECHNIQUES: wind speed/dir + along/cross-shore components; precip 3/7/14-day history +
#             heavy-rain flag; distance-to-shore/river; bathymetry; month + doy sin/cos.
#             Server-side bbox for ERA5/CHIRPS. Coarse features flagged broad-context.
# CITATIONS: Copernicus ERA5; UCSB CHIRPS; RSS/PODAAC SMAP; GEBCO; US Census TIGER.
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(limitation): SMAP salinity ~40-70 km — broad-context feature only, flag it.
# NOTE(paper): coarser-than-daily features forward/backward-filled within valid period
#              and flagged (feature_filled=TRUE) — never silently masqueraded as observed.

stop("TODO(A5 env-features): implement environmental/static features. See PLAN.md §6-A5/§8-A.")
