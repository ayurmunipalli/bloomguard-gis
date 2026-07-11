# R-SPLIT — Independent Split-Integrity Review

**Reviewer:** R-SPLIT (Sonnet 4.6)
**Scope:** A7 train/test split construction only (not model code, hyperparameters, or metrics)
**Artifacts reviewed:** `R/07_modeling.R`, `data/processed/model_dataset.parquet` (65,939 × 114),
`data/processed/static_geo.parquet`, `outputs/tables/model_results.csv`,
`reports/agent_logs/modeling.md`, `reports/agent_logs/R6-datacube-review.md`, `reports/decisions.md`
**Date:** 2026-07-11

---

## Overall Verdict: **CONDITIONAL PASS — M1 may be committed with the caveats below**

No disqualifying leak found. Two structural issues are documented defects that A7 must
annotate/caveat in the decision log and in the paper material; neither requires a re-run.

| Check | Verdict | Severity |
|---|---|---|
| 1. Spatial adjacency leakage | **CAVEAT** | Medium — not a code error; structural limitation to document |
| 2. Temporal embargo | **NEAR-PASS** | Low — tiny bleed (≤0.3% of train), negligible practical impact |
| 3. Feature-matrix exclusions | **PASS** | — |
| 4. Tiny-block merge | **PASS** | — |

---

## Check 1: Spatial Adjacency Leakage — CAVEAT (not FAIL)

### What was reconstructed

A7's spatial split holds out **block 12_115 (Collier County)** as the sole test fold for every
horizon H ∈ {1,3,5,7,14}. This is correct behavior: `merge_tiny_blocks()` merges the two
singleton blocks (12_083, 12_077, 1 row each) into the largest block (12_115), which then always
satisfies the ≥15% greedy threshold alone:

| H | test_rows | n_total | test% | holdout_blocks |
|---|---|---|---|---|
| 1 | 3,279 | 7,791 | 42.1% | [12_115] |
| 3 | 2,228 | 4,765 | 46.8% | [12_115] |
| 5 | 2,399 | 6,151 | 39.0% | [12_115] |
| 7 | 6,576 | 23,751 | 27.7% | [12_115] |
| 14 | 6,388 | 23,889 | 26.7% | [12_115] |

The block is a single geographically **contiguous** region (one Florida county). This is correct
structure; the test region is not fragmented or interleaved with training.

### Adjacency quantification

Computed haversine distances from every test cell centroid (Collier County, n=89) to the nearest
training cell centroid. All nearest-neighbor pairs are in adjacent counties (12_015 = Hendry
County, 12_081 = Lee County).

| Distance band | Test cells | % of test cells |
|---|---|---|
| ≤ 5 km | 0 | 0.0% |
| 5–10 km | 13 | 14.6% |
| 10–15 km | 23 | 25.8% |
| 15–20 km | 2 | 2.2% |
| 20–50 km | 51 | 57.3% |
| > 50 km | 0 | 0.0% |

- **13/89 test cells (14.6%) have a train-cell edge neighbor at ~9.9 km** (the grid cell spacing
  — these cells share an edge with a Hendry/Lee County training cell).
- **36/89 test cells (40.4%) have a train neighbor within 15 km.**
- Minimum distance: 9.9 km; Median: 20.2 km; Max: 36 km.
- 83 cross-boundary pairs within 15 km (36 unique test cells, 45 unique train cells).

This is **structural, not a code error**: any county-level spatial split will produce county-border
cells that are grid-adjacent. Eliminating adjacency would require a spatial buffer of ≥10 km
(drop all border cells from both sides), which is a design choice beyond A7's current scope.

### Investigation of the spatial > random anomaly

**Reported numbers (model_results.csv, RF):**

| H | Temporal PR-AUC | Random PR-AUC | Spatial PR-AUC |
|---|---|---|---|
| 1 | 0.638 | 0.720 | **0.783** |
| 3 | 0.634 | 0.677 | **0.733** |
| 5 | 0.668 | 0.679 | **0.731** |
| 7 | 0.498 | 0.631 | **0.663** |
| 14 | 0.445 | 0.552 | **0.636** |

Spatial PR-AUC exceeds random PR-AUC at every horizon. This ordering was flagged as a red flag
in the review mandate.

**Root cause identified: test-set prevalence inflation, not primarily code leakage.**

Collier County (12_115) is the most-sampled HAB hotspot in the HABSOS archive. The greedy
largest-block selection therefore creates a test set with a systematically higher positive rate
than the random test set:

| H | Random test pos% | Spatial test pos% | Ratio |
|---|---|---|---|
| 7 | 8.4% | 11.4% | 1.35× |
| 14 | 7.9% | 11.4% | 1.44× |

PR-AUC scales with class prevalence: on a test set that is 1.35× more bloom-dense, a calibrated
model will achieve higher PR-AUC regardless of train-test leakage, because (a) precision at any
recall threshold is higher and (b) the baseline (random classifier) PR-AUC is proportional to
positive rate. For H=7: spatial baseline ≈ 0.114 vs random baseline ≈ 0.084 — a 0.030 base-rate
uplift already explains most of the 0.032 gap in PR-AUC.

**Secondary contributor:** The 36/89 border-cell pairs have spatial autocorrelation leakage
through HAB history lags (hab_any_prior_7d/14d): if a training cell at 9.9 km shared a bloom
event with the adjacent test cell, the model learned that signal. This is a genuine but bounded
effect.

**Judgment:** The spatial>random ordering is **not primarily explained by leakage** — it is an
artifact of the greedy holdout choosing the single largest (and highest-prevalence) county. The
ordering is misleading and must be documented so the author does not present spatial PR-AUC as
evidence of geographic generalizability.

