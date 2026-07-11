# sat-features — decision & methods log

**Agent:** A4 sat-features
**Task:** MODIS-Aqua satellite features aggregated to the 10 km study grid
**Output:** `data/processed/satellite_features.parquet`
**Script:** `R/04_satellite_features.R`
**Log date:** 2026-07-11

---

## Decisions

- **Products selected:** chlor_a (CHL), SST (SST), nFLH (FLH), Kd_490 (KD). These four represent the most directly bloom-relevant, widely-available daily MODIS L3m products. FAI was explicitly excluded (see Limitations). — 2026-07-11
- **FAI excluded:** FAI (Floating Algae Index, Hu 2009) requires MODIS bands at ~859 nm and ~1240 nm that are NOT distributed in OB.DAAC L3m products. Would require L2 processing beyond current scope. nFLH retained as the available fluorescence-based bloom proxy. — 2026-07-11
- **4 km resolution chosen over 9 km:** 4 km L3m product matches the PLAN §2 D4 rationale (10 km cells must span >1 pixel for real aggregation). 9 km would give ~1 pixel per cell — no meaningful aggregation. — 2026-07-11
- **SST daytime product (L3m.DAY.SST.sst.4km):** Chose daytime SST over night SST4. Night SST4 is less affected by aerosols but has lower Gulf of Mexico coverage due to nighttime orbit geometry. Daytime maximizes coverage at the cost of slightly higher atmospheric correction uncertainty. — 2026-07-11
- **SST quality layer discarded:** The SST NetCDF ships `sst` + `qual_sst` bands. Only the `sst` band is extracted; `qual_sst` is a quality flag raster that should not be averaged spatially. Selected by layer name in `aggregate_to_grid()`. — 2026-07-11
- **cloud_flag definition:** A cell-day is cloud-flagged (cloud_flag=TRUE) if the sum of valid pixel counts across ALL 4 products is 0. Cells with at least one valid pixel in any product are not flagged — they may still have missing values for individual products. — 2026-07-11
- **Date scope:** Intersected with HABSOS sample dates in satellite era (2003-01-01 to 2021-12-31) → 5,829 unique dates. Full daily era (every day 2003-2021) not attempted in single session; checkpoint system allows incremental extension. — 2026-07-11
- **FLUSH_EVERY = 50 dates:** Write to Parquet every 50 processed dates. Balance between disk I/O overhead and memory accumulation (~237,000 rows per flush). — 2026-07-11
- **Reprojection method:** bilinear interpolation for crop+project step (terra::project). Appropriate for all MODIS ocean color continuous variables. Nearest-neighbor would be correct for categorical/flag data but all four products are continuous. — 2026-07-11
- **Aggregation method:** Mean of valid (~non-NA) MODIS pixels within each 10 km cell via terra::zonal(). For chlor_a, this is the arithmetic mean; a geometric mean might better reflect the log-normal distribution of chlorophyll but would complicate downstream rolling stats. Logged as a limitation. — 2026-07-11

---

## Data sources used

- **MODIS-Aqua L3m Daily CHL** — NASA OB.DAAC file-search API + `curl` download — Accessed 2026-07-11 — DOI: 10.5067/AQUA/MODIS/L3M/CHL/2022.0 — Public — chlorophyll-a feature
- **MODIS-Aqua L3m Daily SST** — NASA OB.DAAC — Accessed 2026-07-11 — DOI: 10.5067/AQUA/MODIS/L3M/SST/2019.0 — Public — sea surface temperature
- **MODIS-Aqua L3m Daily FLH** — NASA OB.DAAC — Accessed 2026-07-11 — DOI: 10.5067/AQUA/MODIS/L3M/FLH/2022.0 — Public — normalized fluorescence height
- **MODIS-Aqua L3m Daily KD** — NASA OB.DAAC — Accessed 2026-07-11 — DOI: 10.5067/AQUA/MODIS/L3M/KD/2022.0 — Public — diffuse attenuation at 490 nm
- **Access method:** OB.DAAC file-search API (`https://oceandata.sci.gsfc.nasa.gov/api/file_search?sensor=MODISA&dtype=L3m&addurl=1&results_as_file=1&search=*DAY*<PROD>*4km*.nc`) + authenticated curl download via NASA Earthdata OAuth (credentials in `~/.netrc`)
- **File naming pattern:** `AQUA_MODIS.YYYYMMDD.L3m.DAY.<PROD>.<var>.4km.nc`
- **Grid:** `data/processed/study_area_grid.gpkg` (A2 output, 4,743 cells, EPSG:5070)
- **Date list:** from `data/processed/habsos_labels.parquet` (A3 output, `sample_date` column)

---

## Methods & techniques

