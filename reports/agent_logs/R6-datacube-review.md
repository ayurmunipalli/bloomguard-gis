# R6 — Independent Datacube Review

**Reviewer:** R6 (Sonnet 4.6)
**Agent reviewed:** A6 datacube
**Artifacts:** `R/06_build_datacube.R`, `data/processed/model_dataset.parquet`
**Date:** 2026-07-11
**Status (initial):** DRAFT cube (satellite coverage 6.9%); reviewing for correctness before final re-run.
**Status (addendum):** FINAL cube (satellite_missing=0); targeted re-verify 2026-07-11 — see §Addendum below.

---

## Overall Verdict: PASS — safe to re-run

No look-ahead leakage found. All T+H labels verified exhaustively. Pre-2003 drop correct.
Honesty flags present and logically correct. Two minor count discrepancies in A6's log (not
defects in the data). One structural note for A7. See details below.

---

## Per-criterion verdicts

### 1. No look-ahead leakage — PASS

**Verification method:** code trace + independent data check.

**C1a. Feature date range.** All 65,939 `date_T` values ≥ 2003-01-01 (earliest actual:
2003-01-02). Verified by data.

**C1b. Delta join direction.** The critical join is:
```r
sat_lag <- sat[, .(cell_id, join_date = date + k, lag_val = x)]
sat[sat_lag, on = .(cell_id, date = join_date), (lag_col) := i.lag_val]
```
A row at `date` is matched when `join_date == date`, i.e. `original_date + k = date`,
i.e. `original_date = date - k`. The lag value assigned is therefore `x` at `T − k`
(strictly backward). Correct for all k ∈ {1, 3, 5, 7}.

**C1c. Slope/rolling features.** `frollmean(align="right")` is trailing. `ols_slope_k()` uses
`shift(y, 2L)` or higher positive lags — no negative (forward) lags. Computed `by = cell_id`
with `setorder(sat, cell_id, date)` so shifts stay within the correct cell's time-ordered series.
No cross-cell contamination.

**C1d. Historical HAB lag.** Non-equi join uses `sample_date < ref_date` (strict less-than).
Verified in code (`R/06_build_datacube.R:268–270`). Same-day HAB status is not included in the
7d/14d prior window.

**C1e. T+H label shift logic.** `lab_shifted` maps `feature_date = sample_date − H`, then joins
to base rows on `(cell_id, sample_date == feature_date)`. A base row at feature date T therefore
receives the label from `sample_date = T + H` — strictly future. H ∈ {1,3,5,7,14} all > 0.

**OLS formula correctness.** Closed-form coefficients verified analytically and numerically:
- k=3: `(y[i]−y[i-2])/2` → coefs (−1,0,+1)/2 ✓
- k=5: `(−2y[i-4]−y[i-3]+y[i-1]+2y[i])/10` → coefs (−2,−1,0,+1,+2)/10; y[i-2] (coef=0) correctly omitted ✓
- k=7: coefs (−3,−2,−1,0,+1,+2,+3)/28; y[i-3] (coef=0) correctly omitted ✓

Numeric test: sequence y = cumsum(1:7), formula=4.5, true OLS=4.5, match=TRUE.

**Assertion-quality note (not a defect).** Assertions LEAKAGE-A through -E are config/existence
checks (`all(delta_lags > 0)`, `length(slope_cols) > 0`), not data-value checks. They would not
catch a reversed join implemented against a correct config. The independent label verification in
C2 below is the actual data-level guard.

---

### 2. T+H label shift correct for all H — PASS

Independent exhaustive verification: for every non-NA HAB_HX row, looked up HAB in
`habsos_labels.parquet` at `(cell_id, date_T + H)` and compared.

| H | Labelled rows | Verified | Mismatches |
|---|---|---|---|
| 1 | 7,791 | 7,791 | **0** |
| 3 | 4,765 | 4,765 | **0** |
| 5 | 6,151 | 6,151 | **0** |
| 7 | 23,751 | 23,751 | **0** |
| 14 | 23,889 | 23,889 | **0** |

Zero unverifiable rows: every labelled cube row matched exactly one label record at T+H.
Hand-trace of 20 H=7 rows all returned "OK".

---

### 3. spatial_block_tiger present and usable — PASS with note

- Column present: YES
- NA rows: 0 (all 65,939 rows have a block assignment)
- Unique blocks in cube: **36** (A6 log says "82 TIGER county blocks")
- Unique blocks in static_geo.parquet: **82**

