# Weather / Environmental — Manual Download Instructions

Generated: 

## Why this file exists
Some environmental data sources require auth or were rate-limited during automated pull.
Follow these steps to populate real data for placeholders in `environmental_features.parquet`.

---

## ERA5 10m Wind (u/v components) — Copernicus CDS API

**Status:** REAL — pulled via Copernicus CDS `derived-era5-single-levels-daily-statistics`
(bilinear-extracted to 1616 cells x 10451 dates; see reports/agent_logs/env-features.md)
**Cite:** Hersbach et al. (2020) doi:10.1002/qj.3803
**Coverage:** 1979-01-01 to present, ~0.25° (~28 km), daily-mean via CDS server-side aggregation

### Steps to pull (already implemented in R/05_environmental_features.R Section E):
1. Register at https://cds.climate.copernicus.eu/ (free account)
2. Accept the licence for BOTH datasets used (each CDS catalog entry has its own licence gate):
   - https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels?tab=download#manage-licences
   - https://cds.climate.copernicus.eu/datasets/derived-era5-single-levels-daily-statistics?tab=download#manage-licences
3. Copy your Personal Access Token to `~/.cdsapirc`:
   ```
   url: https://cds.climate.copernicus.eu/api
   key: <your-PAT>
   ```
4. R package `ecmwfr` handles auth + the async job/poll/download flow (installed via renv).
5. Re-run R/05_environmental_features.R; Section E pulls per-year daily-mean u10/v10,
   bilinearly extracts to cell centroids, and derives speed/direction/along-cross-shore.

### Note on along-shore / cross-shore components:
West Florida Shelf shoreline orientation ≈ 350° (NNW). Along-shore wind ≈ component parallel
to coast; cross-shore ≈ perpendicular. Derived as:
  along  = u * cos(shore_angle) + v * sin(shore_angle)
  cross  = -u * sin(shore_angle) + v * cos(shore_angle)

---

## CHIRPS v2.0 Daily Precipitation — UCSB CHC

**Status:** PLACEHOLDER (HTTP 403 CrowdSec ban re-triggered by the automated pull loop —
confirmed via response body containing 'CrowdSec Ban'; a single lightweight HEAD-request
liveness check can return 200 while the sustained GET loop still gets banned within seconds.
Per lead directive this is logged and NOT retried further this run.)
**Cite:** Funk et al. (2015) doi:10.1038/sdata.2015.66
**Coverage:** 1981-01-01 to 2021-12-31 (for HABSOS overlap), ~0.05° (~5 km), daily

### Steps to pull (no auth required, but respect rate limits):
1. Base URL: https://data.chc.ucsb.edu/products/CHIRPS-2.0/global_daily/tifs/p05/
2. Each file: chirps-v2.0.{YYYY}.{MM}.{DD}.tif.gz (~1.5 MB each)
3. Processing approach (stream-and-discard via terra vsicurl — no permanent storage needed):
   a. In R with terra: url <- '/vsigzip//vsicurl/https://data.chc.ucsb.edu/...'
   b. r <- rast(url); r_crop <- crop(r, ext(-87,-81,24,31))
   c. vals <- extract(r_crop, grid_vect, fun=mean, na.rm=TRUE)
   d. Append to checkpoint parquet; no raw tif saved to disk.
4. Wait well over 24h after a CrowdSec ban before retrying, ideally from a different egress IP —
   a lightweight HEAD-request liveness check passing does NOT mean the ban has lifted for GETs.
5. Re-run R/05_environmental_features.R — it resumes from the checkpoint
   (checkpoint only records genuinely-successful rows, so failed dates are retried automatically).

---

## SMAP Sea-Surface Salinity — RSS/PODAAC

**Status:** PLACEHOLDER (complex OPeNDAP auth; deferred)
**Cite:** Meissner et al. (2018) doi:10.3390/rs10071121
**Coverage:** 2015-04-01 to present, ~0.25° (40–70 km sensor footprint), 8-day running mean
**IMPORTANT:** salinity_coarse_flag=TRUE on ALL values — broad-context feature only.

### Steps to pull (Earthdata auth required):
1. Ensure ~/.netrc has Earthdata credentials (already present on this machine).
2. Search PODAAC CMR: https://cmr.earthdata.nasa.gov/search/granules?short_name=SMAP_RSS_L3_SSS_SMI_8DAY_RUNNINGMEAN_V5
3. Download L3 8-day running mean files for Gulf region (no server-side bbox — global NetCDF,
   but small: ~5 MB each). Extract salinity variable for Gulf bbox.
4. Zonal extract per 10 km cell; flag all rows salinity_coarse_flag=TRUE.
5. Re-run R/05_environmental_features.R with SMAP files in data/raw/weather/smap/.
