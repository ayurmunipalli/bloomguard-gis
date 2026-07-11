# datacube (A6) — decision & methods log

**Agent:** A6 datacube
**Date:** 2026-07-11
**Task:** Build `R/06_build_datacube.R` — model training dataset (cell × date)

---

## Decisions

### Arrow single-thread guard (critical environment fix)
**Decision:** Added `Sys.setenv(ARROW_NUM_THREADS="1")` to `R/00_config.R` (sourced by all scripts) and `arrow::set_cpu_count(1L)` to `R/06_build_datacube.R` immediately after `library(arrow)`.
**Rationale:** `arrow::read_parquet` deadlocks in multi-threaded mode on this machine — observed 7 R processes at 95% CPU for 15h reading parquets. The env var set in 00_config.R ensures all downstream scripts (A7, A8, A9, A11) inherit single-thread mode before arrow initialises its C++ thread pool. `arrow::set_cpu_count(1L)` is belt-and-suspenders insurance applied per-script.
**Date:** 2026-07-11

### Memory guard: filter satellite to label cells before trend computation
**Decision:** Filter `sat_raw` to `cell_id %in% label_cells` before computing trend features. Reduces 27,641,118 → 8,516,169 rows (1461 of 4743 cells).
**Rationale:** Computing 61 trend columns on the full satellite table (27.6M rows × 74 cols × 8 bytes = 16.3 GB) exceeds the 16 GB R memory limit. Filtering to only the 1461 cells present in the label set (cells with at least one HABSOS observation) reduces peak memory to ~5 GB. Each retained cell keeps its full 5829-date time series, so rolling stats are correctly computed over the complete temporal record.
**Date:** 2026-07-11