### Required action for A7 (documentation, not re-run)

Add to A7 decision log and NOTE(paper) tag:
> The spatial split holds out only Collier County (12_115), which has 1.4–1.5× the HAB positive
> rate of the rest of the training data. Spatial PR-AUC is inflated relative to random (and to
> temporal) primarily by this prevalence difference, not because the model generalizes better
> to held-out geography. County-border cells also exhibit structural spatial autocorrelation
> (13/89 test cells grid-adjacent to a train cell at ~10 km). The temporal split (train 2003-2015
> / test 2016-2021) is the primary honest forecast-skill estimate.

---

## Check 2: Temporal Split Embargo — NEAR-PASS

### Boundary definition

- Train: `year < 2016` → `date_T ≤ 2015-12-31`
- Test: `year >= 2016` → `date_T ≥ 2016-01-01`
- No explicit embargo gap implemented in code (lines 328–329 of R/07_modeling.R)

### Label-bleed quantification

A training row with `date_T = T` and horizon H has its label `HAB_H{k}` derived from bloom
status at `T + H`. If `T + H ≥ 2016-01-01`, that label is derived from the test period:

| H | Train rows | Bleed rows (label in test period) | % of train | date_T range | Cells affected |
|---|---|---|---|---|---|
| 1 | 4,787 | 1 | 0.02% | 2015-12-31 | 1 |
| 3 | 2,813 | 3 | 0.11% | 2015-12-29 – 2015-12-31 | 3 |
| 5 | 3,474 | 12 | 0.35% | 2015-12-27 – 2015-12-31 | 10 |
| 7 | 14,871 | 23 | 0.15% | 2015-12-28 – 2015-12-31 | 20 |
| 14 | 14,868 | 49 | 0.33% | 2015-12-21 – 2015-12-31 | 33 |

HABSOS sampling is sparse in late December, so even though up to H days of observations could
bleed, in practice only 1–49 rows are affected.

**Worst case (H=14): 49 training rows (0.33% of train) learned labels that correspond to bloom
status in Jan 2016 (test period).** The model has effectively been given 49 noisy data points
about early 2016 bloom conditions during training.

**Practical impact: negligible.** 49 rows / 14,868 training rows = 0.33%. The temporal PR-AUC
(0.445 for H=14) is the worst-case honest metric; this micro-bleed cannot have meaningfully
inflated it. No re-run is required, but the embargo gap limitation should be documented.

### Required action for A7 (documentation, not re-run)

Add to A7 decision log:
> NOTE(limitation): The year-based temporal split contains no embargo gap. For H=14, 49 training
> rows (0.33%) have label dates in Jan 2016 (test period). This is because HABSOS sampling in
> late Dec 2015 falls within the last H days of the training window. Impact is negligible given
> data sparsity, but a strict implementation would remove the H days preceding the cutoff from
> training for each horizon.

---

## Check 3: Feature-Matrix Exclusions — PASS

Independent verification against `data/processed/model_dataset.parquet` (114 cols):

| Exclusion | In data? | In feat_cols (H=7)? | Verdict |
|---|---|---|---|
| `HAB` (same-day label) | YES | **NO** — excluded by ALWAYS_EXCLUDE; verified by `stopifnot` | PASS |
| `HAB_H1/H3/H5/H14` (non-target horizons) | YES | **NO** — excluded by `excl_H` | PASS |
| `HAB_H7` (current target) | YES | **NO** — explicitly excluded as `target_col` | PASS |
| `max_count`, `n_samples` (label inputs) | YES | **NO** | PASS |
| `wind_u_ms`, `wind_v_ms`, `wind_speed_ms`, `wind_dir_deg`, `precip_mm`, `salinity_pss` | YES (100% NA) | **NO** | PASS |
| All 11 diagnostic/meta flag columns | YES | **NO** | PASS |
| `spatial_block_tiger` (CV key) | YES | **NO** | PASS |
| `cell_id`, `date_T`, `year` | YES | **NO** | PASS |

Computed feature matrix for H=7: **85 columns**, none in the exclusion list. All 29
`ALWAYS_EXCLUDE` entries are present in the data and absent from `feat_cols`. The 6 placeholder
env cols are confirmed 100% NA and correctly dropped.

---

## Check 4: Tiny-Block Merge — PASS

Confirmed from code (`R/07_modeling.R:224–233`) and data:

- 12_083: 1 row in cube → merged into `target = names(cnt)[which.max(cnt)]`
- 12_077: 1 row in cube → merged into same target
- Largest block = **12_115** (Collier County, 11,018 rows in full cube; ~6,500 in H=7 subset)
- Both singleton blocks are merged into 12_115, which is the held-out test block

Net effect: the singletons become part of the test fold. This is correct — they cannot be
standalone CV folds, and merging them into the only held-out block is safe. The training data
loses no valid rows.

---

## M1 Gate Decision

**M1 may be committed.** No disqualifying leakage found. Required actions before commit:

1. **A7 must add NOTE(paper) and NOTE(limitation) tags** (not code changes) documenting:
   - Spatial split prevalence inflation (Check 1)
   - Zero-embargo boundary bleed at H=14 (Check 2)
2. **A7 decision log**: add the two caveats from Checks 1 and 2.
3. **For the paper**: the temporal split (0.498 PR-AUC at H=7) is the headline honest number;
   spatial PR-AUC (0.663) must not be presented as evidence of geographic generalizability
   without noting the Collier County prevalence confound.

No re-run of modeling is required. The feature exclusions are clean and complete. The split
construction code is structurally sound.
