# Static GIS layers (bathymetry, coastline, counties) — access notes

**Purpose:** static geographic features + spatial-split groups (§8-A, §9).

## GEBCO bathymetry / coastline (no auth)
- https://download.gebco.net/ — subset the Gulf box, download grid. Used for depth and
  distance-to-shore features. `download.file()`/`httr2`.

## US Census TIGER county/region boundaries (no auth)
- https://www2.census.gov/geo/tiger/ — Florida (+ Gulf) counties. Used for GIS zoning and
  the **spatial split** (held-out counties/regions).

## Notes
- Reproject all to EPSG:5070 to match the grid. Record URL + date in
  `data/metadata/data_sources.md`.
