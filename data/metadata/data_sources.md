# Data sources (A-DOC verifies complete before M1 exit)

Every dataset must record: **source URL, date accessed, access method, auth required (Y/N),
spatial resolution, CRS, temporal coverage, license, purpose.** (PLAN.md §5)

_Last updated: 2026-07-11 (A-DOC initial seeding pass). Fields marked **TBD by A1/A5** are
pending the agent's confirmed pull — do not fill with guesses._

| Dataset | Source URL | Accessed | Access method | Auth | Resolution | CRS | Coverage | License | Purpose |
|---|---|---|---|---|---|---|---|---|---|
| HABSOS *K. brevis* DwC-A v1.5 **[STALE MIRROR — still the source of every frozen number]** | https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5 (GBIF/OBIS IPT, published by **USGS**, not NOAA) | **2026-07-11** (A3); version re-checked **2026-07-17** (M4-1) — **still v1.5, published 2022-09-30, nothing newer** | DwC-A zip download; no auth | N (public) | Point samples | EPSG:4326 | **1953-08-19 to 2022-01-11** (190,341 event rows; 169,871 in study bbox). **CORRECTED 2026-07-17:** this row previously read "to 2021-12-31" — the archive actually carries 12 records in Jan 2022 (`max(eventDate) = 2022-01-11T23:23:00Z`). The frozen labels stop at 2021-12-31 because the pipeline's own window does, not because the archive does. | CC0 (per EML) | Ground-truth labels (binary HAB > 100k cells/L); 94,810 cell-day rows; 7,523 positive (7.93%) — **reproduced exactly by `R/01c_habsos_overlap_audit.R` on 2026-07-17** |
| HABSOS *K. brevis* **live (NCEI)** — **PULLED, NOT ADOPTED** | https://gis.ncdc.noaa.gov/arcgis/rest/services/ms/HABSOS_CellCounts/MapServer/0 (landing: https://www.ncei.noaa.gov/products/harmful-algal-blooms-observing-system) | **2026-07-17** (M4-1) | ArcGIS REST paginated query (`resultOffset`/`resultRecordCount`=2000, `orderByFields=OBJECTID ASC`), R `curl`; serial + exponential backoff (PLAN.md §12 carve-out); `R/01b_pull_habsos_ncei.R` | **N (open — no auth)** | Point samples | LAT/LON fields EPSG:4326 (SHAPE is EPSG:3857) | **1953-08-19 to 2026-07-09**; 220,979 records; **n_expected = n_retrieved = 220,979, 0 duplicate OBJECTID, 0 gaps** | Public domain / CC0 (NOAA NCEI) | **NOT WIRED INTO ANY MODEL.** Fails the M4-2 overlap gate: does not reproduce the frozen population (173,232 in bbox / 95,430 cell-days / **7,475 positive / 7.83%** vs 169,871 / 94,810 / 7,523 / 7.93%); **9.7% of frozen 2016+ test cell-days are absent from it**; 67 HAB label flips. Carries `WATER_TEMP` (48.8% non-null), `SALINITY` (49.5%), `SAMPLE_DEPTH` (99.6%) — Arm B in-situ candidates the DwC-A lacks; `WIND_SPEED`/`WIND_DIR` exist but are **0.0% populated**. Record starved 2021-07→2023-12. See `reports/results/M4-2_overlap_audit.md`. |
| MODIS-Aqua Ocean Color L3M | https://oceandata.sci.gsfc.nasa.gov/ | **2026-07-11 (A4 FINAL)** | OB.DAAC file-search API + R `curl` package (netrc+cookie OAuth); stream-and-discard per-day loop; 4 products downloaded per date | Y (Earthdata ~/.netrc) | ~4.6 km (4 km L3m product) | EPSG:4326 native → reprojected to EPSG:5070 via `terra::project()` (bilinear) | 2003-01-01 to 2021-12-31 (**5,829/5,829 HABSOS dates fully processed — FINAL**) | NASA open | chlor_a (CHL DOI: 10.5067/AQUA/MODIS/L3M/CHL/2022.0), nFLH (FLH DOI: 10.5067/AQUA/MODIS/L3M/FLH/2022.0), Kd_490 (KD DOI: 10.5067/AQUA/MODIS/L3M/KD/2022.0), SST daytime (SST DOI: 10.5067/AQUA/MODIS/L3M/SST/2019.0). Output: `data/processed/satellite_features.parquet`. **satellite_missing=0; sat_IS_PLACEHOLDER=0; cloud_flag=TRUE 45.7% (30,135 rows); chlor_a NA 66.7% (43,991 rows) — real cloud/quality masking, not zeros.** |
| ERA5 10m wind | https://cds.climate.copernicus.eu/ | **2026-07-13 (A5; REAL)** | Copernicus CDS API (`ecmwfr`, dataset `derived-era5-single-levels-daily-statistics`); per-(year,month) requests, server-side bbox area=[31,-87,24,-81]; bilinear-extracted to cell centroids; checkpointed/resumable | Y (~/.cdsapirc) | ~0.25° (~28 km) native, bilinear to 10 km cells | EPSG:4326 | 2003-01-01 to 2021-12-31 (65,939/65,939 satellite-era rows — FINAL; wind_is_placeholder=FALSE) | Copernicus License v1.2 (open) | Wind speed, direction, u/v, along-shore/cross-shore components (shoreline azimuth 350°NNW); mixing/transport features (PLAN.md §8-A); DOI: 10.1002/qj.3803 |
| CHIRPS v2.0 precipitation | https://data.chc.ucsb.edu/products/CHIRPS-2.0/ | **PLACEHOLDER** (403 CrowdSec ban re-confirmed on retry; A5 2026-07-12/13) | terra vsicurl streaming designed (no local copy); HTTP 403 "CrowdSec Ban" from CHC server on both the initial pull and a same-session retry; checkpoint-resumable; no auth needed; instructions in data/raw/weather/manual_downloads.md | N | ~0.05° (~5 km) | EPSG:4326 | 1981–present | UCSB open | Rainfall/runoff proxy (prior 3/7/14 days); DOI: 10.1038/sdata.2015.66 |
| SMAP RSS L3 SSS v5.0 | https://podaac.jpl.nasa.gov/ | **PLACEHOLDER** (OPeNDAP auth deferred; A5 2026-07-11) | PODAAC CMR search + OPeNDAP download; Earthdata netrc auth; complex CMR query deferred; salinity_is_placeholder=TRUE; salinity_coarse_flag=TRUE ALL rows; instructions in data/raw/weather/manual_downloads.md | Y (Earthdata ~/.netrc) | ~40–70 km (sensor footprint; far coarser than 10 km grid) | EPSG:4326 | 2015-04-01 to present (no salinity for pre-2015 labels) | NASA/RSS open | Stratification proxy (**broad-context only**; salinity_coarse_flag=TRUE on all rows); cite Meissner et al. 2018 DOI: 10.3390/rs10071121 (Remote Sensing 10(7):1121; CORRECTED — A5 script had wrong DOI 10.3389/fmars.2018.00349 which resolves to a coral reef paper) |
| GEBCO 2026 bathymetry | https://download.gebco.net/ | **2026-07-11** (A5; REAL) | GEBCO queue API POST/poll/download (no auth); Gulf subset 24–31°N 87–81°W; GeoTIFF; ~5 MB | N | ~450 m (15 arc-sec) | EPSG:4326 → EPSG:5070 via terra bilinear | Static | **NON-COMMERCIAL (GEBCO ToU)** — same restriction as MEOW; confirm with venue | Depth per cell (depth_m range –3,539 to +95 m; 24 edge NAs); DOI: 10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f |
| Census TIGER 2023 | https://www2.census.gov/geo/tiger/TIGER2023/ | **2026-07-11** (A5; REAL) | Direct download (no auth); county zip ~83 MB + coastline zip | N | Vector | EPSG:4269 native → EPSG:5070 | Static (2023 vintage) | Public domain (US Gov) | County polygons → spatial_block_tiger (82 blocks for spatial CV, Lead Directive 2026-07-11); coastline → dist_to_shore_m (17 m–429 km) |

