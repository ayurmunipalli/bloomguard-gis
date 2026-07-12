# R-SPLIT — Transformer (A11) Split-Integrity Review

**Reviewer:** R-SPLIT (Sonnet 4.6)
**Scope:** A11 train/test split construction ONLY (not model architecture, hyperparameters, or metrics)
**Artifacts reviewed:**
- `python/dl_dataset.py` (split construction + sequence building)
- `python/modeling_transformer.py` (main training loop)
- `R/07_modeling.R` (A7 reference split logic)
- `data/processed/model_dataset.parquet` (65,939 × 114)
- `reports/agent_logs/R-SPLIT-review.md` (A7 CONDITIONAL PASS review)
- `reports/agent_logs/transformer.md` (A11 decision log)
- `outputs/tables/model_results.csv` (RF + transformer rows, all 60 rows)
**Date:** 2026-07-12
**Verification method:** Empirical — Python/pyarrow, same dataset, independent reconstruction

---

## Overall Verdict: **CONDITIONAL PASS — A11 may be committed with the caveat below**

No disqualifying leakage found. One structural caveat (random-split RNG non-identity) requires
documentation; it does not require a re-run because the two honest splits (temporal, spatial)
are row-for-row identical to A7 and the random split is the known-optimistic metric.

| Check | Verdict | Severity |
|---|---|---|
| 1. Spatial adjacency / same block holdout | **PASS** | — |
| 2. Temporal split boundary | **PASS** | — |
| 3. Label bleed (T+H across boundary) | **NEAR-PASS** | Low — identical to A7's caveat |
| 4. Fairness: row membership identical to A7 — temporal split | **PASS** | — |
| 4. Fairness: row membership identical to A7 — spatial split | **PASS** | — |
| 4. Fairness: row membership identical to A7 — random split | **CAVEAT** | Low — self-admitted; random is optimistic split |
| 5. Sequence look-ahead (seq_len=14 lookback) | **PASS** | — |

---

## Check 1: Spatial Adjacency / Same Block Holdout — PASS

### Reconstruction

`dl_dataset.py:merge_tiny_blocks()` is a Python port of R `07_modeling.R:merge_tiny_blocks()`.
Both merge blocks with < `MIN_BLOCK_ROWS=5` rows into the largest block. Both then run a
greedy largest-first accumulation until cumulative test fraction ≥ 15%.

Computed from parquet directly:

| H | Holdout block (A11 Python) | test_rows | test% | Holdout block (A7 R) |
|---|---|---|---|---|
| 1 | `12_115` | 3,279 | 42.1% | `12_115` ✅ |
| 3 | `12_115` | 2,228 | 46.8% | `12_115` ✅ |
| 5 | `12_115` | 2,399 | 39.0% | `12_115` ✅ |
| 7 | `12_115` | 6,576 | 27.7% | `12_115` ✅ |
| 14 | `12_115` | 6,388 | 26.7% | `12_115` ✅ |

### Tie-breaking investigation

Ties in block sizes exist at every horizon (e.g., H=7: two blocks tied at count=10).
However, block `12_115` (Sarasota County) is the single largest block at all horizons by a
factor of ≥1.5×, and it already satisfies the ≥15% threshold alone. Therefore `n_holdout=1`
at every horizon, and the tied smaller blocks are never reached in the greedy selection.
The ties are irrelevant to the holdout outcome.

**Verdict:** Spatial split logic is effectively identical to A7. Same holdout block, same
test/train row sets. The structural adjacency caveats from the A7 CONDITIONAL PASS (13/89
border test cells within ~10 km of a train cell; prevalence confound from Sarasota County)
apply equally here. They are documented structural limitations, not code defects, and require
no new action.

---

## Check 2: Temporal Split Boundary — PASS

### Boundary definition (both A7 and A11)

- Train: `year < 2016` → `date_T ≤ 2015-12-31`
- Test: `year >= 2016` → `date_T ≥ 2016-01-01`

