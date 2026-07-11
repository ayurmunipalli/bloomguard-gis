# habsos-label (A3) — decision & methods log

## Decisions

- **DwC-A schema gap resolved (2026-07-11)** — The `occurrence.txt` in `data/raw/habsos/`
  was only the *occurrence extension* of a Darwin Core Sampling Event Archive, missing the
  *event core* (`event.txt`) which carries `decimalLatitude`, `decimalLongitude`, and
  `eventDate`. Found the full DwC-A (v1.5, 190,341 rows) at
  `https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5`. Downloaded and extracted to
  `data/raw/habsos/` (event.txt + meta.xml + eml.xml). The `eventID` field in
  `occurrence.txt` is identical to the `id` field in `event.txt`, enabling a clean 1:1 join.
  Alternative considered: re-export from HABSOS portal with geo fields — rejected in favour
  of the IPT DwC-A because the IPT download is programmatically reproducible.

- **Cell count source: `occurrence.txt` `organismQuantity` used directly (2026-07-11)** —
  The DwC-A also ships an `extendedmeasurementorfact.txt` with a "density" measurement type
  (`measurementValue`, cells/L). Spot-checked: values are identical to `organismQuantity`.
  Used `occurrence.txt` to avoid the extra file read. If any discrepancy surfaces, the eMoF
  file is retained in tmp and can be re-applied.

- **Aggregation: max per (cell, date) (2026-07-11)** — Multiple HABSOS samples can be taken
  within the same 10 km cell on the same day (e.g., different stations within a cell).
  Following PLAN.md A3 spec: take `max(organism_quantity)` per cell-day. Alternatives:
  mean or sum were considered and rejected — the bloom threshold is defined as a threshold
  exceedance at any point; max is the most conservative and biologically defensible.

- **IS_ABSENCE_UNCERTAIN = TRUE on all rows (2026-07-11)** — Both sampled-absent rows and
  sampled-present rows get this flag because the absence flag refers to the *cell-day* unit
  of analysis, not the individual sample. Even in a cell-day where a sample returns 0, other
  parts of the 10 km cell may be unsampled. Downstream agents must NOT treat HAB=0 as a
  confirmed clean cell.

- **Date range retained back to 1953 (2026-07-11)** — HABSOS contains historical records
  back to 1953. These are kept in the parquet; A4/A6 will filter to the satellite era
  (MODIS-Aqua: 2002-present) when building the datacube. Removing pre-MODIS records now
  would discard data that could be useful for environmental feature joins if a longer
  environmental record is used.

- **No eMoF `measurementRemarks` filtering (2026-07-11)** — A handful of eMoF rows have
  non-empty `measurementRemarks`. Inspected; all were blank or contained QC notes that
  don't indicate record invalidity. Kept all records.

## Data sources used

- **HABSOS v1.5 DwC-A** — `https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5` — downloaded
  2026-07-11 — open/public (NOAA NCEI) — event.txt + occurrence.txt + eMoF + meta.xml
  extracted to `data/raw/habsos/`. 190,341 occurrence records. Files dated 2022-09-30 in zip.
  License: CC0 (per EML: HABSOS is a NOAA/NCEI public dataset).

## Methods & techniques

- **Darwin Core Archive join** — event.txt (event core) joined to occurrence.txt (occurrence
  extension) on `event.txt$id = occurrence.txt$eventID` using `data.table::merge()` (inner
  join). Yields ~190,339 records (2 event rows with parse-corrupt lat/lon from multi-line
  locality field were dropped pre-merge via `!is.na(lat)` filter).
  Applied in: `R/03_habsos_labels.R`, step 1.

- **Bounding-box pre-filter** — Study area 24–31°N, 87–81°W (D1 / Hu et al. 2022) applied
  before reprojection for efficiency. Reduces 190,339 to 169,871 records.
  Applied in: `R/03_habsos_labels.R`, step 2.

- **CRS: WGS84 → Albers (EPSG:4326 → EPSG:5070)** — Points reprojected using `sf::st_transform()`
  before spatial join. Grid is in EPSG:5070 (Albers Equal Area). Consistent with A2's grid
  method and PLAN.md D1. Applied in: `R/03_habsos_labels.R`, step 3.

- **Spatial join: `st_within`** — `sf::st_join(..., join = st_within, left = FALSE)` assigns
  each point to its containing cell. `left = FALSE` drops points that fall outside the grid
  (ocean regions, edge clipping). Applied in: `R/03_habsos_labels.R`, step 3.

- **Daily aggregation** — `data.table` groupby `(cell_id, sample_date)` → `max(organism_quantity)`,
  `count(n_samples)`. Applied in: `R/03_habsos_labels.R`, step 4.

- **Binary label: D2** — `HAB = as.integer(max_count > 100000)`. 100,000 cells/L threshold per
  PLAN.md §2 D2. Applied in: `R/03_habsos_labels.R`, step 4.

- **Output: Apache Parquet** — `arrow::write_parquet()`. Schema: cell_id (int32), sample_date
  (date32), max_count (double), n_samples (int32), HAB (int32), IS_PLACEHOLDER (bool),
  IS_ABSENCE_UNCERTAIN (bool). Applied in: `R/03_habsos_labels.R`, step 5.

## Labels summary (IS_PLACEHOLDER = FALSE — real grid join)

| Metric | Value |
|--------|-------|
| Total cell-day rows | 94,810 |
| HAB = 1 (positive) | 7,523 (7.93%) |
| HAB = 0 (negative) | 87,287 (92.07%) |
| Threshold | > 100,000 cells/L (D2) |
| Date range | 1953-08-19 to 2021-12-31 |
| IS_PLACEHOLDER | FALSE |
| IS_ABSENCE_UNCERTAIN | TRUE (all rows) |
| max_count range | 0 to 3.58×10⁸ cells/L |

## Open questions / caveats / limitations

- **NOTE(limitation): HABSOS non-detection != proven absence.** An `occurrenceStatus=absent`
  or `organism_quantity=0` record means a sample was taken and K. brevis was below detection.
  A cell-day with *no* HABSOS sample at all is simply absent from the dataset — it is NOT
  represented as HAB=0. Downstream modeling (A7) must treat negatives as soft negatives.

- **NOTE(limitation): Label balance (7.93% positive) reflects sampling effort, not true bloom
  frequency.** HABSOS samples are spatially clustered near coastal monitoring stations and
  temporally biased toward known bloom years. Class imbalance should be handled in modeling
  (PLAN.md §9: prioritize recall + PR-AUC; consider class weights, not naive oversampling).

- **NOTE(limitation): Data extends back to 1953 but satellite features (MODIS) only start
  2002. The pre-2002 cell-days will be dropped during datacube join (A6) — kept in parquet
  for completeness, not for modeling.**

- **NOTE(paper): Join key.** The DwC-A event-occurrence join (eventID = event.id) is a
  standard DwC Sampling Event Archive pattern. This is documented to allow the method to be
  reproduced from the public HABSOS IPT resource.

- **Reviewer R3 note:** Confirm that `max_count` of 3.58×10⁸ cells/L is real (not a parse
  artifact) before modeling. This is ~3,580 × the bloom threshold and could represent a dense
  bloom aggregate or a data entry error. Should be flagged to A7 for outlier sensitivity check.
