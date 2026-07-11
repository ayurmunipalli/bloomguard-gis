# grid-clean (A2) — decision & methods log

## Decisions

- **Study-area bbox** — Used 24–31°N, 87–81°W as a code-defined sf::st_bbox (no QGIS polygon
  needed) per PLAN.md §2.1 / D1. Alternatives: hand-drawn polygon clipped to 200 m isobath
  (noted as optional future refinement in PLAN.md). Chosen: rectangular bbox per Hu et al. (2022)
  for reproducibility and alignment with the mentor's gulf script. — 2026-07-11

- **Projection — EPSG:5070** — NAD83/Conus Albers Equal Area chosen for metric grid spacing.
  Cells are exactly 10 km × 10 km under this projection. Alternatives: UTM zone 17N
  (accurate for Gulf of Mexico but not equal-area across the full 24-31N extent);
  WGS84/geographic (degree-based cells → non-uniform area). EPSG:5070 matches PLAN.md D4 /
  the mentor's script. — 2026-07-11

- **Cell size — 10000 m (10 km)** — Exceeds ~4.6 km MODIS L3 pixel (true aggregation, no
  false sub-pixel precision), sits below coarse wind/salinity fields (~28 km at 0.25°).
  Locked in config.yaml / PLAN.md D4. — 2026-07-11

- **st_make_grid with square=TRUE, what="polygons"** — Produces rectangular polygons (not
  centroids), one row per cell footprint. Intersect filter retains only cells touching the
  projected study polygon (idempotent here because the bbox IS the study area, but explicit
  for maintainability). — 2026-07-11

- **Spatial cluster method — Queen contiguity via st_relate DE-9IM "****1****"** — Queen
  contiguity (shared edge OR corner) is more conservative than Rook (edge only): more
  adjacent cells are grouped together, giving larger, safer held-out spatial folds.
  Union-find / BFS over the resulting adjacency gives connected components. For this
  rectangular tile grid the entire grid is one connected component (n_clusters=1), which
  means A7/A11 must use geographic sub-region groupings (by grid quadrant or county
  intersection) rather than connected-component IDs for spatial splits. Flagged for A7. — 2026-07-11

- **Point-to-cell join deferred** — Current data/raw/habsos/occurrence.txt lacks
  decimalLatitude / decimalLongitude / eventDate. Per PLAN.md §0 / decisions.md, coordinates
  must not be fabricated. Implemented points_to_cells() in utils_spatial.R; blocked pending A1
  delivering geocoded HABSOS. — 2026-07-11

## Data sources used

- **HABSOS occurrence.txt** — data/raw/habsos/occurrence.txt — Darwin Core Accident export,
  190,339 rows, dated Sep 30 2022 on disk — no lat/lon/eventDate — blocked for point-clean
  step; coordinates gap documented in manual_downloads.md and decisions.md.
- No additional external data pulled in this script (grid is built from config values alone).

## Methods & techniques

- **sf::st_bbox → st_as_sfc** — build_study_grid() in utils_spatial.R — converts the
  config.yaml bbox values into an sf sfc POLYGON in WGS84 before reprojection.
  Citation: Pebesma (2018).

- **sf::st_transform to EPSG:5070** — build_study_grid() — reprojects study polygon
  to Albers Equal Area before tiling. Ensures metric cell size. Citation: EPSG:5070.

- **sf::st_make_grid(cellsize=10000, what="polygons", square=TRUE)** — build_study_grid()
  — tiles the projected extent into 10 km × 10 km polygon cells. Mentor's gulf script method
  (Green 2022). Parameters: cellsize from config.yaml; square=TRUE enforces rectangular grid
  (appropriate for risk-layer display); whole grid retained (bbox IS study area).

- **Queen contiguity via st_relate DE-9IM** — flag_spatial_clusters() in utils_spatial.R —
  adjacency matrix for connected-component labeling. Union-find with path compression.
  Used by A7/A11 for grouped spatial splits (R-SPLIT check). Novel / mentor's method.

- **st_join with st_intersects** — points_to_cells() in utils_spatial.R — maps each
  point to its containing grid cell; drops points outside the study area (left=FALSE).
  Datetime reduced to date; per-cell × date aggregation via data.table grouped summary.
  Pattern: mentor's gulf script. Citation: Pebesma (2018).

- **renv::snapshot()** — locked sf 1.1-1, s2 1.1.11, units 1.0-1, yaml 2.3.12,
  data.table 1.18.4, arrow 24.0.0, plus dependency tree. renv.lock updated.

## Open questions / caveats / limitations

- **HABSOS coordinates gap (BLOCKER for point-clean):** occurrence.txt has no spatial or
  temporal fields. A1 must either locate the DwC-A companion files (verbatim.txt /
  event.txt) or re-export from the HABSOS portal with lat/lon/date. points_to_cells() is
  ready to ingest those columns once A1 delivers them. Downstream: A3 (habsos-label)
  cannot run until this is resolved.

- **Single connected component:** The 4743-cell rectangular grid forms one Queen-contiguity
  cluster. A7/A11 must implement spatial splits by assigning cells to geographic sub-regions
  (e.g., by grid quadrant or county intersection) rather than relying on spatial_cluster
  alone. spatial_cluster column retained in the grid for downstream use.

- **200 m isobath refinement:** PLAN.md notes as optional — intersecting the bbox with
  the 200 m isobath would drop offshore deep-water cells that are unlikely to host K. brevis
  blooms. If retained deep-water cells degrade model performance (A7 evaluation), A2 can
  re-run with isobath clipping. Not done at MVP stage; bathymetry data not yet pulled (A5).

- **Cell centroid lat/lon not exported:** centroids (in WGS84) are useful as static features
  for A5 (distance-to-coast, distance-to-river-mouth). A5 can derive them via
  sf::st_centroid + st_transform(4326) on the grid file.

## Verification output (from 02_build_grid.R run 2026-07-11)

```
[build_study_grid] n_cells=4743  cellsize=10000 m  crs=EPSG:5070
Grid: 4743 cells  (expected ~4600-5200 for the 24-31N/87-81W box)
PASS: grid fully covers the study-area bbox.
PASS: grid CRS = EPSG:5070.
[flag_spatial_clusters] n_cells=4743  n_clusters=1
WRITTEN & VERIFIED: data/processed/study_area_grid.gpkg  (4743 cells, EPSG:5070)
```

Output file: `data/processed/study_area_grid.gpkg` — 1.1 MB — columns: cell_id (int),
spatial_cluster (int), geometry (Polygon, EPSG:5070).