A7 (R): `which(h_dt$year < TEMPORAL_CUTOFF_YEAR)` with `TEMPORAL_CUTOFF_YEAR <- 2016L`
A11 (Python): `np.where(year < TEMPORAL_CUTOFF_YEAR)[0]` with `TEMPORAL_CUTOFF_YEAR = 2016`

Confirmed max training anchor date: `2015-12-31`. Confirmed min test date: `2016-01-01`.
No overlap, no fuzzy boundary.

### Count verification (A7 vs A11, temporal split)

All counts verified by independent Python reconstruction from parquet match A7 exactly:

| H | A7 train | A11 train | A7 test | A11 test |
|---|---|---|---|---|
| 1 | 4,787 | 4,787 ✅ | 3,004 | 3,004 ✅ |
| 3 | 2,813 | 2,813 ✅ | 1,952 | 1,952 ✅ |
| 5 | 3,474 | 3,474 ✅ | 2,677 | 2,677 ✅ |
| 7 | 14,871 | 14,871 ✅ | 8,880 | 8,880 ✅ |
| 14 | 14,868 | 14,868 ✅ | 9,021 | 9,021 ✅ |

**Verdict:** Temporal split is IDENTICAL to A7 — deterministic year-based criterion, same cutoff.

---

## Check 3: Label Bleed (T+H Window) — NEAR-PASS

A11 does not implement an embargo gap, same as A7. A training row at date_T with label T+H
can have its label date fall in the test period.

