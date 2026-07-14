# Methods log (A-DOC — harvested)

A-DOC maintains this file. It harvests `NOTE(paper)`, `NOTE(cite)`, and `NOTE(limitation)`
tags from every script plus the per-agent decision logs in `reports/agent_logs/*.md`, and
records each technique the project uses with the citation the author will use to explain it.
Feeds `paper/source_set.md`.

Format per entry:
`<technique> — <where used (file/function)> — <parameters> — <citation or "novel/mentor's method">`

_Last harvested: 2026-07-11. Scripts 03–09 are stubs (stop("TODO...")); entries for those
agents will be added as work lands._

---

## Data

- **Config-driven design constants** — `R/00_config.R` / `config.yaml` — study bbox,
  cellsize, label threshold, horizons H, trend windows, random seed — "project design;
  config.yaml is the single-source of truth for all pinned parameters (D0–D12)"
  — NOTE(paper) from `R/00_config.R` (2026-07-11)

- **API-preferred data sourcing** — `R/01_source_data.R` — all datasets where API exists;
  manual export only as fallback — "project rule (author's standing instruction, PLAN.md §5)"
  — NOTE(paper) from `R/01_source_data.R` (2026-07-11)

- **MODIS stream-and-discard** — `R/04_satellite_features.R` **(implemented A4 2026-07-11)**
  — per-day loop: download 4 global ~13 MB files per product → `terra::crop()` to bbox →
  `terra::project()` bilinear EPSG:4326→EPSG:5070 → `terra::zonal()` mean + valid-count →
  append Parquet → `unlink()` all 4 raw files. Peak disk ≈ 60 MB (4 files simultaneously).
  Resumable: checkpoint reads existing Parquet at startup, skips done dates.
  Date scope: 5,829 unique HABSOS sample dates (2003-01-01 to 2021-12-31).
  — `\cite{modis_obdaac_chl}`, `\cite{modis_obdaac_nflh}`, `\cite{modis_obdaac_kd490}`,
  `\cite{modis_obdaac_sst}` — NOTE(paper)/NOTE(cite) from `R/04_satellite_features.R`
  (harvested 2026-07-11)

- **MODIS product selection (CHL, SST, FLH, KD)** — `R/04_satellite_features.R` —
  4 daily L3m products at 4 km chosen over 9 km (10 km cells span only ~1 pixel at 9 km;
  4 km gives ~4–6 pixels/cell for meaningful aggregation). FAI excluded: requires MODIS
  bands at 859 nm and 1240 nm NOT available in OB.DAAC L3m; would need L2 swath processing.
  nFLH retained as L3m fluorescence proxy. SST daytime product chosen over night SST4
  (higher Gulf coverage; slightly higher aerosol uncertainty acceptable at this scale).
  — NOTE(paper)/NOTE(limitation) from `R/04_satellite_features.R` (2026-07-11)

- **Feature cadence forward/backward fill** — `R/04_satellite_features.R` (A4 sets
  `feature_filled = FALSE` on all output rows); fill logic handled by A6 datacube
  (`feature_filled = TRUE` set during gap-fill) — "PLAN.md §5 cadence mismatch note"

- **TIGER county assignment → spatial_block_tiger (THE spatial-CV grouping)** —
  `R/05_environmental_features.R` (implemented A5 2026-07-11) —
  `sf::st_join(join=st_intersects)` assigns each cell centroid to a county; ocean cells
  (no intersection) reassigned via `sf::st_nearest_feature()`. Produces `spatial_block_tiger
  = state_fips + "_" + county_fips` (e.g. "12_087"). 82 unique blocks across 4,743 cells.
  Per Lead Directive 2026-07-11: ALL spatial cross-validation splits in A6/A7/A11 use
  these county blocks (Queen-contiguity cannot be used — single component). Output:
  `static_geo.parquet` column `spatial_block_tiger`.
  — `\cite{census_tiger}` (TIGER 2023, public domain) — NOTE(paper)/NOTE(cite) from
  `R/05_environmental_features.R` (harvested 2026-07-11)

- **Distance-to-shore (static; TIGER coastline)** — `R/05_environmental_features.R`
  Section C — `sf::st_distance(st_centroid(grid), st_union(coast_5070))` in EPSG:5070
  (Albers Equal Area metric projection). Returns meters from each of the 4,743 cell
  centroids to the nearest US coastline segment. Observed range: 17 m to 429 km.
  — `\cite{census_tiger}` — NOTE(paper) from `R/05_environmental_features.R` (2026-07-11)

- **GEBCO 2026 bathymetric depth (static)** — `R/05_environmental_features.R` Section B
  — GEBCO 2026 grid (~450 m / 15 arc-second) downloaded via POST to GEBCO FastAPI queue
  endpoint (`download.gebco.net/api/queue`; no auth; Gulf bbox), poll status, download
  GeoTIFF zip. `terra::project()` bilinear to EPSG:5070, then
  `terra::extract(fun="mean", na.rm=TRUE)` per cell. Observed depth range: −3,539 to
  +95 m (negative = below sea level). 24 edge cells have NA (peripheral bbox coverage).
  — `\cite{gebco2026}` — NOTE(paper)/NOTE(cite) from `R/05_environmental_features.R`
  (harvested 2026-07-11)

- **Seasonality encoding (always real, never placeholder)** — `R/05_environmental_features.R`
  Section G — month (integer 1–12), day-of-year `doy` (1–365/366),
  `doy_sin = sin(2π × doy/365)`, `doy_cos = cos(2π × doy/365)`. Circular sin/cos pair
  jointly encodes position in the annual cycle (no discontinuity at Dec 31 → Jan 1).
  Captures K. brevis bloom season (Aug–Oct peak on WFS). Computed from date alone;
  no external data required.
  — Standard time-series seasonality encoding; no specific external citation needed —
  NOTE(paper) from `R/05_environmental_features.R` (2026-07-11)

- **IS_PLACEHOLDER per-feature flag schema** — `R/05_environmental_features.R` —
  Per-family placeholder flags: `wind_is_placeholder`, `precip_is_placeholder`,
  `salinity_is_placeholder`. Master `IS_PLACEHOLDER = TRUE` only when ALL three are TRUE.
  `salinity_coarse_flag = TRUE` on ALL salinity rows (independent of placeholder status).
  `feature_filled = FALSE` in A5 output; set to TRUE by A6 during forward/backward fill.
  Schema held constant even when data absent so A6 can wire against correct column names.
  — PLAN.md §5 placeholder guardrail — NOTE(paper) from `R/05_environmental_features.R`
  (2026-07-11)

- **ERA5 wind (PLACEHOLDER — no ~/.cdsapirc)** — `R/05_environmental_features.R` Section E
  — Placeholder: wind_u_ms / wind_v_ms / wind_speed_ms / wind_dir_deg all NA;
  `wind_is_placeholder = TRUE`. Along-shore and cross-shore components (WFS shoreline
  orientation ≈ 350° NNW) not yet computed. Pull instructions in
  `data/raw/weather/manual_downloads.md`.
  — `\cite{hersbach2020era5}` — NOTE(limitation) from `R/05_environmental_features.R`
  (2026-07-11)