---

## Notes

**Resolution reality check** (PLAN.md §5):
- MODIS ~4.6 km pixels vs. 10 km cells: a cell spans only ~4–6 pixels. No sub-pixel precision.
- SMAP salinity ~40–70 km: far coarser than the grid — flag as broad-context in all outputs.
- ERA5 wind ~0.25° (~28 km): interpolated to cell centers where needed; note in methods.

**Label/feature cadence mismatch** (PLAN.md §5):
Features arriving at coarser-than-daily cadence are forward/backward-filled within their valid
period. Filled rows must be flagged (`feature_filled = TRUE`). Never let a fill masquerade as
an observation.

**HABSOS schema gap — RESOLVED (2026-07-11)**:
A3 obtained full DwC-A v1.5 from GBIF/OBIS IPT. `event.txt` carries `decimalLatitude`,
`decimalLongitude`, `eventDate`. Join key: `event.txt$id = occurrence.txt$eventID`.
See `reports/agent_logs/habsos-label.md` for full details.

**Auth credentials** (never committed):
- NASA Earthdata: `~/.netrc` (`machine urs.earthdata.nasa.gov login <user> password <pw>`)
- Copernicus CDS: `~/.cdsapirc`
- Never store credentials in the repo or in any script.

---

## Sources logged by A1 sourcing (corrected 2026-07-11 per A-DOC audit)

_Original A1 table had 11 incorrect fields (guesses, not confirmed values). Corrected below
to match the authoritative primary table (A3/A4/A5 confirmed). Corrections noted inline._

