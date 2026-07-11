# BloomGuard GIS — publication source set (A-DOC · FINAL deliverable)

> **This is the project's final deliverable.** For every decision, method, and dataset used
> anywhere in the project, this document gives a publication-ready entry (plain-language
> description + the citation to use + which agent/file it came from), organized by paper
> section so the author can lift it straight into the manuscript.
>
> A-DOC builds this from every `reports/agent_logs/*.md` and the inline `NOTE()` tags.
> **A-DOC does NOT write the paper** — no abstract, intro, related-work, or discussion prose.
> **No invented citations.** Every entry here resolves to an entry in `references.bib`.

_Last updated: 2026-07-11 (A-DOC initial seeding pass + PDF harvest pass). Scripts 03–09
not yet implemented; modeling entries will be added as work lands._

---

## Intro

_Intro citations from author's lit-review notes (HAB Research (3).pdf). All UNRESOLVED
— verify DOIs before placing in manuscript. These support the introduction's framing of
HAB ecological/economic significance and the K. brevis Gulf of Mexico context._

- **Anderson et al. 2000** — UNRESOLVED. Likely: Anderson, D.M. et al. (2000). Context
  for HAB ecological/economic significance. Confirm exact title, journal, DOI; add to bib
  as `anderson2000hab`. Stub: `% @article{anderson2000hab, ...}` in `references.bib`.

- **Gobler (2020)** — UNRESOLVED. Likely: Gobler, C.J. (2020). Climate Change and
  Harmful Algal Blooms. *Harmful Algae* or similar. Confirm DOI; add to bib as
  `gobler2020climate`. Stub in `references.bib`.

- **Ralston & Moore (2020)** — UNRESOLVED. Likely: Ralston, D.K. & Moore, S.K. (2020).
  Modeling harmful algal blooms in a changing climate. Confirm DOI; add as
  `ralston2020model`. Stub in `references.bib`.

- **Magaña et al. (2003)** — UNRESOLVED. Context/title unknown. Author to provide paper
  or title so A-DOC can verify. Add as `magana2003` once resolved.

---

## Related Work