- **CHIRPS precipitation (PLACEHOLDER — 403 CrowdSec block)** — `R/05_environmental_features.R`
  Section D — vsicurl streaming approach designed (`terra::rast("/vsigzip//vsicurl/https://...")`)
  and tested; CHC UCSB server returned HTTP 403 (CrowdSec bot-detection). Placeholder:
  `precip_mm = NA`, `precip_is_placeholder = TRUE`. Checkpoint-resumable; re-run after
  block clears (~24 h) or from different IP. Pull instructions in
  `data/raw/weather/manual_downloads.md`.
  — `\cite{funk2015chirps}` — NOTE(limitation) from `R/05_environmental_features.R`
  (2026-07-11)

- **SMAP sea-surface salinity (PLACEHOLDER — deferred; coarse flag always TRUE)** —
  `R/05_environmental_features.R` Section F — OPeNDAP/CMR query deferred (complex auth
  flow); placeholder: `salinity_pss = NA`. `salinity_coarse_flag = TRUE` on ALL rows
  unconditionally (SMAP footprint 40–70 km far coarser than 10 km grid). Coverage window:
  2015-04-01 to present; earlier dates have no salinity. Pull via
  PODAAC CMR + OPeNDAP with Earthdata auth (`~/.netrc`); instructions in
  `data/raw/weather/manual_downloads.md`.
  — `\cite{meissner2018smap}` — NOTE(limitation) from `R/05_environmental_features.R`
  (2026-07-11)

- **Pre-2003 label exclusion** — `R/06_build_datacube.R` Step 2 **(implemented A6 2026-07-11)**
  — explicit filter `labels_raw[sample_date >= 2003-01-01]`; drops 28,871 of 94,810
  label rows (30.5%). Pre-2003 records preserved in `habsos_labels.parquet` (A3 decision)
  but excluded from model training because MODIS-Aqua L3m reliable daily coverage
  begins 2003-01-01; joining them would yield 100% NA satellite columns.
  — NOTE(paper)/NOTE(limitation) from `R/06_build_datacube.R` (2026-07-11)

- **Feature-centric row space (T = HABSOS sample date)** — `R/06_build_datacube.R`
  **(implemented A6 2026-07-11)** — 65,939 base rows, one per HABSOS observation cell-day
  at feature date T = `sample_date` (post-2003). Features joined at T. Forecast label for
  horizon H retrieved via self-join at T+H. Label = NA when no HABSOS observation at T+H
  (not assumed negative). Design maximises feature coverage: both satellite_features and
  environmental_features are keyed on HABSOS observation dates. Alternative (label-centric
  T = label_date − H) was rejected because env_features is only at HABSOS dates.
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **Wide-format cube (HAB_H1…H14)** — `R/06_build_datacube.R` **(implemented A6 2026-07-11)**
  — one row per (cell_id, T) with 5 forecast target columns: `HAB_H1`, `HAB_H3`, `HAB_H5`,
  `HAB_H7`, `HAB_H14`. Avoids 5× row inflation; A7 selects labelled subset per horizon
  with `!is.na(HAB_Hk)`. Transformer (A11) can reshape to long format or use wide directly.
  Label availability: H=1 7,791 rows (12.3% pos); H=3 4,765 (14.4%); H=5 6,151 (13.2%);
  H=7 23,751 (8.4%); H=14 23,889 (7.9%). Short-horizon sparsity reflects low
  consecutive-day HABSOS resampling frequency.
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **IS_PLACEHOLDER_ROW composition flag** — `R/06_build_datacube.R` Step 7
  **(implemented A6 2026-07-11)** — master honesty flag: TRUE when `satellite_missing OR
  env_IS_PLACEHOLDER OR static_IS_PLACEHOLDER`. In DRAFT cube: 100% TRUE (env dynamic
  features all placeholder via A5). Use per-source flags (`sat_IS_PLACEHOLDER`,
  `env_IS_PLACEHOLDER`, `static_IS_PLACEHOLDER`) for finer-grained source attribution.
  A7 uses as diagnostic; do not hard-filter on IS_PLACEHOLDER_ROW in DRAFT (real features
  — satellite level/trends, seasonality, geography — are usable when satellite_missing=FALSE).
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **Historical HAB lag features** — `R/06_build_datacube.R` Step 4
  **(implemented A6 2026-07-11)** — `hab_any_prior_7d` and `hab_any_prior_14d`: integer
  (0/1), 1 when any HAB=1 HABSOS observation exists for the same cell in [T-lag, T) (strict
  less-than prevents self-leakage with same-day HAB). Captures temporal autocorrelation at
  cell level. Based solely on HABSOS sampling dates — absence of prior observation ≠ prior
  non-bloom.
  — NOTE(paper)/NOTE(limitation) from `R/06_build_datacube.R` (2026-07-11)

- **Datacube FINAL status** — `data/processed/model_dataset.parquet` **(FINAL — full MODIS
  2003–2021)** — 65,939 rows × 114 cols, 12.78 MB. Satellite coverage: **100%** (5,829 of
  5,829 HABSOS dates). `satellite_missing=0`; `sat_IS_PLACEHOLDER=0`. `cloud_flag=TRUE` for
  30,135 rows (45.7%) — real Gulf cloud cover, not a data error. `chlor_a` NA for 43,991
  rows (66.7%) — cloud/quality mask applied honestly. `IS_PLACEHOLDER_ROW=TRUE` for all
  65,939 rows (100%) — env dynamic features ERA5/CHIRPS/SMAP still placeholder per A5;
  satellite features are real. 36 of 82 TIGER county blocks represented among 1,461 label
  cells.
  — NOTE(limitation) updated DRAFT→FINAL from `reports/agent_logs/datacube.md` (2026-07-11)

- **Memory guard: satellite pre-filter to label cells** — `R/06_build_datacube.R`
  **(implemented A6 final run 2026-07-11)** — `sat_raw` filtered to `cell_id %in%
  label_cells` (1,461 of 4,743 cells) before trend computation. Reduces satellite table
  from 27,641,118 → 8,516,169 rows (27.6 M × 74 cols × 8 bytes ≈ 16.3 GB would exceed
  16 GB R limit). Each retained cell keeps its full 5,829-date temporal series, so trailing
  OLS slopes and rolling statistics are computed over the complete record. Trend correctness
  verified by R6 review.
  — NOTE(paper) from `reports/agent_logs/datacube.md` (2026-07-11)

---

## Methods

- **Study-area bounding box definition** — `R/02_build_grid.R` (`build_study_grid()` in `utils_spatial.R`)
  — `sf::st_bbox()` → `st_as_sfc()` in EPSG:4326; 24–31°N, 87–81°W — `\cite{hu2022karenia}` (defines
  this extent) — NOTE(paper) from `R/02_build_grid.R` (2026-07-11)

- **Albers Equal Area reprojection** — `R/02_build_grid.R` (`build_study_grid()`) — `sf::st_transform(crs = 5070)`;
  EPSG:5070 NAD83 CONUS Albers — USGS standard CONUS Albers (EPSG registry) — NOTE(cite) from
  `R/02_build_grid.R` (2026-07-11)