| Dataset | Source URL | Access method | Auth? | Resolution | Temporal | License | Purpose |
|---|---|---|---|---|---|---|---|
| HABSOS K.brevis DwC-A v1.5 | https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5 | DwC-A zip download (curl); no auth | No | Point samples | 1953-08-19 to 2021-12-31 | **CC0** (per EML) [was: CC BY 4.0 — corrected per A3] | Ground-truth labels |
| MODIS-Aqua L3m daily CHL/FLH/KD/SST | https://oceandata.sci.gsfc.nasa.gov/ (OB.DAAC file_search API) | **curl + netrc+cookie OAuth** (stream-and-discard per A4) [was: httr2 Bearer token — corrected per A4] | Yes (Earthdata ~/.netrc) | **~4.6 km (4 km L3m product)** [was: ~9 km — corrected per A4] | 2003-01-01 to 2021-12-31 | NASA open | Satellite features (4 products; stream-and-discard in A4) |
| SMAP RSS L3 SSS v5.0 | https://archive.podaac.earthdata.nasa.gov/ (CMR search) | **PODAAC CMR search + OPeNDAP; Earthdata netrc auth** [was: httr2 Bearer token — deferred to A5] | Yes (Earthdata ~/.netrc) | ~40–70 km | 2015–present | NASA/RSS open | Salinity broad-context (PLACEHOLDER per A5; salinity_is_placeholder=TRUE) |
| CHIRPS v2.0 | https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/ | terra vsicurl streaming (designed); **PLACEHOLDER — HTTP 403 CrowdSec block as of 2026-07-11** [was: presented as accessible — corrected per A5] | No | ~0.05° (~5 km) | 1981–present | UCSB open | Precipitation (placeholder until 403 resolves) |
| ERA5 single levels | https://cds.climate.copernicus.eu/api | CDS API v3; server-side bbox; **PLACEHOLDER — no ~/.cdsapirc** | Yes (CDS key ~/.cdsapirc) | ~0.25° (~28 km) | **1979–present** [was: 1940–present — corrected per A5] | **Copernicus License v1.2 (open)** [was: CC BY 4.0 — corrected per A5] | Wind u/v, precipitation |
| GEBCO **2026** bathymetry | https://download.gebco.net/ | **Queue API (automated POST/poll/download)** [was: Manual JS portal — corrected per A5] | No | ~450 m (15 arc-sec) | Static | **NON-COMMERCIAL (GEBCO ToU)** [was: CC BY 4.0 — CRITICAL correction per A5] | Bathymetry; depth_m; dist_to_shore |
| US Census TIGER **2023** | https://www2.census.gov/geo/tiger/TIGER2023/ | Direct download (no auth) [was: TIGER2020 URL — corrected per A5] | No | Vector | Static (2023 vintage) | Public domain | County polygons; spatial CV blocks |

---

## A-DOC reconciliation: A1 table vs. confirmed values (2026-07-11; corrected by A1 2026-07-11)

**The primary table at the top of this file is authoritative.** A1's original table reflected
planning-time metadata; fields below were confirmed by A3/A4/A5 who actually pulled and
inspected the data. A1 table above has been corrected to match. **Use the primary table for
all manuscript, methods, and citation purposes.**

| Field | A1 originally logged | Confirmed (authoritative) | Source | Status |
|---|---|---|---|---|
| HABSOS license | CC BY 4.0 | **CC0** (from DwC-A EML metadata) | A3 2026-07-11 | Corrected in A1 table |
| MODIS resolution | ~9 km | **~4.6 km (4 km L3m product)** | A4 2026-07-11 | Corrected in A1 table |
| MODIS auth method | httr2 Bearer token | **curl + netrc+cookie OAuth** | A4 2026-07-11 | Corrected in A1 table |
| GEBCO version | GEBCO 2024 | **GEBCO 2026** | A5 2026-07-11 | Corrected in A1 table |
| GEBCO license | CC BY 4.0 | **NON-COMMERCIAL (GEBCO ToU)** — same restriction as MEOW | A5 2026-07-11 | Corrected in A1 table |
| GEBCO access | Manual (JS portal) | **Queue API (automated POST/poll/download)** | A5 2026-07-11 | Corrected in A1 table |
| Census TIGER vintage | TIGER 2020 | **TIGER 2023** | A5 2026-07-11 | Corrected in A1 table |
| ERA5 license | CC BY 4.0 | **Copernicus License v1.2 (open)** | A5 2026-07-11 | Corrected in A1 table |
| ERA5 temporal | 1940–present | **1979–present** | A5 2026-07-11 | Corrected in A1 table |
| CHIRPS status | presented as accessible | **PLACEHOLDER (HTTP 403 CrowdSec block)** | A5 2026-07-11 | Corrected in A1 table |
| SMAP auth method | httr2 Bearer token | **PODAAC CMR + OPeNDAP; netrc auth** | A5 2026-07-11 | Corrected in A1 table |

