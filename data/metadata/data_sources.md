# Data sources (A-DOC verifies complete before M1 exit)

Every dataset must record: **source URL, date accessed, access method, auth required (Y/N),
spatial resolution, CRS, temporal coverage, license, purpose.** (PLAN.md §5)

| Dataset | Source URL | Accessed | Access method | Auth | Resolution | CRS | Coverage | License | Purpose |
|---|---|---|---|---|---|---|---|---|---|
| HABSOS *K. brevis* | NOAA NCEI HABSOS | _pending_ | manual export (in `data/raw/habsos/occurrence.txt`) | Y (portal) | point | EPSG:4326 (TBD) | TBD | NOAA open | Ground-truth labels |
| MODIS-Aqua Ocean Color L3 | NASA OB.DAAC `oceandata` | _pending_ | API (`httr2`) | Y (Earthdata) | ~4.6 km | — | 2003– | NASA open | Satellite features (chlor_a, nFLH, Kd490, SST, Rrs) |
| ERA5 wind | Copernicus CDS (`cdsapi`) | _pending_ | API, server-side bbox | Y (CDS key) | ~0.25° | EPSG:4326 | 1979– | Copernicus | Wind (mixing/transport) |
| CHIRPS precipitation | UCSB CHC | _pending_ | API, server-side bbox | N–Y | ~5 km | EPSG:4326 | 1981– | UCSB open | Rainfall/runoff proxy |
| SMAP salinity | RSS / PODAAC | _pending_ | API | Y (Earthdata) | ~40–70 km | — | 2015– | open | Stratification proxy (broad-context) |
| GEBCO bathymetry | GEBCO / NOAA | _pending_ | download | N | grid | — | static | open | Depth, distance-to-shore |
| Census TIGER counties | US Census | _pending_ | download | N | vector | EPSG:4269 | static | public domain | GIS zoning + spatial splits |

> Notes: resolution reality — MODIS ~4.6 km vs. 10 km cells (no sub-km precision). SMAP salinity
> is far coarser (broad-context only). Label/feature cadence mismatch: coarse features are
> forward/backward-filled within valid period and **flagged** (`feature_filled = TRUE`).
>
> **HABSOS schema flag (scaffolding):** the current `occurrence.txt` (Darwin Core, 12 cols) lacks
> visible coordinates/eventDate — see `reports/decisions.md`. A1/A3 must locate the geo/date
> fields (companion DwC-A files or re-pull) before labeling. Record final access details here.
