# ============================================================
# FILE: 09_gis_export.R
# OWNER: A9 gis (M2)
# PURPOSE: Apply best model per cell -> risk-FORECAST layers; build the intra-cell attention
#          drill-down (diagnostic feature concentration, D12/§2.3 — NOT a sub-cell forecast).
# INPUTS:  best model (Stage-1 first) + feature pipeline + native ~4 km rasters for mapped
#          date(s) + static sub-km layers (bathymetry, distance-to-coast).
# OUTPUTS: outputs/gis/hab_risk_grid.gpkg; hab_risk_raster.tif; priority_monitoring_zones.gpkg;
#          outputs/gis/intracell_attention.gpkg; outputs/maps/hab_risk_map.html.
# TECHNIQUES: tmap/leaflet; per-cell prediction; re-derive native pixels for mapped dates;
#             convergence highlight (elevated pixel ∩ shallow/nearshore static context).
# CITATIONS: tmap (Tennekes 2018); leaflet.
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): every map labeled a model FORECAST at horizon H (states which model), not
#              observed blooms. Drill-down labeled "where flagging conditions concentrate"
#              (diagnostic), never a sub-cell risk score; nothing rendered below native ~4 km.
# NOTE(limitation): long-horizon maps carry the precursor-drift caveat (§2.3).

stop("TODO(A9 gis): implement risk maps + intra-cell drill-down. GATE: needs validated A7 model. §6-A9.")
