# HABSOS — data access notes

**Purpose:** ground-truth *Karenia brevis* cell counts → binary HAB labels (D2).

## Files present (post-A3 resolution)

| File | Source | Description |
|------|--------|-------------|
| `event.txt` | DwC-A event core | `eventID`, `eventDate`, `decimalLatitude`, `decimalLongitude`, `locality`, depth |
| `occurrence.txt` | DwC-A occurrence extension | `eventID`, `organismQuantity` (cells/L), `occurrenceStatus` (present/absent) |
| `meta.xml` | DwC-A structure | Column mappings for each file in the archive |
| `eml.xml` | Ecological Metadata Language | Dataset metadata, temporal coverage, contact info |

**Note:** `extendedmeasurementorfact.txt` (80MB, same density values as `occurrence.txt$organismQuantity`)
is NOT copied here — available in the DwC-A zip at the URL below if needed.

## Source

- **HABSOS DwC-A v1.5 (latest as of 2026-07-11)**
  - URL: `https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5`
  - Resource page: `https://ipt-obis.gbif.us/resource?r=habsos`
  - License: CC0 / public domain (NOAA NCEI)
  - Publisher: US Integrated Ocean Observing System (IOOS) via OBIS-USA
  - Accessed: 2026-07-11 (files in zip dated 2022-09-30)
  - Size: ~10 MB zipped, ~135 MB extracted

## Programmatic re-pull (R/curl)

```r
# In R — re-download full DwC-A zip and extract event.txt + occurrence.txt
url  <- "https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5"
dest <- tempfile(fileext = ".zip")
download.file(url, dest, method = "curl", mode = "wb")
unzip(dest, files = c("event.txt", "occurrence.txt", "meta.xml", "eml.xml"),
      exdir = "data/raw/habsos/", overwrite = TRUE)
unlink(dest)  # delete zip after extraction
```

Or via shell (if curl is available):
```bash
curl -L "https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5" -o /tmp/habsos_dwca.zip
unzip /tmp/habsos_dwca.zip event.txt occurrence.txt meta.xml eml.xml -d data/raw/habsos/
rm /tmp/habsos_dwca.zip
```

## DwC-A schema (key fields)

**event.txt** (event core):
- `id` / `eventID` — join key (e.g., `habsos_939786_AL`)
- `eventDate` — ISO-8601 datetime (e.g., `2022-01-11T23:23:00Z`)
- `decimalLatitude` / `decimalLongitude` — WGS84 decimal degrees
- `stateProvince` — AL / FL / MS / TX
- `minimumDepthInMeters` / `maximumDepthInMeters`

**occurrence.txt** (occurrence extension):
- `id` / `eventID` — links to event.txt via `eventID`
- `organismQuantity` — cell count in cells/L (same value as eMoF `measurementValue`)
- `occurrenceStatus` — `present` (>0) or `absent` (0 cells/L)
- `scientificName` — "Karenia brevis"

## What was in the original 12-column occurrence.txt

The `occurrence.txt` present before 2026-07-11 was the occurrence *extension* only,
missing lat/lon/date. It is a subset of the full DwC-A. The DwC-A download above provides
all fields. The occurrence.txt has been updated to the full-archive version in place.

## Coverage

- **Species:** *Karenia brevis* only (all records)
- **States:** AL, FL, MS, TX (+ some FL Atlantic shelf)
- **Date range:** 1953-08-19 to 2021-12-31 (latest version v1.5)
- **Total records:** 190,341 occurrences (43,813 present; 146,528 absent)
- **After study-area filter (24–31°N, 87–81°W):** 169,871 records
- **After grid join (10 km cells, EPSG:5070):** 94,810 cell-day rows

## Label output

Output: `data/processed/habsos_labels.parquet`
- 94,810 cell-day rows | HAB=1: 7,523 (7.93%) | HAB=0: 87,287 (92.07%)
- IS_PLACEHOLDER = FALSE (real grid join from A2)
- IS_ABSENCE_UNCERTAIN = TRUE on all rows (non-detection != absence)

## Limitations

- Non-detection records (`occurrenceStatus=absent`) confirm sampling occurred and K. brevis
  was below detection, but they are NOT evidence of true absence within the full 10 km cell.
- Cell-days with no HABSOS sample are missing from the dataset, not represented as negatives.
- Sampling effort is spatially clustered near coastal monitoring stations.
- The dataset extends back to 1953; satellite features (MODIS-Aqua) begin ~2002.