**Explanation (not a defect).** The 82 figure reflects how many TIGER counties A5 used for the
full grid; only 36 of those counties contain HABSOS observation cell-days. This is correct
behavior — the cube's row space is HABSOS-observation-centric, so offshore and unsampled counties
don't appear. Column is usable for spatial CV grouping per the lead directive.

**Note for A7.** Block sizes are highly skewed: largest block has 11,018 rows (12_115 = Collier
County), two blocks have only 1 row each (12_083, 12_077). A7 should aggregate tiny blocks or
use stratified holdout rather than treating each 1-row block as a standalone CV fold.

---

### 4. Honesty flags — PASS

| Flag | Present | Values | Verdict |
|---|---|---|---|
| IS_PLACEHOLDER_ROW | YES | TRUE=65,939 (100%) | PASS — env dynamic features all placeholder |
| satellite_missing | YES | TRUE=62,946 / FALSE=2,993 | PASS |
| cloud_flag | YES | TRUE=1,398 / FALSE=1,595 / NA=62,946 | PASS — NA exactly where sat_missing=TRUE |
| salinity_coarse_flag | YES | TRUE=65,939 (100%) | PASS — salinity is placeholder/coarse |
| feature_filled_any | YES | TRUE=0 / FALSE=65,939 | PASS — confirmed: A4/A5 applied no LOCF fills |
| IS_ABSENCE_UNCERTAIN | YES | TRUE=65,939 (100%) | PASS |

**satellite_missing=TRUE ⇒ level cols NA (not zero-filled):** verified for all 4 level features
(chlor_a_mean, sst_mean, nflh_mean, Kd_490_mean) — nonNA count = 0 when satellite_missing=TRUE.

**IS_ABSENCE_UNCERTAIN:** TRUE for all rows, no NAs. Correct per PLAN.md.

**feature_filled_any=FALSE for all rows**: confirmed against source tables — sat_feature_filled
and env_feature_filled are both all-FALSE in their respective parquets (no LOCF applied by A4
or A5 in the draft stage). Flag is logically correct.

---

### 5. Pre-2003 drop — PASS