### Row-space design: feature-centric (T = HABSOS sample date)
**Decision:** The 65,939 base rows are HABSOS observation cell-days at feature date T = `sample_date` (post-2003 filter). Labels for horizon H are found by self-joining habsos_labels at T+H.
**Rationale:** Both satellite_features and environmental_features are keyed on HABSOS observation dates (A4/A5 design). Using T = HABSOS date guarantees full satellite and env feature coverage for every base row (or clear NA+satellite_missing when A4 hasn't yet processed a date). The alternative (label-centric, T = label_date − H) would have required LOCF gap-fill for both satellite and env features on arbitrary calendar dates.
**Alternatives rejected:** Label-centric T = label_date − H was rejected because env_features is only at HABSOS dates, creating systematic NA gaps for most H > 0 rows.
**Date:** 2026-07-11

### Output format: wide (HAB_H1…H14 columns), not long
**Decision:** One row per (cell_id, T) with separate columns for each forecast horizon: `HAB_H1`, `HAB_H3`, `HAB_H5`, `HAB_H7`, `HAB_H14`.
**Rationale:** Avoids 5× row inflation, keeps column lineage clear, lets A7 subset per horizon with a simple `!is.na(HAB_Hk)` filter. The transformer (A11) can reshape to long or use the cube directly.
**Date:** 2026-07-11

### Pre-2003 row exclusion
**Decision:** Drop 28,871 label rows with `sample_date < 2003-01-01`. Explicit filter at line `labels <- labels_raw[sample_date >= SAT_ERA_START]`.
**Rationale:** MODIS-Aqua reliable L3m daily coverage begins 2003-01-01. Joining pre-2003 rows to satellite features would yield 100% NA satellite columns — not useful for modeling. Per habsos-label.md and teammate task instructions.
**Date:** 2026-07-11

### Satellite trend feature computation: observation-order slopes
**Decision:** OLS slope features (`_slope_obsK`) use observation-order indices (1, 2, ..., k), not calendar-day indices, because the satellite series covers only HABSOS sample dates (cloud-gapped).
**Rationale:** The satellite series is irregularly spaced in calendar time (cloud gaps). Using calendar-day x-axis for OLS requires dense data or LOCF interpolation — complex and error-prone in the DRAFT. Observation-order slopes are correct, fast (vectorised shift()), and clearly documented. Unit = "change per satellite observation". Calendar-day deltas (delta_Xd) are computed separately via exact-date join.
**Alternatives rejected:** Calendar-day OLS slope rejected for DRAFT — requires dense satellite data (not yet available). Will be re-evaluated after A4 MODIS pull completes.
**Date:** 2026-07-11

### Calendar-day delta join: exact match only (no LOCF)
**Decision:** Absolute delta features (`_delta_Xd`) use an exact-date join to find x at T-X calendar days. If T-X is not in the satellite series, delta = NA. No LOCF fill for the DRAFT.
**Rationale:** LOCF for calendar-day lookups would propagate stale satellite values potentially days old — hard to validate in the DRAFT. NA is honest. When A4 runs to completion (all HABSOS dates), exact matches will be much more common. PLAN.md §5 says "never let a fill silently masquerade as an observation."
**Date:** 2026-07-11

### Historical HAB lag computation: strict-prior non-equi join
**Decision:** `hab_any_prior_7d` and `hab_any_prior_14d` use a non-equi join with `sample_date < ref_date` (strict less-than), not `<= ref_date`.
**Rationale:** The same-day HAB label is already present as the `HAB` column. The historical indicator must cover only strictly prior dates to avoid self-leakage.
**Date:** 2026-07-11

### IS_PLACEHOLDER_ROW = 100% is expected in DRAFT
**Decision:** IS_PLACEHOLDER_ROW is TRUE for ALL 65,939 rows in this DRAFT.
**Rationale:** The env_IS_PLACEHOLDER column from A5 is TRUE for all rows because the dynamic env features (ERA5 wind, CHIRPS precip, SMAP salinity) are all placeholder. Per the task rule "a row is placeholder if ANY constituent feature is placeholder." This is correct and honest. Use the per-source flags (`sat_IS_PLACEHOLDER`, `env_IS_PLACEHOLDER`, `static_IS_PLACEHOLDER`) to distinguish sources. The seasonality, depth, dist_to_shore, and TIGER block features are real.
**Implications for A7:** A7 should use IS_PLACEHOLDER_ROW only as a diagnostic, not as a hard training filter in the DRAFT. The relevant real features (satellite level + trends, seasonality, geography) are usable when satellite_missing = FALSE.
**Date:** 2026-07-11

### spatial_block_tiger carried from static_geo, NOT re-derived
**Decision:** `spatial_block_tiger` (82 TIGER county blocks) is taken directly from `static_geo.parquet` (A5 output). A6 does not re-derive it.
**Rationale:** A5 implemented the Lead Directive (reports/decisions.md 2026-07-11) correctly: geographic blocking via TIGER counties, with `st_nearest_feature` fallback for ocean cells. Re-deriving in A6 would risk inconsistency. The Queen-contiguity `spatial_cluster` column is NOT present in model_dataset (not in any source table joined here) — if needed, it can be added from the grid .gpkg.
**Date:** 2026-07-11

---

## Data sources used

| Dataset | Access | Version/Date | Used for |
|---|---|---|---|
| `habsos_labels.parquet` (A3) | local file | 2026-07-11 | Base rows (label_date T), T+H labels |
| `satellite_features.parquet` (A4) | local file | 2026-07-11 DRAFT | Level features + trend base |
| `environmental_features.parquet` (A5) | local file | 2026-07-11 | Env features (wind/precip/sal placeholder; seasonality real) |
| `static_geo.parquet` (A5) | local file | 2026-07-11 | Cell-level geography + spatial_block_tiger |

---

## Methods & techniques

- **T+H label shift** — self-join on habsos_labels: for each row at T, the forecast label at T+H is obtained by joining to a date-shifted copy of the label table (shift = H). Implementation: create `lab_shifted[feature_date = sample_date - H, HAB]`, join on `cell_id + feature_date = sample_date`. Applied in `R/06_build_datacube.R` Step 7. — PLAN.md D5/§2.2.

- **Vectorised OLS slope** — Closed-form coefficients for OLS with x = 1:k (observation order): k=3 → (y[i] − y[i−2])/2, k=5 → (−2y[i−4] − y[i−3] + y[i−1] + 2y[i])/10, k=7 → (−3y[i−6] − 2y[i−5] − y[i−4] + y[i−2] + 2y[i−1] + 3y[i])/28. Implemented via `shift()` in data.table, computed by cell group. No loops over rows. — `ols_slope_k()`, `R/06_build_datacube.R`.

- **Calendar-day delta join** — For each level feature x, create a shifted reference table `sat_lag[join_date = date + k, lag_val = x]`, then exact-join to `sat` on `(cell_id, date = join_date)`. This retrieves x at T-k without any future-date access. — PLAN.md §8-B.

- **frollmean / rolling std** — `data.table::frollmean(align="right", na.rm=TRUE)` for trailing rolling means over k=3 and k=7 observation windows. Rolling std via Var(X) = E[X²] − E[X]². — PLAN.md §8-B.

- **10% DoD threshold flag** — `chlor_a_above10pct_consec`: integer (0/1), 1 when chl-a rose >10% in the day-over-day calendar-lag AND the previous observation also rose >10%. Uses observation-order shift for the "consecutive" test. — PLAN.md D11.

- **Historical HAB non-equi join** — `hab_any_prior_7d` / `_14d`: for each (cell_id, T), any HAB=1 in [T-lag, T)? Non-equi join on `sample_date ∈ [win_start, ref_date)` with pre-computed `win_start = sample_date - lag_days`. — PLAN.md §8-C.

- **No-look-ahead assertion** — Five explicit `stopifnot()` assertions (LEAKAGE A–E) verify: (A) all feature dates ≥ 2003-01-01, (B) delta lags > 0, (C) slope/roll columns are trailing, (D) all horizons > 0, (E) hab-lag joins use strict-prior dates. All PASSED. — PLAN.md §2.2.

---

## Output summary (FINAL)

| Metric | Value |
|--------|-------|
| File | `data/processed/model_dataset.parquet` |
| Status | **FINAL** — full MODIS coverage, 2003-2021 |
| Rows | 65,939 |
| Columns | 114 |
| File size | 12.78 MB |
| Satellite coverage | **100%** (5829/5829 unique dates) |
| satellite_missing | **0** rows (was 62,946 in DRAFT) |
| cloud_flag=TRUE | 30,135 rows (45.7%) — real Gulf cloud cover |
| chlor_a NA (cloud/missing) | 43,991 rows (66.7%) |
| sat_IS_PLACEHOLDER | 0 (all satellite data is real) |
| IS_PLACEHOLDER_ROW | 65,939 (100% — env dynamic features ERA5/CHIRPS/SMAP still placeholder per A5) |
| No-leakage assertions | ALL PASSED (5/5) |
| unique cells | 1,461 |
| spatial_block_tiger blocks (label cells) | 36 of 82 county blocks |

**Label availability per horizon:**

| H | Labelled rows | Positive (HAB=1) | % Positive |
|---|---|---|---|
| 1 | 7,791 | 957 | 12.3% |
| 3 | 4,765 | 686 | 14.4% |
| 5 | 6,151 | 809 | 13.2% |
| 7 | 23,751 | 2,005 | 8.4% |
| 14 | 23,889 | 1,881 | 7.9% |

---

## Open questions / caveats / limitations

- **NOTE(limitation):** Satellite level features have 66.7% NA (chlor_a) due to Gulf cloud cover (45.7% of cell-days cloud_flag=TRUE). This is expected for MODIS over the Gulf — cloud gaps are real atmospheric conditions. satellite_missing=0: all 5,829 HABSOS dates were processed by A4.

- **NOTE(limitation):** Observation-order slopes (slope_obsK) measure change per satellite observation, not per calendar day. For the dense full dataset (post-A4), consider recomputing with calendar-day x-axis for proper temporal slope estimation.

- **NOTE(limitation):** Calendar-day delta features (delta_Xd) require the exact date T-X to be in satellite_features.parquet. With the current sparse MODIS pull, most deltas are NA. They will populate incrementally as A4 processes more dates.

- **NOTE(limitation):** IS_PLACEHOLDER_ROW = TRUE for all rows because env dynamic features (ERA5 wind, CHIRPS precip, SMAP salinity) are all placeholder (A5 blocker). Use per-source flags for finer-grained placeholder detection.

- **NOTE(paper):** The same-day HAB label (`HAB` column) is retained in model_dataset for diagnostics only. A7 must NOT use it as a feature when training the H-day forecast model, as this would introduce contemporaneous "detection" information. Run ablations with/without.

- **NOTE(paper):** Label sparsity at short horizons (H=1: 7,791 labelled rows; H=3: 4,765) reflects the frequency of consecutive-day HABSOS observations at the same cell, which is low. The model will primarily be trained on H=7 and H=14 pairs (23,000+ labelled rows) where HABSOS re-sampling is more common.

- **NOTE(limitation):** spatial_cluster (Queen-contiguity) column was NOT included in model_dataset because it is not in any of the joined source tables (the grid .gpkg has it but was not joined). If needed, A7 can join it from `data/processed/study_area_grid.gpkg` via cell_id. The critical CV column `spatial_block_tiger` IS present.

---

## Done-criteria (PLAN.md §6 A6) — pass/fail

| Criterion | Status | Note |
|---|---|---|
| Script runs end-to-end | ✅ PASS | No errors |
| Labels + satellite + env + static joined | ✅ PASS | Left-join on (cell_id, date) |
| T+H label shift for all 5 horizons | ✅ PASS | HAB_H1/H3/H5/H7/H14 present |
| No look-ahead leakage (5 assertions) | ✅ PASS | All PASSED |
| Trend features computed (D11/§8-B) | ✅ PASS | 61 trend columns |
| spatial_block_tiger carried through | ✅ PASS | 82 TIGER county blocks |
| IS_ABSENCE_UNCERTAIN carried | ✅ PASS | |
| cloud_flag, salinity_coarse_flag carried | ✅ PASS | |
| satellite_missing flag for NA satellite | ✅ PASS | 0 missing (FINAL — full MODIS) |
| IS_PLACEHOLDER_ROW computed | ✅ PASS | 100% (env dynamic features placeholder per A5) |
| Pre-2003 rows dropped (explicit filter) | ✅ PASS | 28,871 dropped |
| FINAL status (DRAFT → FINAL) | ✅ PASS | Log + script updated 2026-07-11 |
| Header + NOTE tags present | ✅ PASS | |
| Agent log written | ✅ PASS | This file |
| Script re-runnable (idempotent) | ✅ PASS | Overwrites output on re-run |
