# Satellite (MODIS-Aqua Ocean Color L3) — access notes

**Purpose:** satellite features — chlor_a, nFLH, Kd490, SST, Rrs bands (§8-A).

## Access (prefer API)
- NASA OB.DAAC `oceandata` file-search + download API. Requires **Earthdata login**
  (`~/.netrc` with `machine urs.earthdata.nasa.gov login <user> password <pw>`).
- File-search API: https://oceandata.sci.gsfc.nasa.gov/api/file_search
- Use R `httr2`/`download.file()` — **wget is not installed**.

## ⚠️ Stream-and-discard is MANDATORY (PLAN.md §6 A4)
MODIS L3 is served as **global daily files** (no server-side bbox). Do **NOT** bulk-download
the archive (300–500 GB). Per day: download one global file → clip to 24–31°N/87–81°W →
aggregate to 10 km grid → append cell rows → **delete the raw file** (R `unlink()`), then next
day. Make it resumable (checkpoint by date). Peak disk ≈ one file (~15 MB) + growing Parquet.

## Retain for A9 drill-down (selective)
Keep native ~4 km feature rasters retrievable **only for the specific date(s) A9 maps**, or
record the exact re-pull recipe. This does not conflict with stream-and-discard (which governs
the full-archive pass).

## Manual fallback (only if API blocked)
- OB.DAAC browser: https://oceancolor.gsfc.nasa.gov/ → Level-3 browser → MODIS-Aqua →
  daily mapped → download per-day files. Record URL + date in `data/metadata/data_sources.md`.