Independently verified bleed counts (identical to A7's R-SPLIT-review.md numbers):

| H | Train rows | Bleed rows | Bleed% |
|---|---|---|---|
| 1 | 4,787 | 1 | 0.02% |
| 3 | 2,813 | 3 | 0.11% |
| 5 | 3,474 | 12 | 0.35% |
| 7 | 14,871 | 23 | 0.15% |
| 14 | 14,868 | 49 | 0.33% |

Worst case H=14: 49 rows (0.33%) have label dates in Jan 2016. A11 inherits exactly A7's
bleed — neither more nor less. The A7 CONDITIONAL PASS NOTE(limitation) on this carries over
unchanged: negligible practical impact; a strict implementation would drop the H days preceding
the cutoff from training.

**Verdict:** Same as A7. No new action required beyond A7's existing documentation.

---

## Check 4: Fairness — Row Membership vs A7 — MIXED

### 4a. Temporal split (PRIMARY honest metric) — PASS

Both A7 and A11 apply the same deterministic criterion to the same rows. Row membership is
provably identical: every row with `year < 2016` is in train for both; every row with
`year >= 2016` is in test for both. Verified by exact count match at all horizons.

**The head-to-head RF vs transformer comparison on the temporal split is FAIR.**

### 4b. Spatial split — PASS

Both hold out the identical block (`12_115`) at all horizons. Row membership is provably
identical: spatial block membership is a fixed column in the parquet, and both implementations
apply the same greedy threshold logic producing the same holdout set. Verified by exact count
match at all horizons.

**The head-to-head RF vs transformer comparison on the spatial split is FAIR.**

### 4c. Random split — CAVEAT (not FAIL)

A11 uses a numpy RNG (`np.random.default_rng(SEED + H)`) while A7 uses R's `set.seed(SEED + H)`.
The two RNGs produce different shuffle sequences. The counts match exactly (e.g., H=7:
RF n_test=4,751; transformer n_test=4,751) because both apply the same 80/20 stratified
proportions — but the specific rows in train vs test differ between RF and transformer.

A11 self-admits this in its decision log:
> "random split uses numpy RNG (seed=SEED+H) rather than R's RNG; assignment is statistically
> equivalent but not row-for-row identical."

**Why this is not a FAIL:**
- The random split is explicitly noted throughout the project as the "optimistic" evaluation
  (spatial autocorrelation lets nearby cell-days appear in both train and test regardless of
  which specific rows are selected).
- The temporal and spatial splits — the honest metrics the paper headlines — are IDENTICAL.
- The statistical properties of the random split are preserved: same stratification (positive/
  negative), same 80/20 proportions, same seed offset philosophy.
- No result depends on the random split being the same specific rows; it is always
  subordinated to temporal and spatial in the honest reporting.

**Required action for A11 (documentation, not re-run):**
> NOTE(limitation): The random-split head-to-head comparison uses statistically equivalent
> but non-identical train/test rows vs the Stage-1 RF (numpy RNG differs from R's RNG at
> the same seed). The random split is the optimistic metric and is not the paper's honest
> number. Temporal and spatial split comparisons are row-for-row identical and are the
> valid fairness comparison.

---

## Check 5: Sequence Look-ahead (SEQ_LEN=14 Lookback) — PASS

### Logic review (`dl_dataset.py:build_all_sequences()`)

For each anchor row with `date_T = T`:
```python
valid_mask = cell_dates <= date_T_np
valid_pos  = cell_pos[valid_mask]
```
Only rows with `date_T <= T` are included in the lookback. A runtime assertion confirms this:
```python
assert (cell_dates[valid_mask] <= date_T_np).all(), ...
```

### Temporal split sequence integrity

Training anchors have `date_T < 2016-01-01`. Their sequences pull from `full_df` (65,939 rows)
filtered to the same cell AND `date_T <= anchor_date_T`. Since `anchor_date_T < 2016`, no
row from the test period (2016+) can enter any training sequence.

### Spatial split sequence integrity

Training anchors have `cell_id` from non-holdout blocks. The `cell_index` in `build_cell_index`
groups rows by `cell_id`. A training cell's rows in `full_df` are all from that cell — which
is in the training block. No rows from holdout cells can appear in a training-cell sequence.

### Cross-contamination via `full_df`

`build_all_sequences()` takes the full 65,939-row dataset as `full_df` (for maximum lookback
history), but uses `cell_index` which is keyed by `cell_id` — so each anchor only looks up
rows from its own cell. There is no mechanism by which a test cell's rows appear in a training
cell's sequence.

**Verdict:** No look-ahead leakage in sequence construction. The assertion is a valid in-code guard.

---

## Gate Decision

**A11 may be committed.** No disqualifying leakage found. Required action before commit:

1. **A11 must add NOTE(limitation)** (not a code change) to `reports/agent_logs/transformer.md`:
   - Random split row membership is statistically equivalent but not row-for-row identical to A7
     due to numpy vs R RNG. Temporal and spatial splits ARE identical. Random split result must
     not be used to claim head-to-head advantage or disadvantage over RF — only temporal and
     spatial comparisons are row-for-row fair.
2. **For the paper:** present temporal and spatial split head-to-head as the fair comparison.
   Random split head-to-head is indicative only (different rows, same statistical design).

No re-run of A11 training is required. The honest splits (temporal, spatial) are
structurally sound and row-for-row identical to A7.

---

## Comparison Summary: A7 vs A11 Split Integrity

| Property | A7 RF | A11 Transformer | Match? |
|---|---|---|---|
| Temporal cutoff | `year < 2016` | `year < 2016` | ✅ |
| Temporal train/test rows (all H) | Verified above | Identical | ✅ |
| Spatial holdout block (all H) | `12_115` | `12_115` | ✅ |
| Spatial train/test rows (all H) | Verified above | Identical | ✅ |
| Random split proportions | Stratified 80/20 | Stratified 80/20 | ✅ |
| Random split specific rows | R RNG (seed+H) | Numpy RNG (seed+H) | ⚠️ Non-identical |
| Label bleed (H=14) | 49 rows (0.33%) | 49 rows (0.33%) | ✅ |
| Feature exclusions | ALWAYS_EXCLUDE | Identical list | ✅ |
| log1p transforms | 3 features | Same 3 features | ✅ |
| Imputation source | Train medians | Train medians | ✅ |
| Class weights | n_neg/n_pos | n_neg/n_pos | ✅ |