- **OB.DAAC file-search API** — URL construction per product/date; returns direct download URL — `R/04_satellite_features.R:obdaac_url()` — no parameters; sensor=MODISA, dtype=L3m, daily
- **Authenticated download** — R `curl` package (`curl_download()` + `new_handle()`) with netrc=1, cookie jar for NASA Earthdata OAuth redirect chain — `download_modis()` — timeout=300s, low_speed_limit=1 KB/s
- **terra::crop()** — Crop global MODIS raster to bbox ext(-87, -81, 24, 31) before reprojection to reduce memory — `aggregate_to_grid()` — bbox from config.yaml
- **terra::project()** — Bilinear reproject from WGS84 (EPSG:4326) to Albers Equal Area (EPSG:5070) for metric-consistent aggregation — `aggregate_to_grid()`
- **terra::rasterize() + terra::zonal()** — Rasterize 10 km vector grid cells onto reprojected MODIS raster, then compute per-zone mean and valid-pixel count — `aggregate_to_grid()` — fun='mean', na.rm=TRUE
- **Stream-and-discard loop** — Per date: download 4 global files (~10-15 MB each) → clip → project → zonal → unlink() → next day. Peak disk ≈ 60 MB at a time. — `R/04_satellite_features.R` main loop — mandatory per PLAN.md §6-A4 / CLAUDE.md
- **Checkpoint by date** — On re-run, load existing output Parquet, extract processed dates, skip them. Allows resumable incremental processing. — main script startup block
- **cloud_flag** — Boolean column; TRUE if sum of all 4 products' n_valid == 0 for a cell-day. Not zero-filled; A6 handles gap-filling with `feature_filled` flag. — per PLAN §6-A4 checks

---

## Open questions / caveats / limitations

- **FAI not available in L3m:** FAI (Floating Algae Index, Hu 2009) requires MODIS bands 1 (~645 nm), 2 (~859 nm), 7 (~2130 nm) that are not published as L3m daily mapped products by OB.DAAC. Including FAI would require processing L2 swath files — a significantly more complex pipeline. nFLH is used as the available fluorescence-based proxy. The author should note this gap.
- **~61% cloud cover (cell-days):** On any given day, the majority of Gulf cells have no valid ocean color retrievals (cloud cover, sun glint, high sensor zenith angle). This is expected for MODIS over the Gulf of Mexico. A6 should handle this via forward/backward fill within valid periods with `feature_filled=TRUE`.
- **Arithmetic mean of chlor_a:** Chlorophyll-a is log-normally distributed. Arithmetic mean of 4-6 pixel values per cell is simpler but upward-biased vs. geometric mean. Conservative for bloom detection (bloom pixels inflate the mean). Documented, not changed, for downstream consistency.
- **Date coverage:** This script processes only HABSOS sample dates (5,829 dates). Full daily era (6,935 days) would provide denser time series for rolling stats. The checkpoint system allows extension.
- **nFLH negative values retained:** Negative nFLH values occur over clear, low-biomass water (instrument noise, sub-pixel atmospheric correction). Range observed: -0.23 to +2.15 mW cm⁻² µm⁻¹ sr⁻¹. These are real retrievals, not errors; A6/A7 should be aware.
- **SST atmospheric correction:** Daytime SST has higher aerosol-correction uncertainty than night SST4. Near-coast pixels may have residual contamination. Consider flagging coastal cells for validation.
- **Pixel count per cell:** MODIS 4 km vs. 10 km cell → ~4-6 pixels per cell on the diagonal. Cells touching the coast or land boundary may have fewer. Minimum observed: 1 pixel. Reported in `*_n_valid` columns.

---

## Done-criteria (§6 A4) — pass/fail

| Criterion | Status | Note |
|-----------|--------|------|
| Script runs end-to-end | ✅ PASS | Verified on 5-date test; background pipeline running |
| Script is resumable by date | ✅ PASS | Checkpoint reads existing Parquet at startup; skips done dates |
| Produces real per-cell×date features | ✅ PASS | IS_PLACEHOLDER=FALSE for all rows; values in expected physical ranges |
| Satellite era only (2003-2021) | ✅ PASS | Pre-2003 rows have no satellite features (A6 join handles) |
| Deletes raw files each iteration | ✅ PASS | `unlink(dest)` immediately after `aggregate_to_grid()` call |
| Header + NOTE tags present | ✅ PASS | Header block + NOTE(paper)/NOTE(cite)/NOTE(limitation) in script |
| Cells with no valid pixels flagged | ✅ PASS | `cloud_flag=TRUE` for 61% of cell-days (expected Gulf cloud cover) |
| Not zero-filled | ✅ PASS | NAs retained for cloud-masked cells; `feature_filled=FALSE` from A4 |
| IS_PLACEHOLDER column | ✅ PASS | Always FALSE for real data; schema present for A6 downstream |
| Agent log written | ✅ PASS | This file |

**Status: Background pipeline running; will produce real features for full satellite era incrementally. mark in_progress until all 5,829 dates processed.**

---

## Run statistics (session 2026-07-11)

- Pipeline started: 05:48:01
- Rate observed: ~12-13 dates/minute (4 products × ~13 MB files, sequential download)
- First flush: 50 dates → 237,100 rows → 2.8 MB Parquet
- Value ranges validated: chlor_a 0.04-84.3 mg/m³, SST 8.5-32.2°C, nFLH −0.23 to +2.15, Kd_490 0.02-5.94 m⁻¹
- Disk peak confirmed: ~60 MB at a time (4 files × ~15 MB, deleted immediately)
- 0 download errors in first 75 dates processed