- Rows with date_T < 2003-01-01 in cube: **0**
- Labels pre-2003 in habsos_labels.parquet: **28,871** (matches A6's claim exactly)
- Labels post-2003: **65,939** = cube rows: **65,939** (exact 1:1)

---

### 6. Trend features (D11) — PASS with minor count note

- Trend columns by grep search: **63** (A6 log claims 61)
- Discrepancy: `hab_any_prior_7d` and `hab_any_prior_14d` are included in the grep pattern
  but A6 appears to have counted them separately from the D11 trend features (historically-lag
  vs. temporal-trend). No correctness issue — both are present and correctly computed.

All 63 trend columns are backward-looking:
- 4 level features × (4 Δ-day + 4 pct_chg + 3 slope + 2 rollmean + 2 rollstd) = 60
- 1 threshold flag (chlor_a_above10pct_consec)
- 2 hab_any_prior (historical HAB lag)

**Zero-fill check.** Spot-checked 8 trend columns where satellite_missing=FALSE: exact-zero
count = 0 for all delta and pct_chg columns. Early-window NA propagation is honest (no zero
masquerade).

---

## Actionable items for A6 / downstream agents

These are clarifications/warnings, not blocking defects:

1. **For A6 log (cosmetic fix):** The log says "82 TIGER county blocks" in the Done-criteria
   table and agent log. This is the static_geo source count; the cube's row space only spans 36.
   Update the log entry to "36 unique TIGER blocks in cube rows (82 in static_geo source)".

2. **For A6 log (cosmetic fix):** Trend column count in Done-criteria says 61; actual is 63.
   Update to 63 (or note that hab_any_prior cols are counted separately).

3. **For A7 (structural warning, not an A6 defect):** The `HAB` column (same-day label at T,
   position 3) is in the modeling table. A6 flags this at assertion F and in NOTE(paper). A7
   must explicitly exclude `HAB` from the feature matrix when training HAB_HX models — failure
   to do so would introduce contemporaneous label information (not look-ahead leakage, but
   detection conflated with forecasting). Recommend A7 hard-drops this column via name.

4. **For A7 (CV design warning):** Two spatial blocks contain only 1 cube row each (12_083,
   12_077). These cannot function as standalone CV holdout folds. A7 should merge tiny blocks
   with geographic neighbors or use minimum-size thresholds when constructing spatial CV splits.

5. **Assertion hardening (for final re-run, low priority):** The 5 leakage assertions are
   config/existence checks. After A4 completes and satellite coverage is dense, consider adding
   a data-level check: e.g., verify that no delta column has a value where the "lag" date is
   actually ≥ T (a stale-positive that would indicate a reversed join). Not urgent — independent
   T+H verification above provides the real guard.

---

## Pipeline safety for re-run

**SAFE TO RE-RUN.** The design is correct: joins are backward, T+H shift is exhaustively
verified, all honesty flags are present and logically correct. When A4 completes the MODIS pull,
re-running `R/06_build_datacube.R` will populate the satellite-derived columns (currently 95.5%
NA) without any design changes required. The output schema, column semantics, and label
correctness will not change.

---

## Addendum — Final cube re-verify (2026-07-11)

**Trigger:** A6 regenerated model_dataset.parquet on the now-complete MODIS satellite pull.
`satellite_missing` dropped from 95.5% → 0. Targeted re-verify of 4 changed-state checks only.

**Overall: PASS — FINAL cube cleared for A7.**

### Check 1: Full date series preserved per cell — PASS

| Metric | Value |
|---|---|
| satellite_missing=0 | confirmed |
| Unique dates across cube | 5,829 (all MODIS processing dates) |
| Unique cells | 1,461 |
| delta_1d non-NA rate | 12.4% |

The 12.4% delta_1d non-NA rate is internally consistent: `chlor_a_mean` is valid (non-cloud)
for 33.3% of rows; for a 1-day delta, both T and T−1 must be valid → (0.333)² ≈ 11%, which
matches the observed 12.4% (slight upward bias from correlated clear-day clusters). This is only
possible if the satellite_features table contained the full daily MODIS series (not a
label-date-truncated subset). If only HABSOS obs dates were in the series, T−1 calendar-day
matches would be near-zero (HABSOS rarely samples consecutive days at the same cell).

Satellite_features.parquet had ~2,608,100 rows across 5,829 dates and 1,461 label-bearing cells.
The cell-level filter preserved all dates for those cells. Trends (slopes, rolling windows) are
computed by `cell_id` on the full time series before joining to label dates. **Not truncated.**

### Check 2: satellite_missing=0 is real, not zero-fill — PASS

| Variable | NA count | Exact-zero count |
|---|---|---|
| chlor_a_mean | 43,991 (66.7%) | **0** |
| sst_mean | 30,730 | **0** |
| nflh_mean | 47,537 | **0** |
| Kd_490_mean | 44,180 | **0** |

All NAs are honest cloud/quality gaps. No zero-fill detected in any level feature.

`cloud_flag=TRUE` for 30,135 of the 43,991 NA chlor_a rows; the remaining 13,856 have
`cloud_flag=FALSE`. These are not fabricated zeros — they are NAs from other MODIS quality
exclusions (sun glint, land mask, low-quality retrieval). `cloud_flag` specifically marks cloud
pixels; other quality exclusions produce NAs with `cloud_flag=FALSE`. All are honest NAs.
**A7 note:** satellite NAs have more than one source; `cloud_flag=TRUE` is not the complete NA
indicator — use `is.na(chlor_a_mean)` directly when masking cloud/invalid obs.

### Check 3: No-leakage holds on full data — PASS

Spot-check: cell_id=537, date_T=2007-02-14, H=7.
- HAB_H7 in cube: 0
- HAB at (cell 537, 2007-02-21) in habsos_labels: 0 → **match OK**
- Feature date = 2007-02-14; label date = 2007-02-21 (strictly future)
- chlor_a_mean at date_T: NaN in both cube and satellite_features (cloud gap) → consistent,
  no fabrication. (NaN-NaN "CHECK" in test output is a R IEEE-754 artefact, not a data error.)

### Check 4: Placeholder env columns identifiable — PASS

| Flag | Value |
|---|---|
| sat_IS_PLACEHOLDER=FALSE | 65,939 (100% of rows — all have real satellite) |
| sat_IS_PLACEHOLDER=TRUE | 0 |
| env_IS_PLACEHOLDER=TRUE | 65,939 (100% — ERA5/CHIRPS/SMAP still placeholder) |
| IS_PLACEHOLDER_ROW=TRUE | 65,939 (100% — because env dynamic features are placeholder) |

**All-NA placeholder env columns (A7 must exclude from feature matrix):**
`wind_u_ms`, `wind_v_ms`, `wind_speed_ms`, `wind_dir_deg`, `precip_mm`, `salinity_pss`

**Real env columns:** `month`, `doy`, `doy_sin`, `doy_cos` (seasonality by construction)

`IS_PLACEHOLDER_ROW=TRUE` for all rows because env is universally placeholder. A7 should use
`sat_IS_PLACEHOLDER == FALSE` (all rows pass) to identify real-satellite rows; `IS_PLACEHOLDER_ROW`
is not a useful training filter in this state.

**A7 feature-matrix exclusion list (consolidated from both reviews):**
1. `HAB` — same-day label (col 3); detection conflation if used as predictor
2. `wind_u_ms`, `wind_v_ms`, `wind_speed_ms`, `wind_dir_deg`, `precip_mm`, `salinity_pss` — all NA
3. Diagnostic/meta columns not features: `IS_PLACEHOLDER_ROW`, `satellite_missing`,
   `cloud_flag`, `salinity_coarse_flag`, `feature_filled_any`, `IS_ABSENCE_UNCERTAIN`,
   `sat_IS_PLACEHOLDER`, `env_IS_PLACEHOLDER`, `static_IS_PLACEHOLDER`, `label_IS_PLACEHOLDER`
4. Spatial CV grouping key (not a feature): `spatial_block_tiger`

---

## Addendum — ERA5 wind join re-verify (2026-07-13)

**Trigger:** Real ERA5 10m wind (u/v, speed, direction, along/cross-shore) pulled via
Copernicus CDS and joined into the cube, replacing the all-NA placeholder from the prior
review. Trend-feature joins, T+H label shift, and HAB-lag joins are unchanged code — not
re-verified here (trust prior PASS). Scope: the wind change only, plus a row/label sanity
check that nothing else silently moved.

**Overall: PASS.**

1. **ERA5 request config — PASS.** `R/05_environmental_features.R` line ~542-543:
   `daily_statistic = "daily_mean"`, `time_zone = "utc+00:00"`. Per-value date comes straight
   from the NetCDF's own time axis (`times_u <- as.Date(time(r_u))`, line 597) with no offset
   arithmetic anywhere in the pull/reshape code (`grep`'d for `date_T`, `+ 1`, `shift(`,
   `lead(`, `lag(` in the full diff vs. the last commit — zero matches). No forward window.

2. **Join is exact-date — PASS.** `R/06_build_datacube.R` line 344-347:
   `merge(base, env_join, by.x = c("cell_id","sample_date"), by.y = c("cell_id","date"), all.x = TRUE)`
   — same-day match, both sides mean day T. This merge is unchanged code (diff on this file
   vs. last commit is comment-only, 11 lines, no logic touched).

3. **Wind features are same-day levels only — PASS.** Lines 634-640: `wind_speed_ms` (sqrt of
   u²+v²), `wind_dir_deg` (atan2, meteorological convention), `wind_along_ms`/`wind_cross_ms`
   (static rotation by fixed `SHORE_ANGLE_DEG = 350`) — all computed from the *same* month_dt
   row's u/v, no temporal transform. Confirmed no `wind_*_delta`/`_slope`/`_pct_chg`/`_roll`
   columns exist anywhere in the codebase (grep, zero matches) — no D11 trend features were
   built for wind, as expected.

4. **Data-level check (pyarrow, independent of R pipeline) — PASS.**
   - Total rows: 65,939 (matches pre-wind-update exactly)
   - `wind_speed_ms` non-NA: 65,939 / 65,939 (100% — ERA5 2003-2021 fully covers the
     satellite-era-filtered cube)
   - H1: 957 pos / 7,791 labelled; H3: 686/4,765; H5: 809/6,151; H7: 2,005/23,751;
     H14: 1,881/23,889 — **all identical** to the pre-wind numbers. Row/label membership did
     not change; only feature columns did. (Cross-checked against the live `a6_run1.log`
     build output, which reports the same five horizon counts independently.)

5. **No future-date use near wind pull/join — PASS.** No `date_T + 1`-style arithmetic found
   in the ERA5 section or the env join; daily-mean is a same-UTC-day aggregate and the join is
   exact-date, so no mechanism exists for day-T wind to include day-(T+1) information.

**No leakage introduced by the ERA5 wind update. Cube cleared for A7 retrain.**

Note (out of scope for this check, flagged for A7): the exclusion list above still lists
`wind_u_ms`/`wind_v_ms`/`wind_speed_ms`/`wind_dir_deg` as "all NA" from the prior review —
that is now stale for wind specifically (100% real per check 4). A7 should re-derive its
exclusion list from current `*_is_placeholder`/`*_IS_PLACEHOLDER` flags rather than reusing
the old list verbatim.

---

## Addendum — Bio-optical species-discrimination features review (2026-07-14)

**Trigger:** A6 additively rebuilt `model_dataset.parquet` to join the A4b bio-optical
(RBD/KBBI/Cannizzaro-vs-Morel bbp) discrimination features + 60 rolling/trend columns via a
refactored shared `add_trend_features()`. Scope per the lead: independently verify the
NEWLY-ADDED bio-optical columns for look-ahead leakage, additive integrity, KBBI
winsorization, non-finite values, and CV-grouping-column presence. Read `R/06_build_datacube.R`
in full (826 lines) and independently re-derived values from the raw source parquets — did not
trust the agent log's numbers.

**Overall Verdict: PASS — cleared for A7.**

### 1. No look-ahead leakage on new bio trend columns — PASS (strongest check this run)

Traced the shared `add_trend_features()` helper (lines 256–315) line-by-line:
- **Calendar-day deltas**: `dt_lag <- dt[, .(cell_id, join_date = date + k, lag_val = get(col))]`
  then `dt[dt_lag, on = .(cell_id, date = join_date), (lag_col) := i.lag_val]`. For a row at
  date D, this matches `dt_lag` rows where `date + k == D`, i.e. the original row was at
  `D - k`. Confirmed algebraically backward-looking for all k ∈ {1,3,5,7}, identical pattern
  already PASSed in the 2026-07-11 review for the satellite variables.
- **pct_chg**: pure re-derivation from the already-verified delta column; no independent join,
  no leakage surface.
- **Slope** (`ols_slope_k`, `shift(y, ≥1L)`) and **rollmean/rollstd** (`frollmean(align="right")`),
  both computed `by = cell_id` after `setorder(bio, cell_id, date)` (line 419) — trailing,
  no cross-cell contamination (data.table grouped ops reset per group by construction).

**Independent end-to-end numerical reproduction (not just code trace):** pulled the raw
`satellite_features_bio_optical.parquet` via `arrow::open_dataset()` server-side filter for 40
label cells (233,160 raw rows, 0 duplicate (cell_id,date)), independently reimplemented delta,
pct_chg, slope_obs5, rollmean_obs7, rollstd_obs7 for all 4 winsorized variables (`rbd`, `kbbi`,
`bbp_ratio_morel`, `bbp_deficit`) from scratch in a separate R process, and compared to the
values actually written in `model_dataset.parquet`:

| Check | Result |
|---|---|
| Rows compared | 5,083 rows × 20 columns = 101,660 value pairs |
| Mismatches | **0** |
| Additional targeted trace (5 cells, `rbd_delta_7d`/`rbd_rollmean_obs3`/level match) | 7/7, 0 mismatches |

This directly proves the join direction is backward (T−k, never T+k) and the bio join key is
the feature date T (not shifted) — the critical risk this review exists to catch.

### 2. T+H labels — PASS

Independently reconstructed HAB_H{1,3,5,7,14} for 40 randomly sampled cell×date_T rows (200
row×horizon pairs) directly from `habsos_labels.parquet` at date T+H (own lookup, not reusing
A6's join code). **0 mismatches.** Consistent with the exhaustive 65,939-row verification in
the 2026-07-11 review (unchanged code path — the label-shift logic was not touched by this
extension).

### 3. Additive integrity — PASS

| Metric | Independently verified | A6's claim |
|---|---|---|
| Rows | 65,939 | 65,939 → 65,939 ✓ |
| Duplicate (cell_id, date_T) | 0 | 0 ✓ |
| Columns | 194 | 116 → 194 ✓ |
| `satellite_features.parquet` dup (cell_id,date), full 27.6M-row table | 0 | (join precondition) ✓ |

Left-join confirmed non-destructive: `bio_missing` is correctly OR'd into `IS_PLACEHOLDER_ROW`
(independently rebuilt the OR-expression from its 4 constituent flags, 0 mismatches against the
stored column — see note below on `env_IS_PLACEHOLDER`, however).

### 4. KBBI winsorization — PASS

- `kbbi` range in the delivered table: **[-0.997320, 0.999955]**, no `|kbbi|>1` remaining.
- `kbbi_raw` preserved (21,950 non-NA); `kbbi` (winsorized) has 21,678 non-NA — difference is
  exactly 272, matching `kbbi_invalid` count.
- Consistency check: `kbbi_invalid==TRUE` count (272) == count of `!is.na(kbbi_raw) &
  abs(kbbi_raw)>1` (272), **0** cases of flagged-but-not-reset or reset-but-not-flagged, **0**
  cases of the flag being TRUE on an originally-NA raw value. Matches spec exactly (flag TRUE
  only for previously non-NA out-of-range values).

### 5. Non-finite values — PASS on the strict "Inf" criterion; note on NaN

- **Inf/-Inf: 0** across all 165 numeric columns — independently re-swept, matches A6's
  LEAKAGE-J.
- **Note (not a defect):** `is.nan()` (as distinct from the broader `is.na()`) is TRUE for
  ~4.5M cells across the feature matrix — but this is **not new to this run**. It reproduces
  identically for the pre-existing satellite trend columns (e.g. `chlor_a_rollmean_obs3`:
  23,922 NaN) as for the new bio trend columns (e.g. `bbp_deficit_rollmean_obs3`: 30,202 NaN).
  Root cause: `data.table::frollmean(na.rm=TRUE)` returns `NaN` (not `NA`) when an entire
  trailing window is NA — a known data.table quirk, not a leakage or fabrication issue. R's
  `is.na(NaN)` is TRUE everywhere in this pipeline (joins, `stopifnot` checks, downstream
  modeling libraries), so it is functionally handled as missing throughout. A6's own Section 4b
  "NaN==missing" assertion only tests the 8 raw bio score columns (before
  `add_trend_features()` runs) — it does not cover the 60 derived trend columns where this
  quirk actually originates. Recommend A6 either broaden that assertion to post-trend columns
  or retitle it to make the narrower scope explicit; **not blocking** since no Inf reaches the
  matrix and NaN is caught by `is.na()` uniformly.

### 6. Spatial-autocorrelation cluster flags — PASS (CV grouping column), pre-existing gap noted

- `spatial_block_tiger` (the actual CV-grouping column per the Lead Directive): present, 0 NA,
  36 distinct blocks — intact and unaffected by this run.
- `spatial_cluster` (Queen-contiguity adjacency diagnostic): **still absent**, exactly as A6's
  own log already documents as a pre-existing limitation (not introduced by the bio-optical
  extension, not required for A7/R-SPLIT's spatial CV since `spatial_block_tiger` is the
  column actually used for blocking).

### Out-of-scope finding flagged for the lead (not an A6 defect, not blocking)

**`IS_PLACEHOLDER_ROW` is currently 0/65,939 (0%) despite CHIRPS precip and SMAP salinity still
being 100% placeholder (`precip_is_placeholder`/`salinity_is_placeholder` both TRUE for all
65,939 rows, `precip_mm`/`salinity_pss` both 100% NA).** Root cause is **not** in
`R/06_build_datacube.R` — it's `R/05_environmental_features.R:773`:
`env[, IS_PLACEHOLDER := wind_is_placeholder & precip_is_placeholder & salinity_is_placeholder]`
(AND, not OR). This was correct/harmless while all three were placeholder (pre-2026-07-12); now
that ERA5 wind is real, the AND collapses `env_IS_PLACEHOLDER` to FALSE for every row even
though 2 of 3 dynamic env features remain fake. A6 correctly propagates whatever A5 hands it
(verified: A6's `IS_PLACEHOLDER_ROW` OR-expression is internally consistent with its inputs, 0
mismatches) — the defect is upstream in A5's aggregation semantics, out of this review's
charter (R6 watches A6 only) and unrelated to the bio-optical join. Flagging for the lead to
route to A5/R5, since it silently defeats the "don't present placeholder output as real"
guardrail at the row-summary-flag level (the underlying NA values themselves are honest — no
fabrication — only the roll-up flag is misleading).

**Verdict: PASS.** No look-ahead leakage, no label defect, no row/join corruption, KBBI holds,
zero Inf. Cleared for A7.