_Satellite ML / remote-sensing HAB papers. All entries added 2026-07-11 from PDF harvest
(benchmark table + author's notes). Map these in the manuscript's Related Work and/or
Modeling sections as directed. Author does NOT write this prose — entries are source set
anchors only._

### El-habashi et al. (2016) — VIIRS neural network, West Florida Shelf
- **What it is:** VIIRS-based neural network retrieval of *K. brevis* on the West Florida
  Shelf; comparisons with empirical and analytical techniques.
- **Relevance:** Direct geographic match (same study area). NN retrieval differs from this
  project (binary-label forecasting, not continuous optical retrieval), but provides a
  baseline for what satellite NN approaches achieve on this exact domain.
- **Status:** VERIFIED — DOI 10.3390/rs8050377 confirmed via WebSearch 2026-07-11.
- **Citation:** `\cite{elhabashi2016nn}`. Full author list to expand from DOI page.
- **Use in paper:** Related Work (geographic precedent, methodology contrast).

### Gokaraju et al. (2011) — spatio-temporal kernel SVM, Gulf of Mexico
- **What it is:** SeaWiFS + MODIS kernel SVM spatio-temporal data mining for HAB
  detection in the Gulf of Mexico.
- **Relevance:** Early demonstration of ML + satellite RS for Gulf of Mexico HABs;
  methodological predecessor. Cited to show the ML trajectory from SVM detection (2011)
  to RF/Transformer forecasting (this project).
- **Status:** VERIFIED — title, all 4 authors (Gokaraju, Durbha, King, Younan), DOI
  10.1109/JSTARS.2010.2103927 confirmed via WebSearch 2026-07-11.
- **Citation:** `\cite{gokaraju2011hab}`.
- **Use in paper:** Related Work (early ML predecessor).

### Carvalho et al. (2011) — MODIS empirical thresholding, K. brevis
- **What it is:** Empirical optical thresholding of MODIS bands for K. brevis detection;
  *Remote Sensing of Environment* 115:1–18.
- **Relevance:** Establishes MODIS optical baseline for K. brevis satellite work; the
  empirical-threshold approach that ML methods (Izadi 2021, this project) supersede.
- **Status:** VERIFIED — DOI 10.1016/j.rse.2010.07.007 confirmed via WebSearch
  2026-07-11. Full title and author list to confirm from DOI page.
- **Citation:** `\cite{carvalho2011modis}`.
- **Use in paper:** Related Work (pre-ML optical baseline).

### Karki et al. (2018) — MODIS K. brevis, Charlotte County FL
- **What it is:** MODIS-based K. brevis detection study for Charlotte County, Florida;
  *Remote Sensing* 10(10):1656.
- **Relevance:** Regional satellite ML study in the same Gulf/Florida domain.
- **Status:** VERIFIED — full title and all four authors (Karki, Sultan, Elkadiri, Elbayoumi)
  confirmed via WebSearch + Semantic Scholar 2026-07-11. DOI 10.3390/rs10101656 resolves.
- **Citation:** `\cite{karki2018modis}`.
- **Use in paper:** Related Work (Florida regional precedent).

### Izadi et al. (2021) — MODIS + XGBoost/RF/SVM, multi-horizon forecasting
- **What it is:** MODIS satellite features + XGBoost/RF/SVM classifier for K. brevis
  forecasting; 1–11 day lead times; 96% accuracy benchmark; Gulf of Mexico.
- **Relevance:** Closest published analog to this project's Stage-1 RF (PLAN.md D7).
  Same domain (Gulf of Mexico), same ML family (RF), multiple forecast horizons.
  Key comparison: tabular feature ML on satellite inputs → multi-day lead time.
- **Status:** VERIFIED — DOI 10.3390/rs13193863 confirmed via WebSearch 2026-07-11.
  Full title and author list to confirm from DOI page (lead author: M. Izadi).
- **Citation:** `\cite{izadi2021kb}`.
- **Use in paper:** Related Work and Modeling (benchmark comparison at H=1/3/5/7/14).

### Hill et al. (2020) — HABNet, CNN+LSTM+RF+SVM ensemble
- **What it is:** HABNet: multimodal CNN + LSTM + RF + SVM on MODIS ocean color + GEBCO
  bathymetry for HAB detection and prediction; *IEEE JSTARS* 13:3229–3239.
- **Relevance:** Architecturally most similar published system to Stage-2 Transformer
  (PLAN.md D8). Uses CNN (spatial) + LSTM (temporal) on satellite data, same input
  families as this project. Key contrast: image-input CNN architecture vs. tabular
  grid-cell RF+Transformer approach here.
- **Status:** VERIFIED — DOI 10.1109/JSTARS.2020.3001445 confirmed via WebSearch
  2026-07-11. Full author list to confirm from DOI page.
- **Citation:** `\cite{hill2020habnet}`.
- **Use in paper:** Related Work (architecture comparison) and Modeling discussion
  (multimodal deep-learning baseline; explain why grid-cell tabular approach differs).
  **Do NOT reframe this project's method as image-based to match HABNet.**

### Yao et al. (2023) — VIIRS CNN, K. brevis deep learning
- **What it is:** VIIRS-based CNN for K. brevis bloom detection; *Remote Sensing of
  Environment* 298:113833.
- **Relevance:** Recent state-of-the-art deep learning benchmark on ocean color data.
  Cited to position this project relative to the current frontier.
- **Status:** VERIFIED — DOI 10.1016/j.rse.2023.113833 confirmed via WebSearch
  2026-07-11. Full title and author list to confirm from DOI page.
- **Citation:** `\cite{yao2023viirs}`.
- **Use in paper:** Related Work (recent state of the art). Sensor difference (VIIRS vs.
  MODIS) and framing difference (detection vs. forecasting) must be noted.

---

## GIS Boundaries

_Static geographic datasets for map outputs. Added 2026-07-11 from PDF harvest._

### Spalding et al. (2007) — MEOW marine ecoregions
- **What it is:** Marine Ecoregions of the World (MEOW) — bioregionalization of coastal
  and shelf areas into 232 marine ecoregions. *BioScience* 57(7):573–583.
- **Relevance:** GIS ecoregion context for the Gulf of Mexico / West Florida Shelf in
  risk maps and study-area figures.
- **Status:** VERIFIED — DOI 10.1641/B570707 is well-known and correct.
- **Citation:** `\cite{spalding2007meow}`.
- **LICENSE WARNING:** The MEOW shapefile dataset is **CC BY-NC (non-commercial)**. If
  MEOW polygon boundaries appear in any figure or output, the work carries that
  non-commercial restriction. Before any submission, confirm: (a) journal's open-access
  policy allows NC-licensed components; (b) attribution is included in figure caption.
  Consider using IHO Sea Areas (CC-BY 4.0, below) if commercial/open use is required.
- **Use in paper:** Study-area map (A9 / gis-export); only if the MEOW license is
  acceptable for the target venue.

### Flanders Marine Institute / VLIZ (2023) — IHO Sea Areas
- **What it is:** IHO Sea Areas shapefile from Marine Regions (Flanders Marine Institute /
  VLIZ). Provides standardized ocean region boundaries.
- **Status:** UNRESOLVED — specific version and DOI not confirmed; A9 to verify at
  marineregions.org/sources.php when downloading. License: CC-BY 4.0 (permissive).
- **Citation:** `\cite{flanders2023marineregions}` (DOI to be filled by A9).
- **Use in paper:** Study-area map as an alternative or complement to MEOW if CC-BY-NC
  is a concern (CC-BY 4.0 is fully permissive).

### USF K. brevis Dataset (Mendeley/Digital Commons)
- **What it is:** University of South Florida K. brevis cell-count dataset hosted on
  USF Digital Commons Data.
- **Status:** UNRESOLVED — exact title, authors, year, DOI not confirmed; see URL
  `https://digitalcommonsdata.usf.edu/datasets/9kw6xzmxn3`. A1/A5 to confirm whether
  this dataset is used (supplements or overlaps HABSOS).
- **Citation:** `\cite{usf_kbrevis}` (DOI and details pending).
- **Use in paper:** Data section (if used as a supplementary or alternative to HABSOS).

---

## Data

### HABSOS — *Karenia brevis* cell-count ground truth
- **What it is:** The NOAA NCEI Harmful Algal BloomS Observing System (HABSOS) provides
  historical *K. brevis* cell-count samples (cells/L) with point location and date, spanning
  the Gulf of Mexico coast. It is the sole source of positive-bloom labels.
- **Access:** Darwin Core Archive (DwC-A) v1.5 from GBIF/OBIS IPT, downloaded 2026-07-11.
  URL: https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5. No auth required for download.
  Archive contains: `event.txt` (lat/lon/date, event core) + `occurrence.txt` (cell counts,
  occurrence extension) + `extendedmeasurementorfact.txt` + `meta.xml`. Join key:
  `event.txt$id = occurrence.txt$eventID`.
- **Resolution/CRS:** point samples, EPSG:4326.
- **Coverage:** 1953-08-19 to 2021-12-31 (190,341 records total; 169,871 within study bbox).
- **License:** CC0 (per EML metadata).
- **Purpose:** binary HAB label (> 100,000 cells/L, D2/D3); aggregated to cell × date by A3.
  Labels summary: 94,810 cell-day rows; 7,523 positive (7.93%); 87,287 negative (92.07%).
  Pre-2002 records retained in parquet; will be dropped during datacube join (A6) because
  MODIS features begin in 2003.
- **Agent/file:** A3 (habsos-label); `R/03_habsos_labels.R`. Output: `data/processed/habsos_labels.parquet`.
- **Citation:** `\cite{habsos}` (NOAA NCEI / GBIF-OBIS IPT, HABSOS DwC-A v1.5, 2022-09-30).
- **Key caveats:**
  - HABSOS non-detection ≠ proven absence. A `HAB = 0` on a cell-day with a sample reflects
    a measured below-threshold count; a cell-day with **no** HABSOS sample is simply absent
    from the dataset — not represented as a negative at all. `IS_ABSENCE_UNCERTAIN = TRUE`
    on all rows.
  - Label balance (7.93% positive) reflects sampling effort, not true bloom frequency.
    Samples cluster near coastal monitoring stations and known bloom years. Handle class
    imbalance in modeling via class weights (prioritize recall + PR-AUC, per PLAN.md §9).
  - Max count 3.58×10⁸ cells/L flagged for outlier check by A7/R3 before modeling.

### MODIS-Aqua Ocean Color L3 — satellite features
- **What it is:** NASA MODIS-Aqua Level-3 daily mapped ocean color products at 4 km
  resolution: chlorophyll-a (chlor_a), normalized fluorescence line height (nFLH), diffuse
  attenuation at 490 nm (Kd_490), and daytime sea surface temperature (SST). Primary satellite
  feature source. Rrs bands NOT used (nFLH retained as fluorescence proxy; FAI excluded — see
  below).
- **Access:** NASA OB.DAAC file-search API + R `curl` package with NASA Earthdata OAuth
  (`~/.netrc` + cookie jar). Stream-and-discard loop mandatory: per day, download 4 global
  files (~13 MB each) → `terra::crop()` to bbox → `terra::project()` bilinear EPSG:4326 →
  5070 → `terra::zonal()` mean + valid-pixel-count → append Parquet → `unlink()` all raw
  files. Peak disk ≈ 60 MB. Checkpoint by date for resumability.
- **Resolution/CRS:** 4 km (L3m daily mapped); EPSG:4326 native → EPSG:5070 via bilinear
  reproject. Clipped to 24–31°N, 87–81°W; aggregated to 10 km grid (~4–6 MODIS pixels/cell).
- **Coverage:** 2003-01-01 to 2021-12-31 (A4 accessed 2026-07-11). Date scope: 5,829 HABSOS
  sample dates (not full daily era; checkpoint allows incremental extension).
- **License:** NASA open.
- **Purpose:** Level features (chlor_a, nFLH, Kd_490, SST) and trend features (D11, §8-A/B).
  Observed value ranges: chlor_a 0.04–84.3 mg m⁻³; SST 8.5–32.2°C; nFLH −0.23 to +2.15
  mW cm⁻² µm⁻¹ sr⁻¹; Kd_490 0.02–5.94 m⁻¹.
- **Agent/file:** A4 (sat-features); `R/04_satellite_features.R`.
  Output: `data/processed/satellite_features.parquet`.
- **Citations:** `\cite{modis_obdaac_chl}` (CHL DOI 10.5067/AQUA/MODIS/L3M/CHL/2022.0);
  `\cite{modis_obdaac_nflh}` (FLH DOI 10.5067/AQUA/MODIS/L3M/FLH/2022.0);
  `\cite{modis_obdaac_kd490}` (KD DOI 10.5067/AQUA/MODIS/L3M/KD/2022.0);
  `\cite{modis_obdaac_sst}` (SST DOI 10.5067/AQUA/MODIS/L3M/SST/2019.0).
- **Key caveats:**
  - MODIS pixels ~4 km vs. 10 km grid cells — ~4–6 pixels per cell; no sub-cell precision.
  - ~61% of cell-days are cloud-flagged (cloud_flag=TRUE); NAs retained, not zero-filled;
    A6 gap-fills with `feature_filled=TRUE`.
  - FAI excluded: requires MODIS bands at ~859 nm and ~1240 nm not available in OB.DAAC
    L3m; would require L2 swath processing. nFLH used as the available proxy.
    Cite `\cite{hu2009fai}` for FAI definition when explaining this limitation.
  - nFLH negative values retained (real low-biomass retrievals, not errors).
  - Arithmetic mean of chlor_a per cell is upward-biased vs. geometric mean (log-normal
    distribution); acceptable for this application but note in methods.
  - SST daytime product has higher aerosol-correction uncertainty than night SST4; chosen
    for higher Gulf coverage.

### ERA5 — wind (mixing and bloom transport)
- **What it is:** ECMWF ERA5 global atmospheric reanalysis, 10 m u/v wind components at
  ~0.25° (~28 km) resolution. Wind speed, direction, and along-shore/cross-shore components
  used as mixing and bloom-transport features. WFS shoreline orientation ≈ 350° NNW;
  cross-shore = onshore/offshore driver.
- **Access:** Copernicus CDS API (`cdsapi`; `~/.cdsapirc`). Server-side bounding box request
  (`area: [31, -87, 24, -81]`) — no global download. Auth required.
- **Current status: PLACEHOLDER.** No `~/.cdsapirc` on A5's machine. `wind_is_placeholder=TRUE`
  on all rows; wind columns all NA. Pull instructions in `data/raw/weather/manual_downloads.md`.
  Along-shore/cross-shore components NOT YET COMPUTED.
- **Resolution/CRS:** ~0.25° (~28 km), EPSG:4326; interpolated to cell centers.
- **Coverage:** 1979–present.
- **License:** Copernicus License v1.2 (open for research).
- **Purpose:** wind speed/direction/components (§8-A); mixing/upwelling/transport influence
  on bloom dynamics; key features for T+H forecasting.
- **Agent/file:** A5 (env-features); `R/05_environmental_features.R`.
  Output: `data/processed/environmental_features.parquet` (wind columns, placeholder).
- **Citation:** `\cite{hersbach2020era5}`.

### CHIRPS — precipitation (runoff proxy)
- **What it is:** Climate Hazards Center Infrared Precipitation with Stations (CHIRPS v2.0),
  30+ year quasi-global daily rainfall at ~5 km (~0.05°). Rainfall and runoff proxy
  (nutrient loading, freshwater discharge).
- **Access:** UCSB CHC server (https://data.chc.ucsb.edu/products/CHIRPS-2.0/). No auth.
  A5 approach: `terra::rast("/vsigzip//vsicurl/...")` streaming without local storage
  (stream-and-discard per-day; Gulf bbox crop; checkpoint-resumable Parquet).
- **Current status: PLACEHOLDER.** CHC UCSB server returned HTTP 403 (CrowdSec
  bot-detection) during A5 session 2026-07-11. `precip_is_placeholder=TRUE` all rows.
  No auth needed; retry after ~24 h or from different IP. Re-run
  `R/05_environmental_features.R` to resume from checkpoint. Instructions in
  `data/raw/weather/manual_downloads.md`.
- **Resolution/CRS:** ~0.05° (~5 km), EPSG:4326.
- **Coverage:** 1981–present; 50°S–50°N.
- **License:** UCSB open.
- **Purpose:** precipitation history over prior 3/7/14 days; heavy-rain indicator (§8-A).
- **Agent/file:** A5 (env-features); `R/05_environmental_features.R`.
  Output: `data/processed/environmental_features.parquet` (precip columns, placeholder).
- **Citation:** `\cite{funk2015chirps}`.

### SMAP — sea-surface salinity (broad-context; PLACEHOLDER)
- **What it is:** RSS SMAP Level-3 8-day running mean sea-surface salinity (~0.25° /
  40–70 km sensor footprint). Stratification and freshwater-discharge proxy.
- **Access:** PODAAC CMR search + OPeNDAP download; Earthdata auth (`~/.netrc`).
  OPeNDAP/CMR workflow complex; deferred by A5.
- **Current status: PLACEHOLDER.** `salinity_pss=NA`, `salinity_is_placeholder=TRUE`,
  `salinity_coarse_flag=TRUE` (unconditional — independent of placeholder status).
  Coverage window: 2015-04-01 to present; pre-2015 dates have no salinity feature.
  Pull instructions in `data/raw/weather/manual_downloads.md`.
- **Resolution/CRS:** ~40–70 km sensor footprint; ~0.25° gridded; EPSG:4326.
- **Coverage:** 2015-04-01 to present.
- **License:** NASA/RSS open.
- **Purpose:** salinity as broad-context stratification feature (§8-A). `salinity_coarse_flag`
  must appear in all tables and figures — do not interpret per-cell with fine-scale meaning.
- **Agent/file:** A5 (env-features); `R/05_environmental_features.R`.
  Output: `data/processed/environmental_features.parquet` (salinity columns, placeholder).
- **Citation:** `\cite{meissner2018smap}` (VERIFIED: DOI corrected to 10.3390/rs10071121,
  *Remote Sensing* 10(7):1121, Meissner/Wentz/Le Vine 2018 — A5 script had wrong DOI
  10.3389/fmars.2018.00349, which resolves to a coral reef paper; corrected by A-DOC
  2026-07-11 in both references.bib and data_sources.md).
- **Key caveats:** (1) ~40–70 km >> 10 km grid; broad-context only. (2) Pre-2015 coverage
  gap is informative missingness — A7 must not treat it as random. (3) Placeholder: pull
  when OPeNDAP auth is implemented.

### GEBCO 2026 — bathymetry
- **What it is:** General Bathymetric Chart of the Oceans (GEBCO) 2026 Grid at 15 arc-second
  (~450 m) resolution. Used for per-cell mean depth feature and (in A9) intra-cell attention
  drill-down context layer.
- **Access:** GEBCO queue API (`download.gebco.net/api/queue`); POST with Gulf bbox
  and data_source_id=1 (bathymetry), GeoTIFF format; poll status; download ~5 MB zip.
  No auth required. A5 downloaded Gulf subset (24–31°N, 87–81°W) 2026-07-11.
- **Resolution/CRS:** 15 arc-second (~450 m), EPSG:4326 → bilinear reproject to EPSG:5070.
  Per-cell mean via `terra::extract()`.
- **Coverage:** global, static (GEBCO 2026 release).
- **Status: REAL** — `depth_m` column in `static_geo.parquet`. Depth range: −3,539 to +95 m.
  24 edge cells have NA (peripheral bbox coverage); marked IS_PLACEHOLDER=TRUE.
- **License: NON-COMMERCIAL (GEBCO Terms of Use).** Same restriction as MEOW (Spalding 2007).
  If GEBCO depth or bathymetric maps appear in any figure, supplementary, or appendix:
  (1) include GEBCO attribution; (2) confirm target venue permits non-commercial components.
  Alternative: ETOPO (NOAA NCEI, public domain) if open license required.
- **Purpose:** static depth feature (§8-A); intra-cell attention context (D12/§2.3, A9).
- **Agent/file:** A5 (env-features), A9 (gis); `R/05_environmental_features.R`, `R/09_gis_export.R`.
  Output: `data/processed/static_geo.parquet` column `depth_m`.
- **Citation:** `\cite{gebco2026}` (DOI 10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f — VERIFIED
  from A5 script header 2026-07-11).

### Census TIGER 2023 — county boundaries + coastline
- **What it is:** US Census Bureau TIGER/Line 2023 county polygons and national coastline
  for Gulf-state FIPS (01 AL, 12 FL, 13 GA, 22 LA, 28 MS, 48 TX). Two uses:
  (1) county spatial blocks for cross-validation; (2) coastline for distance-to-shore.
- **Access:** Direct download (no auth). Files: `tl_2023_us_county.zip` (~83 MB),
  `tl_2023_us_coastline.zip`. URL: https://www2.census.gov/geo/tiger/TIGER2023/
  Downloaded by A5 2026-07-11.
- **Resolution/CRS:** Vector; native EPSG:4269 → EPSG:5070.
- **Coverage:** 2023 vintage (static).
- **License:** Public domain (US government work).
- **Purpose:**
  1. `spatial_block_tiger` — THE geographic blocking column for spatial CV (A6/A7/A11).
     82 unique county blocks across 4,743 cells. Ocean cells assigned via
     `st_nearest_feature()` to nearest coastal county. Per Lead Directive 2026-07-11
     (Queen-contiguity unusable — 1 component; county blocks are the required substitute).
  2. `dist_to_shore_m` — Euclidean distance from each cell centroid to nearest coastline
     segment in EPSG:5070 (metric). Range: 17 m–429 km.
- **Agent/file:** A5 (env-features); `R/05_environmental_features.R`.
  Output: `data/processed/static_geo.parquet` columns `spatial_block_tiger`, `county_fips`,
  `county_name`, `state_fips`, `dist_to_shore_m`.
- **Citation:** `\cite{census_tiger}` (2023 vintage — VERIFIED; public domain).

---

## Methods

### Study area definition
- **Description:** The study domain is the West Florida Shelf, defined in code as a geographic
  bounding box: 24–31°N, 87–81°W. No hand-drawn polygon is used; the box is constructed with
  `sf::st_bbox()` → `st_as_sfc()` in EPSG:4326, then projected to Albers EPSG:5070.
- **Rationale:** This extent is the established MODIS *K. brevis* study area from Hu et al.
  (2022), matching how the ocean-color community grids the West Florida Shelf.
- **Agent/file:** A2 (grid-clean); `R/02_build_grid.R`.
- **Citation:** `\cite{hu2022karenia}`.
- **NOTE(paper) tag:** `R/02_build_grid.R` (harvested 2026-07-11).

### Spatial projection — Albers Equal Area CONUS (EPSG:5070)
- **Description:** All spatial layers are reprojected to Albers Equal Area Conic (EPSG:5070,
  North American Datum 1983, CONUS Albers). This projection preserves area, enabling metric
  distance calculations and a regular 10 km grid.
- **Rationale:** Metric projection required for `cellsize = 10000` (meters) in `st_make_grid`;
  standard CONUS projection avoids distortion over the study area.
- **Agent/file:** A2 (grid-clean); `R/02_build_grid.R`.
- **Citation:** USGS standard CONUS Albers / EPSG:5070 registry. No specific paper required.
- **NOTE(cite) tag:** `R/02_build_grid.R` (harvested 2026-07-11).

### Grid construction — 10 km × 10 km regular grid (Green RTM method)
- **Description:** The study area is tiled into regular 10 km × 10 km cells using
  `sf::st_make_grid(cellsize = 10000, what = "polygons", square = TRUE)` in EPSG:5070.
  Each cell receives a unique `cell_id` identifier. The grid contains 4,743 cells covering
  the study bbox. Point observations (HABSOS, satellite, weather) are joined to cells via
  `sf::st_within()` (inner join — points outside the grid are dropped).
- **Rationale:** 10 km cell size is larger than the ~4.6 km MODIS L3 pixel, ensuring each
  cell aggregates real pixel data (not sub-pixel false precision), while remaining below the
  coarse wind/salinity grids (~28 km at 0.25°). Cell size and method follow the mentor's
  demonstrated `gulf` script and RTM gridding approach (Green 2022).
- **Agent/file:** A2 (grid-clean); `R/02_build_grid.R`, `R/utils_spatial.R`. Output: `data/processed/study_area_grid.gpkg` (4,743 cells, 1.1 MB, EPSG:5070).
- **Citations:** `\cite{green2022rtm}` (gridding method); `\cite{pebesma2018sf}` (sf package).
- **NOTE(paper) / NOTE(cite) tags:** `R/02_build_grid.R` (harvested 2026-07-11).

### Spatial cluster labeling for split grouping
- **Description:** Each grid cell is assigned a `spatial_cluster` label via Queen contiguity
  (shared edge or corner, DE-9IM pattern `"****1****"`) and union-find BFS. For this
  rectangular grid, all 4,743 cells form one connected component (`n_clusters = 1`).
  Consequently, A7/A11 must implement spatial splits using geographic sub-regions (grid
  quadrant or county intersection), not connected-component IDs.
- **Rationale:** Queen contiguity is more conservative than Rook (includes corner-sharing
  neighbors), producing larger, safer held-out spatial folds and preventing spatially
  autocorrelated cells from straddling train/test boundaries (R-SPLIT requirement, PLAN.md §6.0).
- **Agent/file:** A2 (grid-clean); `R/utils_spatial.R` (`flag_spatial_clusters()`). Column `spatial_cluster` in `study_area_grid.gpkg`.
- **Citation:** Novel / mentor's method (adapted from RTM spatial grouping). `\cite{pebesma2018sf}` for sf operations.

### Binary HAB label construction
- **Description:** HABSOS records within the study bbox are joined to the grid via
  `sf::st_join(st_within)`, then aggregated per (cell_id × sample_date) by taking
  `max(organism_quantity)` across all samples in the cell on that day. A cell-day is
  labeled `HAB = 1` if `max_count > 100,000 cells/L`; otherwise `HAB = 0`. The
  Darwin Core Archive join connects `event.txt` (lat/lon/date) to `occurrence.txt`
  (cell counts) on `eventID` via `data.table::merge()`. Two parse-corrupt event rows
  (broken lat field) were dropped pre-merge; the rest are intact.
- **Rationale:** max aggregation: the bloom threshold is a point-exceedance criterion;
  max is biologically defensible (a bloom anywhere in the cell on that day = bloom day).
  100,000 cells/L is the standard bloom-level threshold in prior *K. brevis* remote-
  sensing studies (D2, D3). Binary framing is the simplest defensible MVP.
- **Agent/file:** A3 (habsos-label); `R/03_habsos_labels.R`. Output: `data/processed/habsos_labels.parquet`.
- **Citations:** `\cite{habsos}` (HABSOS DwC-A v1.5); `\cite{hu2022karenia}` (threshold precedent); `\cite{pebesma2018sf}` (sf spatial join).
- **NOTE() tags:** `R/03_habsos_labels.R` (harvested 2026-07-11): NOTE(paper) on DwC-A join key; NOTE(cite) on HABSOS dataset; NOTE(limitation) on non-detection / label balance.

### Forecasting frame — no look-ahead (D5)
- **Description:** The model predicts `HAB` for grid cell *c* at day *T+H* using only features
  observed on or before day *T*. Horizon H ∈ {1, 3, 5, 7, 14} days.
- **Rationale:** Forecasting, not detection. Any rolling mean, lag, or trend feature must have
  a timestamp ≤ T. The T+H label is attached in A6 (datacube), with a hard assertion that no
  feature timestamp exceeds T.
- **Agent/file:** A6 (datacube); `R/06_build_datacube.R`.
- **Citation:** PLAN.md §2.2 (project design decision; no external citation needed for the
  framing itself).

### Trend / rate-of-change features (D11)
- **Description:** For each continuous level feature (chlor_a, nFLH, FAI, SST, Kd490, etc.),
  the datacube computes: (a) absolute deltas x_T − x_{T−k} for k ∈ {1,3,5,7}; (b) relative
  day-over-day % change (x_T − x_{T−1})/x_{T−1}; (c) trailing linear-fit slope over
  3/5/7-day windows; (d) threshold-crossing flags (e.g., chl-a up >X% DoD for ≥N consecutive
  days); (e) rolling 3-day and 7-day means and standard deviations.
- **Rationale:** The forecasting signal lies as much in *movement* as in *level* (PLAN.md D11).
  A cell can be high-risk because chlorophyll is elevated (level) or because it is climbing
  fast from a low base (trend).
- **Agent/file:** A6 (datacube); `R/06_build_datacube.R`.
- **Citation:** PLAN.md D11 (project design). Cloud-gap handling in slopes follows best
  practices from the MODIS ocean color literature — A4 to cite specific reference when known.

### MODIS stream-and-discard processing
- **Description:** MODIS L3 is distributed as global daily files (~15 MB each); no server-side
  bounding box is available. Processing pipeline: (1) download one day's global file →
  (2) clip to 24–31°N/87–81°W → (3) aggregate to 10 km grid cells → (4) append cell rows
  to the Parquet feature table → (5) delete the raw file (`R::unlink()`). Loop is resumable
  via date checkpoint.
- **Rationale:** Prevents storage overflow that would result from bulk-downloading the ~300–500 GB
  archive (2003–present). Peak disk usage ≈ one file (~15 MB) + growing Parquet.
- **Agent/file:** A4 (sat-features); `R/04_satellite_features.R`.
- **Citation:** PLAN.md §6 A4 / CLAUDE.md (project requirement, not an external citation).

### Config-driven pipeline
- **Description:** All pinned decisions (study-area bbox, cell size, label threshold, forecast
  horizons, trend windows, random seed) are stored in `config.yaml` and loaded by
  `R/00_config.R` (sourced at the top of every script). This ensures reproducibility and
  provides a single citation anchor for design parameters in the write-up.
- **Agent/file:** `R/00_config.R`, `config.yaml`.
- **NOTE(paper) tag:** `R/00_config.R` (harvested 2026-07-11).

---

## Modeling

_A7 entries added 2026-07-11. A8 (explainability/SHAP), A11 (transformer) entries pending._

### Forecasting target
- **Description:** The forecasting target is the binary HAB label for cell *c* at day *T+H*,
  predicted from level + trend features observed through day *T*. This makes it a genuine
  forecast (not nowcasting or detection), earned by the T+H offset in the label assignment.
- **Agent/file:** PLAN.md D5/§2.2; enforced in A6 (datacube).
- **Citation:** PLAN.md §2.2 (design decision).

### Evaluation protocol
- **Description:** All models are evaluated under three split strategies: (1) random; (2)
  temporal (train earlier years, test later); (3) spatial (hold out counties/regions with
  grouped splits to prevent adjacent-cell leakage). Every metric is reported per horizon
  H ∈ {1,3,5,7,14}. Primary metrics: recall, PR-AUC, F1, ROC-AUC; false-negative rate
  reported first (a missed bloom > a false alarm for early warning).
- **Agent/file:** A7 (modeling), A10 (validation).
- **Citation:** PLAN.md §9 (project design).

### Baselines
- **Description:** Two reference baselines: (a) persistence/naive ("no change from T" —
  HAB at T+H equals HAB at T); (b) chlorophyll-a-only classifier. Both stages (RF and
  transformer) must be compared against these in a single table.
- **Agent/file:** A7, A11. Implemented in A7 2026-07-11 via `baseline_persistence()` and
  `baseline_chl_only()` in `R/07_modeling.R`.
- **Citation:** PLAN.md §9 (project design).
- **NOTE:** Persistence baseline exploits same-day HAB at T (unavailable to RF as a feature).
  Its recall advantage at H=7 (0.627 vs RF 0.370) is structural, not informative about
  RF performance. Compare on PR-AUC instead (persistence 0.450 < RF 0.497).

### Random Forest (Stage-1) — ranger implementation
- **What it is:** `ranger::ranger(probability=TRUE, num.trees=500, num.threads=1,
  case.weights)`. One binary HAB classifier per H ∈ {1,3,5,7,14}. Class weight =
  n_neg/n_pos for positive class; 1.0 for negative. Best model: H=7 temporal RF
  (`models/best_model.rds`). IMPLEMENTED A7 2026-07-11.
- **Agent/file:** A7 (modeling); `R/07_modeling.R`. Outputs: `results/model_results.csv`,
  `models/best_model.rds`, `figures/` (confusion/ROC/PR plots, skill_vs_horizon.png).
- **Citations:** `\cite{breiman2001rf}` (Breiman 2001, *Machine Learning* 45(1):5–32,
  DOI 10.1023/A:1010933404324 — VERIFIED); `\cite{wright2017ranger}` (Wright & Ziegler
  2017, *Journal of Statistical Software* 77(1):1–17, DOI 10.18637/jss.v077.i01 — VERIFIED).
- **Use in paper:** Methods (Stage-1 classifier description, class-weighting rationale).

### log1p feature transforms
- **What it is:** Applied to 3 satellite level features before RF: (a) `chlor_a_mean` →
  `log1p(max(x,0))`; (b) `nflh_mean` → `sign(x)×log1p(|x|)` (signed — preserves negatives
  over clear water); (c) `Kd_490_mean` → `log1p(max(x,0))`. Trend/delta features NOT
  transformed (can be negative; RF splits are robust to monotone transforms).
- **Rationale:** Satellite chlor_a is log-skewed; binary label absorbs count extremes.
- **Agent/file:** A7; `R/07_modeling.R`.
- **Citation:** Standard preprocessing practice; no specific external citation needed.
  Rationale in A7 decision block (`reports/agent_logs/modeling.md`).
- **Use in paper:** Methods (feature preprocessing).

### Median imputation with missingness indicator
- **What it is:** Missing values imputed with training-partition medians (no test data
  used for imputation). Binary `{col}_is_missing` flag added per imputed column, allowing
  RF to exploit cloud-cover gap patterns as a predictive signal.
- **Agent/file:** A7; `R/07_modeling.R::impute_with_flag()`.
- **Citation:** Imputation-with-indicator principle from van Buuren & Groothuis-Oudshoorn
  2011 (mice) — cited in A7 decision block. Bib entry TBD when A8 formally cites it.
- **Use in paper:** Methods (feature preprocessing, missingness-as-signal rationale).

### Three-split evaluation: temporal (PRIMARY), spatial-block, random
- **What it is:** All RF models evaluated under: (1) temporal — train 2003–2015, test
  2016–2021 (PRIMARY HONEST); (2) spatial-block — county holdout ≥15% rows; (3) random —
  80/20 stratified (optimistic reference).
- **CRITICAL framing:** Only temporal split is the honest forecasting assessment. Spatial
  result is "geographic transfer to a high-prevalence region" (not better generalization —
  see R-SPLIT caveat in Limitations). Random is inflated by spatial autocorrelation.
- **Agent/file:** A7; `R/07_modeling.R`.
- **Citation:** PLAN.md §9 (split design).
- **Use in paper:** Methods (evaluation design); Results (temporal-split tables are headline);
  Discussion (spatial caveat; random as optimistic reference).

### PR-AUC (primary evaluation metric)
- **What it is:** Precision-recall AUC (trapezoidal) is the primary metric for all Stage-1
  RF results. ROC-AUC reported as secondary. Chosen because HAB labels are ~8% positive —
  ROC-AUC overstates discrimination performance under class imbalance.
- **Agent/file:** A7; `R/07_modeling.R::pr_auc_fn()`.
- **Citation:** `\cite{davis2006prcurves}` (Davis & Goadrich 2006, ICML — VERIFY-DOI;
  bib entry added 2026-07-11).
- **Use in paper:** Methods (metric justification); all Results tables and figures.

---

## Results

### HABSOS labels summary (A3, `data/processed/habsos_labels.parquet`)

| Metric | Value |
|---|---|
| Total cell-day rows | 94,810 |
| HAB = 1 (positive) | 7,523 (7.93%) |
| HAB = 0 (negative) | 87,287 (92.07%) |
| Threshold | > 100,000 cells/L (D2) |
| Date range | 1953-08-19 to 2021-12-31 |
| IS_PLACEHOLDER | FALSE (real grid join) |
| IS_ABSENCE_UNCERTAIN | TRUE (all rows) |
| max_count range | 0 to 3.58×10⁸ cells/L |

Source: `reports/agent_logs/habsos-label.md` (2026-07-11). Pre-MODIS records (pre-2002) retained in parquet but will be excluded from datacube join (A6) since MODIS features begin 2003.

### Stage-1 RF — temporal-split headline metrics (A7, `results/model_results.csv`)

**PRIMARY HONEST FORECASTING RESULTS** — temporal split: train 2003–2015, test 2016–2021.
Source: `reports/agent_logs/modeling.md` (2026-07-11).

#### H=7 (n_test=8,880; n_pos=1,075; 8.4% positive)

| Model | Recall | PR-AUC | ROC-AUC | F1 |
|---|---|---|---|---|
| RF (Stage-1) | 0.370 | **0.497** | 0.832 | 0.455 |
| Persistence baseline | 0.627 | 0.450 | 0.821 | 0.625 |
| Chl-only baseline | 0.080 | 0.142 | 0.542 | 0.114 |

#### H=14 (n_test=9,021; n_pos=1,010; 7.9% positive)

| Model | Recall | PR-AUC | ROC-AUC | F1 |
|---|---|---|---|---|
| RF (Stage-1) | 0.272 | **0.445** | 0.812 | 0.372 |
| Persistence baseline | 0.523 | 0.320 | 0.762 | 0.512 |
| Chl-only baseline | 0.069 | 0.122 | 0.526 | 0.102 |

**Key results for manuscript:**
- RF beats persistence on PR-AUC at both horizons (H=7: +0.047; H=14: +0.125).
- Persistence recall advantage is structural (exploits same-day HAB unavailable to RF).
- RF substantially beats chl-only (H=7 PR-AUC +0.355): full feature suite adds clear value.
- Present the full H × metric table (required figure D6: skill-vs-horizon decay curve,
  `figures/skill_vs_horizon.png`). Skill decay with increasing H is an expected result.

_All other result tables/figures pending A8 (SHAP/explainability), A9 (GIS maps), A10 (validation), A11 (transformer)._

---

## Limitations

- **HABSOS non-detection ≠ proven absence.** A HAB=0 label on a cell-day reflects the absence
  of a HABSOS sample, not a confirmed bloom-free condition. The observing network has spatial
  and temporal gaps; negative labels may represent unsampled locations. State this wherever
  labels are used. Source: `R/01_source_data.R` NOTE(limitation); PLAN.md §1; `\cite{habsos}`.

- **MODIS pixel size vs. grid cell.** MODIS L3 pixels are ~4.6 km; a 10 km grid cell spans
  only ~4–6 pixels. Cell statistics (mean, max) aggregate genuine variation but do not imply
  sub-pixel precision. Do not claim sub-cell spatial accuracy. Source: `R/02_build_grid.R`
  NOTE(paper); PLAN.md §5 resolution reality check.

- **SMAP salinity resolution mismatch.** SMAP salinity is ~40–70 km, far coarser than the
  10 km grid. Each cell's salinity value may be shared across dozens of cells. Flag as a
  broad-context feature in all tables and figures; do not interpret salinity per-cell with
  fine-scale meaning. Source: `data/metadata/data_sources.md`; PLAN.md §5.

- **Intra-cell attention drill-down is diagnostic, not a sub-cell forecast.** The model
  predicts at the 10 km cell. The drill-down (D12/§2.3) shows where the flag-driving features
  concentrate within the cell, down to native ~4 km MODIS pixels. It carries no validated
  forecasting skill below the cell level. Label all such views as "where flagging conditions
  concentrate" — never as a sub-cell risk score. Source: PLAN.md §2.3.

- **No causal claims.** The model identifies patterns associated with bloom events; it does not
  establish causation. Use "associated with," "predictive of," or "correlated with." Source:
  PLAN.md §1 guardrails.

- **No "first ever" or "operationally ready" claims.** Prior work exists (HABNet, NOAA
  operational HAB forecasting, mentor's RTM work). The contribution is a reproducible,
  interpretable, GIS-integrated early-warning workflow on public data. A model is
  "operationally ready" only if it survives hard temporal and spatial validation splits (§9).
  Source: PLAN.md §1.

- **Label balance (7.93% positive) reflects sampling effort, not true bloom frequency.**
  HABSOS samples cluster near coastal monitoring stations and temporally toward known bloom
  years. Class imbalance must be addressed in modeling via class weights — do not oversample
  or report random-split accuracy as the headline metric. Recall and PR-AUC are primary
  (PLAN.md §9). Source: `reports/agent_logs/habsos-label.md` NOTE(limitation) (2026-07-11).

- **Single connected component.** The 4,743-cell rectangular grid forms one Queen-contiguity
  cluster, so spatial splits cannot use connected-component IDs. A7/A11 must split by
  geographic sub-region (grid quadrant or county intersection). Source:
  `reports/agent_logs/grid-clean.md` (2026-07-11).

- **Pre-2002 HABSOS records.** Labels extend back to 1953 but MODIS-Aqua began in 2003.
  Pre-2002 cell-days are retained in `habsos_labels.parquet` but will be excluded during
  datacube join (A6). This is expected behavior, not a data loss. Source:
  `reports/agent_logs/habsos-label.md` (2026-07-11).

- **HABSOS max count 3.58×10⁸ cells/L.** This extreme value (~3,580× the bloom threshold)
  should be verified by A7/R3 as a real dense-bloom aggregate or potential data-entry error
  before training. Source: `reports/agent_logs/habsos-label.md` (2026-07-11).

- **~~HABSOS coordinate gap~~** — RESOLVED: A3 obtained full DwC-A v1.5 from GBIF/OBIS IPT
  (https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5). event.txt carries lat/lon/date.
  Removed as open blocker.

- **GEBCO 2026 license (non-commercial).** GEBCO Terms of Use restrict commercial use. If
  `depth_m` values or any GEBCO-derived bathymetric map appear in any figure or output,
  confirm the target venue permits non-commercial-licensed data. Alternative: ETOPO (NOAA
  NCEI, public domain) for venues requiring fully open licensing. Flag all figures using
  GEBCO with attribution. Source: `reports/agent_logs/env-features.md` (2026-07-11);
  flagged by A-DOC.

- **MEOW dataset license (CC BY-NC).** If Spalding et al. (2007) MEOW ecoregion polygons
  are used in any figure or GIS export, the output carries a CC BY-NC restriction. Confirm
  whether the target venue (journal, poster, competition) permits NC-licensed components. If
  not, substitute the Flanders Marine Institute IHO Sea Areas (CC-BY 4.0). Source:
  `paper/refs_pdfs/Ready-Made Boundary Files...pdf` (2026-07-11); flagged by A-DOC.

- **Several related-work author lists abbreviated.** Bib entries for izadi2021kb,
  carvalho2011modis, hill2020habnet, yao2023viirs currently use "and others" for author
  fields (karki2018modis now fully expanded). Before final manuscript, expand each from the
  DOI page. A7/A8/A11 should flag if they cite any of these in modeling sections so A-DOC
  can prioritize resolving them.

- **Spatial prevalence confound (R-SPLIT caveat).** The spatial-block holdout always
  isolates Collier County (12_115), the dominant HAB hotspot, with 11.4% positive rate
  vs. 8.4% in the temporal test set (1.35× prevalence inflation). Spatial PR-AUC at H=7
  (0.663) exceeds random (0.631) due to this prevalence difference, **not** better
  geographic generalization. Additionally, 14.6% of spatial test cells fall within ~10 km
  of training cells at block borders, introducing residual spatial autocorrelation. Describe
  spatial results as "geographic transfer to a high-prevalence region." Use temporal
  PR-AUC=0.497 (H=7) as the honest headline. Source: `reports/agent_logs/modeling.md`
  NOTE(paper) (2026-07-11).

- **Temporal zero-embargo (R-SPLIT caveat).** No purge/embargo gap was applied at the 2016
  train/test boundary. At H=14, ~49 training rows (0.33%) have label_date (T+14) in the
  test period, producing a small optimistic leak bounded by HABSOS sparsity. Effect on
  PR-AUC is estimated as negligible but not zero. Report alongside temporal-split metrics;
  note future iterations should add an H-day embargo window. Source:
  `reports/agent_logs/modeling.md` NOTE(limitation) (2026-07-11).

- **Stage-1 RF excludes dynamic env features (ERA5/CHIRPS/SMAP placeholder).** Wind,
  precipitation, and salinity columns are all-NA placeholder in model_dataset.parquet.
  All 6 dynamic env columns hard-excluded from predictor matrix. Stage-1 RF uses only:
  satellite features + trend suite + static geography + seasonality + historical HAB lags.
  Recall at short horizons (H=1,3,5) is expected to improve once meteorological forcing
  features are added. Source: `reports/agent_logs/modeling.md` NOTE(limitation) (2026-07-11).

- **Short-horizon models lower confidence (H=1, H=3).** H=1 (7,791 labelled rows) and
  H=3 (4,765 rows) have insufficient samples for reliable temporal or spatial split training.
  Flag as "lower confidence due to sparse training sample" in all results tables and figures.
  Primary statistical power is at H=7 (23,751 rows) and H=14 (23,889 rows). Source:
  `reports/agent_logs/modeling.md` NOTE(limitation) (2026-07-11).