- **Regular 10 km grid construction** — `R/02_build_grid.R` (`build_study_grid()`) —
  `sf::st_make_grid(cellsize = 10000, what = "polygons", square = TRUE)` in EPSG:5070; `cell_id`
  per cell; 4,743 cells produced — `\cite{green2022rtm}` (mentor's RTM gridding); `\cite{pebesma2018sf}`
  — NOTE(paper)/NOTE(cite) from `R/02_build_grid.R` (2026-07-11)

- **Queen contiguity spatial cluster labeling** — `R/utils_spatial.R` (`flag_spatial_clusters()`) —
  DE-9IM pattern `"****1****"`; union-find BFS; result: 1 connected component for this rectangular
  grid → A7/A11 use geographic sub-regions for spatial splits — novel/mentor's method; `\cite{pebesma2018sf}`
  — NOTE(paper) from `R/02_build_grid.R` (2026-07-11)

- **Darwin Core Archive join** — `R/03_habsos_labels.R` — `data.table::merge(event.txt, occurrence.txt,
  by = "event_id")` inner join; join key: `event.txt$id = occurrence.txt$eventID`; 2 parse-corrupt
  rows dropped (broken lat field) — DwC-A standard (TDWG); `\cite{habsos}` — NOTE(paper) from
  `R/03_habsos_labels.R` (2026-07-11)

- **Point-to-cell spatial join (HABSOS)** — `R/03_habsos_labels.R` — `sf::st_join(..., join = st_within,
  left = FALSE)`; points reprojected from EPSG:4326 to EPSG:5070 before join; drops points outside
  study grid — `\cite{pebesma2018sf}`; `\cite{green2022rtm}` (mentor's method) — NOTE(paper) from
  `R/03_habsos_labels.R` (2026-07-11)

- **Binary HAB label construction** — `R/03_habsos_labels.R` — max(organism_quantity) per (cell_id × date)
  via `data.table` groupby; `HAB = 1` if max > 100,000 cells/L; `IS_ABSENCE_UNCERTAIN = TRUE` all rows
  — `\cite{hu2022karenia}` (threshold precedent); PLAN.md D2/D3 — NOTE(paper)/NOTE(cite)/NOTE(limitation)
  from `R/03_habsos_labels.R` (2026-07-11)

- **T+H forecasting label shift** — `R/06_build_datacube.R` Step 6
  **(implemented A6 2026-07-11)** — for each horizon H ∈ {1,3,5,7,14}, the forecast
  target for row (cell_id, T) = HAB(cell_id, T+H). Implementation: create
  `lab_shifted[feature_date = sample_date - H, HAB]`, merge on
  `(cell_id, feature_date = sample_date)`. Result columns: `HAB_H1`, `HAB_H3`, `HAB_H5`,
  `HAB_H7`, `HAB_H14`. NA = no HABSOS observation at T+H (not assumed negative; A7 filters
  with `!is.na(HAB_Hk)`). Since H > 0, label date is strictly after feature date — no
  look-ahead leakage by construction (LEAKAGE-D assertion).
  — `\cite{green2022rtm}` (RTM forecasting design); PLAN.md D5/§2.2 — NOTE(paper) from
  `R/06_build_datacube.R` (2026-07-11)

- **Trend feature engineering (D11, 61 columns)** — `R/06_build_datacube.R` Step 3
  **(implemented A6 2026-07-11)** — for each of 4 level features (chlor_a_mean, sst_mean,
  nflh_mean, Kd_490_mean): (a) absolute k-day calendar-day deltas (k ∈ {1,3,5,7}, exact-date
  join, NA if offset date absent); (b) signed % change (x_T − x_{T-k}) / (|x_{T-k}| + ε)
  × 100, ε=1e-6; (c) trailing OLS slopes over k=3,5,7 observed dates (observation-order
  indices); (d) rolling mean and rolling std over k=3,7 observations (trailing). Plus (e)
  `chlor_a_above10pct_consec` bloom-accumulation flag. Total: 61 trend columns. All strictly
  backward-looking (feature date T or prior). — PLAN.md D11/§8-B — NOTE(paper) from
  `R/06_build_datacube.R` (2026-07-11)

- **Vectorised OLS slope (closed-form, observation order)** — `R/06_build_datacube.R`
  `ols_slope_k()` — closed-form OLS coefficients with x = 1:k (observation order); no matrix
  inversion: k=3: (y[i] − y[i−2])/2; k=5: (−2y[i−4] − y[i−3] + y[i−1] + 2y[i])/10;
  k=7: (−3y[i−6] − 2y[i−5] − y[i−4] + y[i−2] + 2y[i−1] + 3y[i])/28. Implemented via
  `data.table::shift()` by cell group (no row-wise loops). Unit: change per satellite
  observation (not per calendar day). NA propagated if any window value is NA.
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **Calendar-day delta join (exact match, no LOCF)** — `R/06_build_datacube.R` Step 3 —
  for calendar-day delta at lag k: create reference table
  `sat_lag[join_date = date + k, lag_val = x]`, exact-join to `sat` on
  `(cell_id, date = join_date)`. Retrieves x at T-k without accessing any future date.
  NA when T-k is not in the satellite series (cloud gap or unprocessed date — honest, not
  LOCF-filled). PLAN.md §5: "never let a fill masquerade as an observation."
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **frollmean / rolling std (align="right", trailing)** — `R/06_build_datacube.R` Step 3 —
  `data.table::frollmean(align="right", na.rm=TRUE)` for trailing rolling means over
  k=3 and k=7 observation windows, grouped by `cell_id`. Rolling std via:
  Var(X) = E[X²] − E[X]²; `sqrt(pmax(0, E[X²] - E[X]^2))` (avoids negative roundoff).
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **10% DoD threshold flag (`chlor_a_above10pct_consec`)** — `R/06_build_datacube.R`
  Step 3 — integer (0/1); 1 when: (a) chlor_a rose > 10% on 1-day calendar delta AND
  (b) the immediately prior observation ALSO rose > 10% (observation-order consecutive
  test via `shift()`). Directly interpretable bloom-accumulation signal. Threshold and
  consecutive count from `config.yaml` (`dod_pct_threshold`, `dod_consecutive_days`).
  — PLAN.md D11 — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **Historical HAB non-equi join** — `R/06_build_datacube.R` Step 4 — for each
  (cell_id, T), `hab_any_prior_7d` and `_14d` computed via data.table non-equi join:
  find all rows in habsos_labels where `sample_date ∈ [T-lag, T)` (strict less-than
  prevents inclusion of same-day observation). `any(HAB==1)` aggregated per (cell_id, T).
  Pre-computed `win_start = sample_date - lag_days` column required (data.table non-equi
  join does not allow expressions in `on=`).
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **No-look-ahead leakage assertions (5 hard stopifnot checks)** — `R/06_build_datacube.R`
  Step 8 **(ALL PASSED in DRAFT)** — (A) all feature dates ≥ 2003-01-01; (B) all calendar
  delta lags > 0; (C) slope/roll columns are trailing (verified by construction via shift()
  and align="right"); (D) all horizons H > 0 (label date T+H strictly after feature date T);
  (E) hab-lag joins use strict-prior dates (< T, not ≤ T). Script aborts on any failure —
  no silent leakage possible. — PLAN.md §2.2 — NOTE(paper) from `R/06_build_datacube.R`
  (2026-07-11)

- **OB.DAAC file-search API** — `R/04_satellite_features.R::obdaac_url()` — constructs
  daily file URL per product/date; naming convention
  `AQUA_MODIS.YYYYMMDD.L3m.DAY.<PROD>.<var>.4km.nc`;
  URL base: `https://oceandata.sci.gsfc.nasa.gov/getfile/` — NOTE(cite) from
  `R/04_satellite_features.R` (2026-07-11)

- **Authenticated MODIS download (NASA Earthdata OAuth)** — `R/04_satellite_features.R::download_modis()`
  — R `curl` package (`curl_download()` + `new_handle()`); netrc=1 + cookie jar for
  NASA Earthdata OAuth redirect chain; timeout=300 s, low_speed_limit=1 KB/s;
  file-size guard (< 10 KB → reject as auth-error HTML response) — NOTE(cite) from
  `R/04_satellite_features.R` (2026-07-11)

- **terra::crop() → terra::project() (bilinear) for MODIS clip+reproject** —
  `R/04_satellite_features.R::aggregate_to_grid()` — crop global raster to
  ext(-87, -81, 24, 31) before reproject to reduce memory; bilinear interpolation
  appropriate for all 4 continuous ocean color variables (nearest-neighbor would be
  correct only for categorical/flag rasters) — `\cite{pebesma2018sf}` (sf for grid
  loading); `terra` package (Hijmans et al.) — NOTE(paper) from
  `R/04_satellite_features.R` (2026-07-11)

- **terra::rasterize() + terra::zonal() for per-cell aggregation** —
  `R/04_satellite_features.R::aggregate_to_grid()` — rasterize 10 km EPSG:5070 vector
  grid onto reprojected MODIS raster (`field = "cell_id"`), then compute per-zone
  mean of valid (non-NA) pixels and sum of valid-pixel count — NOTE(paper)/NOTE(cite)
  from `R/04_satellite_features.R` (2026-07-11)

- **cloud_flag definition** — `R/04_satellite_features.R` main loop —
  `cloud_flag = TRUE` iff sum of `*_n_valid` across all 4 products == 0 for that
  cell-day; partial cloud (some products valid, others not) is cloud_flag=FALSE with
  NAs in missing product columns; NOT zero-filled; ~61% of cell-days are cloud-flagged
  in the Gulf — NOTE(limitation) from `R/04_satellite_features.R` (2026-07-11)

- **TIGER spatial join + nearest-feature fallback (EPSG:5070)** — `R/05_environmental_features.R`
  Section A — grid cell centroids joined to Gulf-state counties (FIPS: 01,12,13,22,28,48)
  via `sf::st_join(join=st_intersects, left=TRUE)`; ocean cells with `NA` GEOID (no polygon
  intersection) reassigned via `sf::st_nearest_feature()`. TIGER counties reprojected from
  EPSG:4269 to EPSG:5070 before join — NOTE(paper)/NOTE(cite) from
  `R/05_environmental_features.R` (2026-07-11)

- **GEBCO 2026 queue API download** — `R/05_environmental_features.R` Section B —
  POST `{"items":[{"data_source_ids":[1],"formats":[2],"left":-87,"right":-81,"top":31,"bottom":24}]}`
  to `https://download.gebco.net/api/queue`; poll
  `GET /api/queue/status/{basketId}` until "finished"; download
  `GET /api/queue/download/{basketId}` as zip; extract GeoTIFF (~5 MB Gulf subset). No auth.
  — NOTE(paper)/NOTE(cite) from `R/05_environmental_features.R` (2026-07-11)

- **GEBCO zonal mean per cell (terra::extract)** — `R/05_environmental_features.R` Section B —
  `terra::project(bathy, "EPSG:5070", method="bilinear")` then
  `terra::extract(bathy_5070, vect(grid), fun="mean", na.rm=TRUE)`. 24 edge cells have NA.
  — NOTE(paper)/NOTE(limitation) from `R/05_environmental_features.R` (2026-07-11)

- **Distance-to-shore (sf::st_distance, EPSG:5070)** — `R/05_environmental_features.R`
  Section C — TIGER national coastline (`tl_2023_us_coastline.zip`) reprojected to EPSG:5070;
  `st_union()` to single geometry; `st_distance(st_centroid(grid), coast_union)` returns
  Euclidean meters from each centroid to nearest coastline segment. Range: 17 m–429 km.
  Euclidean distance only — does not account for bathymetric barriers or curved coastal
  geometry — NOTE(paper)/NOTE(cite) from `R/05_environmental_features.R` (2026-07-11)

- **CHIRPS vsicurl stream-and-discard (designed, currently 403-blocked)** —
  `R/05_environmental_features.R` Section D —
  `terra::rast("/vsigzip//vsicurl/https://data.chc.ucsb.edu/.../chirps-v2.0.YYYY.MM.DD.tif.gz")`
  streams and crops without local storage (no permanent files); checkpoint-resumable Parquet
  every 50 dates; no auth required; blocked by CHC CrowdSec 403 during A5 session
  — NOTE(cite)/NOTE(limitation) from `R/05_environmental_features.R` (2026-07-11)

- **Seasonality sin/cos circular encoding** — `R/05_environmental_features.R` Section G —
  `doy_sin = sin(2π × doy/365)`, `doy_cos = cos(2π × doy/365)`; encodes annual position
  without discontinuity at year boundary; pair jointly spans the unit circle; month integer
  also retained for interpretability — NOTE(paper) from `R/05_environmental_features.R`
  (2026-07-11)

- **RBD / K. brevis Bloom Index (KBBI) — Amin et al. (2009)** — `R/04b_bio_optical_features.R`
  (implementer) / `reports/bio_optical_spec.md` §1 (spec, lead-verified 2026-07-14) —
  `RBD = nLw(678) − nLw(667)` [W m⁻² µm⁻¹ sr⁻¹] (Eq. 19); `KBBI = (nLw(678)−nLw(667)) /
  (nLw(678)+nLw(667))` (Eq. 20); nLw(λ) = Rrs(λ) × F0(λ) — NOT computed on Rrs directly.
  F0 = MODIS-Aqua band-13/14 band-averaged solar irradiance (NASA sensor constant; exact
  values/source pending in `reports/agent_logs/sat-features.md`). Thresholds: RBD>0.15
  (detection); RBD>0.15 & KBBI>0.3·RBD (K. brevis classification). Outputs: `rbd`, `kbbi`
  (continuous, primary), `rbd_detect`, `kbbi_kbrevis` (boolean companions).
  — `\cite{amin2009rbd}` — NOTE(cite) harvested from `reports/bio_optical_spec.md` (A-DOC,
  2026-07-14)

- **Cannizzaro low-bbp-per-chlorophyll K. brevis rule** — `R/04b_bio_optical_features.R`
  (implementer) / `reports/bio_optical_spec.md` §3 — `bbp(551) = bbp_443 ×
  (443/551)^bbp_s` (MODIS IOP L3m power law, Eq. 14); classification: Chl > 1.5 mg m⁻³ AND
  bbp(550) < bbp_Morel(550;Chl) (§6.1, p.150, Fig. 9C). Outputs: `bbp_551`, `bbp_morel_550`,
  `bbp_ratio_morel` (primary continuous score), `bbp_deficit`, `cannizzaro_kbrevis` (boolean).
  NA (not zero-filled) on missing Chl/bbp inputs, per existing sat-features missingness
  convention. — `\cite{cannizzaro2008bbp}` — NOTE(cite) harvested from
  `reports/bio_optical_spec.md` (A-DOC, 2026-07-14)

- **Morel (1988) Case-1 bbp(550) reference curve** — `R/04b_bio_optical_features.R`
  (implementer) / `reports/bio_optical_spec.md` §2 — `bbp_Morel(550;C) =
  0.30·C^0.62 · [0.002 + 0.02·(0.5 − 0.25·log₁₀C)]` (combining Eq. 18, p.10759, r²=0.90,
  n=506, with the unnumbered particulate-backscattering-fraction equation, p.10760); C =
  chlorophyll mg m⁻³, valid ~0.03–30. Cross-checked byte-identical to Amin (2009) Eq. 16
  (Amin miscites its own origin to Morel & Maritorena 2001, not this 1988 paper) — two
  independent published derivations agree, raising transcription confidence. Serves as the
  reference curve for the Cannizzaro rule above. — `\cite{morel1988case1}` — NOTE(cite)
  harvested from `reports/bio_optical_spec.md` (A-DOC, 2026-07-14)

---

## Modeling

- **Label availability per forecast horizon (DRAFT)** — `data/processed/model_dataset.parquet`
  (A6 2026-07-11) — Labelled rows = HABSOS cell-days with a HABSOS observation also present
  at T+H. H=1: 7,791 rows / 957 pos (12.3%); H=3: 4,765 / 686 pos (14.4%); H=5: 6,151 /
  809 pos (13.2%); H=7: 23,751 / 2,005 pos (8.4%); H=14: 23,889 / 1,881 pos (7.9%). Short
  horizons (H=1,3) are sparse due to low consecutive-day HABSOS resampling; primary model
  training will be on H=7 and H=14 where sample counts are adequate. Overall label base rate
  declines toward longer horizons (8–9%) reflecting lower consecutive-observation probability
  with the bloom signal diluted over larger temporal separation.
  — NOTE(paper) from `R/06_build_datacube.R` and `reports/agent_logs/datacube.md` (2026-07-11)

- **same-day HAB column retained (diagnostic only — A7 must not use as feature)** —
  `data/processed/model_dataset.parquet` column `HAB` — `HAB` at feature date T is NOT
  leakage in the strict look-ahead sense (it is observed at T) but conflates bloom detection
  with bloom forecasting. A7 must drop `HAB` from the feature matrix when training on
  `HAB_HX` for X > 0. Retained in cube for ablation experiments: run models with and without
  same-day HAB to quantify its marginal contribution vs. the full forecasting-only feature set.
  — NOTE(paper) from `R/06_build_datacube.R` (2026-07-11)

- **Spatial CV grouping confirmed: spatial_block_tiger (82 TIGER county blocks)** —
  `data/processed/model_dataset.parquet` column `spatial_block_tiger` carried from
  `static_geo.parquet` (A5). A6 does not re-derive it. `spatial_cluster` (Queen-contiguity)
  is NOT in `model_dataset`; if needed A7 can join from `data/processed/study_area_grid.gpkg`
  via `cell_id`. Per Lead Directive 2026-07-11: ALL A7/A11 spatial CV splits use county blocks.
  — NOTE(paper) from `R/06_build_datacube.R` / `reports/agent_logs/datacube.md` (2026-07-11)

- **Random Forest per-horizon (Stage-1) — ranger** — `R/07_modeling.R` **(implemented A7 2026-07-11)** — `ranger::ranger(probability=TRUE, num.trees=500, num.threads=1, case.weights)`. One binary HAB classifier per H ∈ {1,3,5,7,14}: label = HAB_Hk; predict P(HAB=1) at T+H from features through T. Class weights: positive class = n_neg/n_pos (imbalance ratio); negative class = 1.0. Prioritises recall per PLAN.md §9. Probability output thresholded at 0.5 for binary metrics. Best model: H=7 temporal RF saved as `models/best_model.rds`. num.threads=1 per host resource constraint. — `\cite{breiman2001rf}` (RF algorithm); `\cite{wright2017ranger}` (ranger package) — NOTE(paper)/NOTE(cite) from `R/07_modeling.R` (2026-07-11)

- **log1p feature transforms (chlor_a_mean, nflh_mean, Kd_490_mean)** — `R/07_modeling.R` preprocessing — (a) `chlor_a_mean`: `log1p(pmax(x, 0))` (floor negatives to 0; log1p); (b) `nflh_mean`: `sign(x) * log1p(abs(x))` (signed log1p — preserves negatives from clear-water retrievals); (c) `Kd_490_mean`: `log1p(pmax(x, 0))`. Level features only — trend/delta/slope columns are NOT transformed (can be negative; RF splits are robust to monotone transforms). Rationale: satellite chl-a is log-skewed; HABSOS outlier counts up to 3.58×10⁸ cells/L are real (R3 outlier verdict) but binary label absorbs the tail. — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Median imputation with missingness-indicator flags** — `R/07_modeling.R` `impute_with_flag()` — Train-split medians computed on training partition only; applied identically to test split (no test-set information leakage). Binary `{col}_is_missing` indicator added per imputed column: allows RF to exploit cloud-cover gap patterns (missingness correlates with weather/bloom cycles). Ref: van Buuren & Groothuis-Oudshoorn 2011 (mice imputation strategy, cited in A7). — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Feature exclusion — ALWAYS_EXCLUDE list** — `R/07_modeling.R` — Hard-excluded from predictor matrix: (a) `HAB` (same-day detection — conflates detection/forecasting; verified by stopifnot); (b) all `HAB_Hk` except target horizon; (c) `max_count`, `n_samples` (HABSOS aggregation artifacts); (d) 6 placeholder env cols: `wind_u_ms`, `wind_v_ms`, `wind_speed_ms`, `wind_dir_deg`, `precip_mm`, `salinity_pss` (all-NA, ERA5/CHIRPS/SMAP placeholder); (e) diagnostic/honesty flags: `IS_PLACEHOLDER_ROW`, `satellite_missing`, `cloud_flag`, `salinity_coarse_flag`, `feature_filled_any`, `IS_ABSENCE_UNCERTAIN`, `sat_IS_PLACEHOLDER`, `env_IS_PLACEHOLDER`, `static_IS_PLACEHOLDER`, `label_IS_PLACEHOLDER`, `sat_feature_filled`, `env_feature_filled`; (f) `spatial_block_tiger` (CV key, not predictor). — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Three evaluation splits — temporal (PRIMARY), spatial-block, random** — `R/07_modeling.R` — (a) **Temporal (PRIMARY honest split)**: train 2003–2015, test 2016–2021 (TEMPORAL_CUTOFF_YEAR=2016). Chronological; prevents future-data leakage. (b) **Spatial-block**: county-block holdout (spatial_block_tiger) greedy until ≥15% test rows; tiny blocks < 5 rows (12_083, 12_077) merged into largest block before splitting. (c) **Random**: 80/20 stratified by HAB; included as optimistic upper-bound reference only. Headline metric in paper = temporal. — PLAN.md §9; NOTE(paper) from `R/07_modeling.R` and `reports/agent_logs/modeling.md` (2026-07-11)

- **PR-AUC as primary metric (imbalanced classes)** — `R/07_modeling.R` `pr_auc_fn()` — trapezoidal precision-recall AUC preferred over ROC-AUC for HAB labels (~8% positive). ROC-AUC reported as secondary. False-negative cost is critical for early warning (a missed bloom > a false alarm). — `\cite{davis2006prcurves}` (Davis & Goadrich 2006, ICML) — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Persistence baseline** — `R/07_modeling.R` `baseline_persistence()` — predicts `HAB_Hk = HAB` at feature date T ("no change"). Exploits same-day HAB which RF cannot use as a feature — persistence is structurally advantaged for active-bloom detection. High persistence recall shows a bloom rarely appears without same-day bloom signal present. — PLAN.md §9 — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Chl-only baseline (RF on log1p(chlor_a_mean) only)** — `R/07_modeling.R` `baseline_chl_only()` — RF with single feature `log1p(pmax(chlor_a_mean, 0))`. Quantifies marginal contribution of all non-chlorophyll features (SST, nFLH, Kd490, trend suite, geography, seasonality, HAB lags). — PLAN.md §9 — NOTE(paper) from `R/07_modeling.R` (2026-07-11)

- **Skill-vs-horizon decay curve (required figure D6)** — `R/07_modeling.R` → `figures/skill_vs_horizon.png` — PR-AUC, ROC-AUC, recall, F1 vs. H ∈ {1,3,5,7,14} for RF + baselines across all 3 splits. Decay with increasing H is an expected result (signal-to-noise degrades at longer horizons), not a failure — must be presented and discussed in paper. — PLAN.md §9/D6 — NOTE(paper) from `R/07_modeling.R` and `reports/agent_logs/modeling.md` (2026-07-11)

- _(A11 Transformer — pending)_

---

## Results

### Stage-1 RF — temporal split headline metrics (PRIMARY HONEST RESULTS)

Temporal split (train 2003–2015, test 2016–2021) is the primary honest forecasting assessment.
Random-split results are an optimistic upper bound (spatial autocorrelation); spatial-block
results are a geographic-transfer assessment, NOT superior generalization.
Source: `reports/agent_logs/modeling.md` (2026-07-11).

#### H=7 (n_test=8,880; n_pos=1,075; 8.4% positive rate)

| Model | Recall | PR-AUC | ROC-AUC | F1 |
|---|---|---|---|---|
| RF (Stage-1) | 0.370 | **0.497** | 0.832 | 0.455 |
| Persistence baseline | 0.627 | 0.450 | 0.821 | 0.625 |
| Chl-only baseline | 0.080 | 0.142 | 0.542 | 0.114 |

#### H=14 (n_test=9,021; n_pos=1,010; 7.9% positive rate)

| Model | Recall | PR-AUC | ROC-AUC | F1 |
|---|---|---|---|---|
| RF (Stage-1) | 0.272 | **0.445** | 0.812 | 0.372 |
| Persistence baseline | 0.523 | 0.320 | 0.762 | 0.512 |
| Chl-only baseline | 0.069 | 0.122 | 0.526 | 0.102 |

Key results: RF beats persistence on PR-AUC at both horizons (H=7: +0.047; H=14: +0.125).
Persistence recall advantage is structural (same-day HAB unavailable to RF as feature).
RF substantially beats chl-only (H=7 PR-AUC: +0.355), demonstrating the full feature suite value.

### Bio-optical features — measured model impact (A10, 2026-07-14) — NEGATIVE result
Bit-exact comparison of frozen models `best_model_before_bio.rds` vs. `best_model.rds` on the
same 8,880 H=7-temporal test rows (`identical(test_idx)`=TRUE). "Before" here is the
wind-inclusive RF immediately prior to adding the bio-optical columns (PR-AUC 0.5022) — a
different reference point than the original pre-wind headline (0.497, §above), reflecting the
ERA5-wind update that landed between them (design_rationale §7.3). Source:
`reports/agent_logs/validation.md`; `outputs/tables/bio_validation_before_after.csv`;
`outputs/tables/bio_fp_concentration_before_after.csv`.

| Metric (H=7 temporal) | Before (pre-bio) | After (bio-inclusive) | Δ |
|---|---|---|---|
| PR-AUC | 0.5022 | 0.4849 | **−0.0173** |
| precision @ recall=0.80 | 0.2759 | 0.2796 | +0.0037 |
| recall @ 0.5 | 0.3553 | 0.3153 | **−0.0400** |
| TP / FP (@0.5) | 382 / 254 | 339 / 232 | TP −43, FP −22 |

Grid (15 H×split combos): PR-AUC down 10/15, up 5/15; recall@0.5 down 12/15;
precision@recall-0.80 a wash (down 7/up 7/flat 1).

**Mechanistic nuance (observed/clear-sky rows only, chl 30.2%, nFLH 25.2% of test):** the
features cut their *targeted* error — top-chl-Q4 FP 39→31 (100% of the net observed-chl FP
reduction); top-chl-Q4 share of all FP 73.58%→68.89%; joint high-chl/high-nFLH FP-rate
12.41%→10.95%. But the joint FP-**concentration ratio** rose 19.09×→22.35× (clean-water FPs
fell proportionally more, 0.65%→0.49%), and the −22 FP cut was outweighed by −43 TP loss →
net skill down.

**Verdict:** a legitimate negative aggregate result with a real-but-weak, correctly-targeted
mechanistic effect. "Associated with," never "causes" — correlational error-shape change on a
frozen holdout, not a demonstrated causal improvement in species discrimination.

_All other result tables/figures pending A8 (SHAP/explainability), A9 (GIS maps), A11 (transformer)._

---

## Limitations

- **HABSOS non-detection ≠ proven absence** — wherever labels are used; A3 + validation —
  PLAN.md §1; `R/01_source_data.R` NOTE(limitation) + `R/03_habsos_labels.R` NOTE(limitation)
  (harvested 2026-07-11)

- **Label balance 7.93% positive** — reflects sampling effort, not true bloom frequency; handle
  in A7 via class weights + recall/PR-AUC priority (not raw accuracy) — `R/03_habsos_labels.R`
  NOTE(limitation) (harvested 2026-07-11)

- **Pre-2002 HABSOS records dropped at datacube join** — labels extend to 1953 but MODIS begins
  2003; explicit A6 filter — `reports/agent_logs/habsos-label.md` (2026-07-11)

- **Extreme max count 3.58×10⁸ cells/L** — requires outlier check by A7/R3 before training —
  `reports/agent_logs/habsos-label.md` (2026-07-11)

- **MODIS L3 pixels ~4.6 km vs. 10 km cells** — no sub-km precision implied; `R/02_build_grid.R`
  NOTE(paper) (harvested 2026-07-11) — PLAN.md §5

- **SMAP salinity ~40–70 km** — broad-context feature only; flag in all outputs —
  PLAN.md §5; `data/metadata/data_sources.md`

- **Intra-cell attention drill-down is diagnostic** — feature concentration, not sub-cell
  forecast; nothing rendered below native ~4 km MODIS pixel — PLAN.md §2.3/D12

- **No causal claims, no "first ever," no "operationally ready" without hard-split survival** —
  PLAN.md §1 guardrails

- **FAI not available from MODIS L3m** — `R/04_satellite_features.R` NOTE(limitation);
  wherever satellite features are described — FAI (Floating Algae Index) requires MODIS
  bands at ~859 nm and ~1240 nm that are not published in OB.DAAC L3m daily mapped products;
  L2 swath processing would be required (outside scope). nFLH used as the available L3m
  fluorescence proxy. Cite `\cite{hu2009fai}` for the FAI definition if discussed
  — harvested 2026-07-11 from `R/04_satellite_features.R`

- **~61% cloud cover (MODIS Gulf cell-days)** — `R/04_satellite_features.R` NOTE(limitation);
  wherever cloud statistics are cited — majority of Gulf cell-days have cloud_flag=TRUE
  (cloud cover, sun glint, high sensor zenith angle); this is expected for MODIS over the
  Gulf of Mexico and is NOT a data error. A6 gap-fills with `feature_filled=TRUE` within
  valid periods. Flag cloud coverage in methods and evaluate its effect on feature
  availability in Results — harvested 2026-07-11

- **Arithmetic mean of chlor_a (log-normal upward bias)** — `R/04_satellite_features.R`
  aggregation; wherever chlor_a statistics are reported — chlorophyll-a is log-normally
  distributed; arithmetic mean of 4–6 pixel values per 10 km cell is upward-biased
  relative to geometric mean. Conservative for bloom detection (bloom pixels inflate
  mean). Not changed for downstream consistency with rolling stats — acknowledge in
  methods — harvested 2026-07-11 from agent log

- **nFLH negative values retained** — `R/04_satellite_features.R` NOTE(limitation);
  wherever nFLH is used — negative nFLH values (range −0.23 to +2.15 mW cm⁻² µm⁻¹ sr⁻¹)
  occur over clear, low-biomass water (instrument noise, sub-pixel atmospheric correction);
  these are real retrievals, not errors. Do not clip to zero; A7 should be aware when
  interpreting nFLH feature importance — harvested 2026-07-11

- **Satellite date scope limited to HABSOS sample dates** — `R/04_satellite_features.R`
  NOTE(limitation) — script processes 5,829 HABSOS sample dates (not all 6,935 daily
  days 2003-2021). Full daily era would provide denser time series for rolling stats;
  the checkpoint system allows incremental extension. A6 may need denser satellite
  coverage for reliable rolling windows — harvested 2026-07-11

- **SST daytime atmospheric correction uncertainty** — `R/04_satellite_features.R`
  NOTE(paper) — daytime SST has higher aerosol-correction uncertainty than night SST4
  (chosen for higher Gulf coverage). Near-coast pixels may have residual contamination.
  State SST product choice and tradeoff in methods — harvested 2026-07-11

- **ERA5 wind placeholder (no ~/.cdsapirc)** — `R/05_environmental_features.R` NOTE(limitation)
  — wind_u_ms / wind_v_ms and derived along-shore/cross-shore components all NA;
  `wind_is_placeholder=TRUE`. Along-shore/cross-shore bloom transport features (PLAN.md §8-A)
  NOT YET COMPUTED. Requires Copernicus CDS key in `~/.cdsapirc`; instructions in
  `data/raw/weather/manual_downloads.md` — harvested 2026-07-11

- **CHIRPS precipitation placeholder (403 CrowdSec block)** — `R/05_environmental_features.R`
  NOTE(limitation) — `precip_mm=NA`, `precip_is_placeholder=TRUE` for all dates. CHC UCSB
  server returned HTTP 403 during A5 session. No auth needed; retry after ~24 h or from
  different IP. Script is checkpoint-resumable — harvested 2026-07-11

- **SMAP salinity coarse resolution + coverage gap** — `R/05_environmental_features.R`
  NOTE(limitation) — SMAP L3 footprint 40–70 km >> 10 km grid; `salinity_coarse_flag=TRUE`
  on ALL rows unconditionally. Coverage starts 2015-04-01; HABSOS labels prior to that date
  have no salinity signal. Pre-2015 missingness is informative structure, not random — A7
  must handle carefully — harvested 2026-07-11

- **GEBCO 2026 license — NON-COMMERCIAL** — `reports/agent_logs/env-features.md` —
  GEBCO 2026 Grid released under GEBCO Terms of Use restricting **commercial use**.
  Same issue as MEOW/Spalding 2007. If GEBCO depth or bathymetric layers appear in any
  figure or output, confirm target venue (journal, competition) permits non-commercial
  components. Consider ETOPO alternatives for open-license venues. Flag all outputs using
  `depth_m` — harvested 2026-07-11

- **GEBCO 24 edge-cell NAs** — `R/05_environmental_features.R` NOTE(limitation) — 24 cells
  at the periphery of the Gulf bbox have NA depth (partial raster coverage at bbox edge).
  Marked `IS_PLACEHOLDER=TRUE` in `static_geo.parquet`. A6 should impute from adjacent
  cells or retain NA — do not zero-fill depth — harvested 2026-07-11

- **Distance-to-shore is Euclidean, not hydrodynamic** — `R/05_environmental_features.R`
  NOTE(paper) — `st_distance()` returns straight-line distance to nearest TIGER coastline
  segment in EPSG:5070; does not account for bathymetric barriers or bay geometry. Adequate
  for first-order bloom-proximity feature; do not claim it reflects transport distance —
  harvested 2026-07-11

- **MODIS cloud cover: 45.7% cloud_flag, 66.7% chlor_a NA in FINAL cube** — `R/06_build_datacube.R`
  FINAL run NOTE(limitation) — `satellite_missing=0` in FINAL cube (all 5,829 HABSOS dates
  fully processed by A4). However, `cloud_flag=TRUE` for 30,135 rows (45.7%) and chlor_a is
  NA for 43,991 rows (66.7%) due to cloud/quality masking. These are honest real-world
  atmospheric conditions over the Gulf of Mexico, NOT data errors. Satellite-derived features
  are NA where masked; do not impute with zeros. Report cloud-flag rates in methods section
  when describing feature availability — harvested 2026-07-11 (DRAFT→FINAL update)

- **Observation-order OLS slopes — unit is change per satellite observation, not per day** —
  `R/06_build_datacube.R` NOTE(limitation) — `_slope_obsK` features use observation-order
  x-axis (1, 2, ..., k) because the satellite series covers only HABSOS sample dates
  (cloud-gapped irregular time series). For the full post-A4 dense dataset, consider
  recomputing with calendar-day x-axis for proper temporal rate-of-change interpretation.
  State slope unit explicitly in manuscript methods — harvested 2026-07-11

- **Calendar-day delta features NA on cloud gaps** — `R/06_build_datacube.R`
  NOTE(limitation) — `_delta_Xd` features use exact-date join; NA when T-X is a cloud-gap
  date (not in satellite series). In FINAL cube (full 5,829-date coverage), unprocessed-date
  NAs are gone but cloud-gap NAs remain (45.7% cloud_flag). Do not LOCF-fill; retain NA as
  honest missingness reflecting real atmospheric conditions — harvested 2026-07-11 (updated)

- **IS_PLACEHOLDER_ROW = 100% (env dynamic features, not satellite)** — `R/06_build_datacube.R`
  NOTE(limitation) — IS_PLACEHOLDER_ROW is TRUE for all 65,939 rows in FINAL cube.
  **`sat_IS_PLACEHOLDER=0`** (satellite is fully real). The 100% rate is solely due to
  `env_IS_PLACEHOLDER=TRUE` for all rows (ERA5 wind, CHIRPS precip, SMAP salinity still
  placeholder per A5 blockers). Use per-source flags: `sat_IS_PLACEHOLDER` (0% — real),
  `env_IS_PLACEHOLDER` (100% — placeholder), `static_IS_PLACEHOLDER` (24 edge cells NA).
  Will drop from 100% once A5 dynamic env pulls complete — harvested 2026-07-11 (updated)

- **Label sparsity at short horizons** — `R/06_build_datacube.R` NOTE(paper) —
  H=1 (7,791 labelled rows) and H=3 (4,765 rows) reflect the low rate of consecutive-day
  HABSOS re-sampling at the same cell. Models trained on H=1/H=3 may be less reliable due
  to small N and potential selection bias (consecutive sampling tends to occur during active
  bloom monitoring). Primary statistical power is at H=7 (23,751 rows) and H=14 (23,889
  rows) — harvested 2026-07-11

- **HABSOS non-detection ≠ proven absence (IS_ABSENCE_UNCERTAIN)** — `R/06_build_datacube.R`
  NOTE(limitation) — `IS_ABSENCE_UNCERTAIN=TRUE` on EVERY model_dataset row (including
  HAB=0). A row with HAB=0 means K. brevis was below 100,000 cells/L at sampling; it does
  NOT certify that the cell was bloom-free. State this wherever label construction is
  described — harvested 2026-07-11 (reinforcing earlier note from A3)

- **Reproducibility: `arrow` multi-thread deadlock — must run single-threaded** —
  `R/00_config.R` + `R/06_build_datacube.R` (operational environment note) — on this machine,
  `arrow::read_parquet()` deadlocks in multi-threaded mode (observed 7 R processes at 95% CPU
  for 15 h). Fix applied: `Sys.setenv(ARROW_NUM_THREADS="1")` in `R/00_config.R` (sourced by
  all scripts) and `arrow::set_cpu_count(1L)` per-script in A6. Both are belt-and-suspenders:
  the env var sets the C++ thread pool before arrow initialises; the API call enforces it
  after. **Anyone re-running the pipeline on a new machine should keep arrow single-threaded
  until this is diagnosed.** Not a data-quality issue; purely a reproducibility constraint.
  No external citation — `reports/agent_logs/datacube.md` decision log (2026-07-11)

- **Stage-1 RF excludes dynamic env features (ERA5/CHIRPS/SMAP placeholder)** —
  `R/07_modeling.R` NOTE(limitation) — wind, precipitation, and salinity columns are all-NA
  placeholder in model_dataset.parquet; all 6 env dynamic columns hard-excluded from
  predictor matrix. Stage-1 RF runs on: satellite features (chlor_a, nFLH, Kd490, SST +
  trend suite) + static geography (depth, dist_to_shore) + seasonality (doy sin/cos, month)
  + historical HAB lags only. Adding ERA5 wind, CHIRPS precipitation, and SMAP salinity is
  expected to improve recall at short horizons (H=1,3,5) where meteorological forcing
  dominates bloom transport. — harvested 2026-07-11 from `reports/agent_logs/modeling.md`

- **RF num.threads=1 — host resource constraint** — `R/07_modeling.R` NOTE(limitation) —
  `ranger::ranger(..., num.threads=1)` due to host machine resource limitation during A7 run.
  Production re-run and benchmarking should use `num.threads = parallel::detectCores() - 1`
  for full parallelism. Does not affect model correctness (weights, splits, predictions) —
  only training speed. — harvested 2026-07-11 from `reports/agent_logs/modeling.md`

- **SPATIAL SPLIT PREVALENCE CONFOUND (R-SPLIT caveat)** — `R/07_modeling.R` NOTE(paper)
  and `reports/agent_logs/modeling.md` — The spatial-block holdout always isolates Collier
  County (block 12_115), the dominant HAB hotspot: held-out positive rate = 11.4% vs. 8.4%
  in the random test set (1.35× inflation). Spatial PR-AUC at H=7 (0.663) exceeds random
  (0.631) due to this prevalence difference, **NOT** because the model generalises better
  geographically. Additionally, 14.6% of spatial test cells fall within ~10 km of training
  cells at county-block borders, introducing residual spatial autocorrelation. In the paper:
  describe spatial results as "geographic transfer to a high-prevalence region," not as
  evidence of superior generalisation. Temporal PR-AUC=0.497 (H=7) is the honest headline.
  — harvested 2026-07-11 from `reports/agent_logs/modeling.md`

- **TEMPORAL SPLIT ZERO-EMBARGO (R-SPLIT caveat)** — `R/07_modeling.R` NOTE(limitation)
  and `reports/agent_logs/modeling.md` — No purge/embargo gap was applied at the 2016
  train/test boundary. At H=14, approximately 49 training rows (0.33% of training set) have
  a label_date (T+14) falling in the test period (2016+), constituting a small optimistic
  information leak bounded by HABSOS observation sparsity. Effect on reported PR-AUC is
  estimated as negligible but not zero. A future iteration should add an H-day embargo
  window straddling the 2016 temporal boundary. Report this caveat alongside all
  temporal-split metrics. — harvested 2026-07-11

- **Short-horizon RF models — lower statistical confidence (H=1, H=3)** —
  `R/07_modeling.R` NOTE(limitation) — H=1 (7,791 labelled rows) and H=3 (4,765 rows) have
  insufficient sample sizes for reliable temporal or spatial split training. Models at H=1/3
  carry lower confidence; flag as "lower confidence due to sparse training sample" in all
  results tables and figures. Primary statistical power is at H=7 (23,751 rows) and H=14
  (23,889 rows). — harvested 2026-07-11 from `reports/agent_logs/modeling.md`

- **Bio-optical features are reused published discrimination equations, not independently
  re-validated for this sensor/aggregation — and measured to NOT improve aggregate forecast
  skill.** — `reports/bio_optical_spec.md` (2026-07-14); `reports/agent_logs/validation.md`
  (2026-07-14) — RBD/KBBI (Amin 2009) and the Cannizzaro (2008) low-bbp-per-chl rule were
  derived and validated by their original authors against in-situ K. brevis cell counts under
  their own instrument/processing conditions. Applying them to MODIS-Aqua L3m 10 km cell-day
  means here is a reuse, not a re-validation; output is *associated with*, not proof of,
  K.-brevis-specific optical signal at this aggregation. **A10 measured this empirically**: at
  H=7 temporal, PR-AUC fell 0.5022→0.4849 and recall@0.5 fell 0.3553→0.3153 (see Results
  above) despite a small, correctly-targeted cut in high-chlorophyll false positives
  (top-chl-Q4 FP 39→31) — a legitimate negative result with mechanistic nuance, not success.
  No causal / validated-sub-cell claim. — A-DOC 2026-07-14

- **F0 (solar irradiance constant) — resolved, sanity-checked.** — `reports/bio_optical_spec.md`
  §1; `reports/agent_logs/sat-features.md` §"F0 — authoritative source" (Gate 2, PASS) —
  RBD/KBBI require MODIS-Aqua band-13/14 band-averaged extraterrestrial solar irradiance F0
  (NASA OBPG sensor constant) to convert Rrs → nLw. **Resolved 2026-07-14**: F0(667) =
  1522.491 W m⁻² µm⁻¹, F0(678) = 1480.511 W m⁻² µm⁻¹, from NASA OBPG's Spectral Bandpass
  Integration (Thuillier reference solar spectrum × MODIS-Aqua RSR). Unit sanity-check (RBD
  near the 0.15 threshold scale, not 10× off) **PASSED**. — A-DOC 2026-07-14
