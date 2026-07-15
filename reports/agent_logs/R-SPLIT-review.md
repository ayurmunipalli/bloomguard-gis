# R-SPLIT — Independent Split-Integrity Review

**Reviewer:** R-SPLIT (Sonnet 4.6)
**Scope:** A7 train/test split construction only (not model code, hyperparameters, or metrics)
**Artifacts reviewed:** `R/07_modeling.R`, `data/processed/model_dataset.parquet` (65,939 × 114),
`data/processed/static_geo.parquet`, `outputs/tables/model_results.csv`,
`reports/agent_logs/modeling.md`, `reports/agent_logs/R6-datacube-review.md`, `reports/decisions.md`
**Date:** 2026-07-11
**Correction (2026-07-12, lead):** The held-out block `12_115` was originally mislabeled here as
"Collier County." Verified against `static_geo.parquet` (TIGER `county_name`), `12_115` = **Sarasota
County** (largest block, ~11.4% prevalence — the prevalence artifact driving spatial-split PR-AUC).
All "Collier County" references for `12_115` in this log have been corrected to Sarasota. (Collier is
`12_021`, a separate, lower-prevalence block.) The prevalence-confound conclusion is unchanged; only
the county name was wrong.

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

A7's spatial split holds out **block 12_115 (Sarasota County)** as the sole test fold for every
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

Computed haversine distances from every test cell centroid (Sarasota County, n=89) to the nearest
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

Sarasota County (12_115) is the most-sampled HAB hotspot in the HABSOS archive. The greedy
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
> The spatial split holds out only Sarasota County (12_115), which has 1.4–1.5× the HAB positive
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
- Largest block = **12_115** (Sarasota County, 11,018 rows in full cube; ~6,500 in H=7 subset)
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
   without noting the Sarasota County prevalence confound.

No re-run of modeling is required. The feature exclusions are clean and complete. The split
construction code is structurally sound.

---

## Addendum (2026-07-13, R-SPLIT) — Re-verification after ERA5 wind added

**Trigger:** Real ERA5 wind features (`wind_u_ms`, `wind_v_ms`, `wind_speed_ms`, `wind_dir_deg`,
`wind_along_ms`, `wind_cross_ms`) replaced the all-NA placeholders, and Stage-1 RF was retrained.
Split-construction code was reported unchanged; scope here is to confirm that.

### Verdict: **PASS — split construction unaffected, prior caveats still apply**

1. **Diff-check.** `git diff -- R/07_modeling.R` against the last commit shows only comment/NOTE
   changes plus the `ALWAYS_EXCLUDE` feature list. `TRAIN_FRAC <- 0.80` (L87),
   `TEMPORAL_CUTOFF_YEAR <- 2016L` (L88), the random stratified split (`set.seed(SEED + H)`,
   `sample(pos_idx, ...)`/`sample(neg_idx, ...)`, L348-352), the temporal boundary
   (`year < / >= TEMPORAL_CUTOFF_YEAR`, L357-358), and `merge_tiny_blocks()` (L253) are
   byte-identical to what the 2026-07-11 review analyzed. No split-logic lines touched.

2. **Row counts (independent read via python3/pyarrow of `data/processed/model_dataset.parquet`,
   65,939 × 116 rows/cols — Rscript avoided per known sandbox hang risk):**

   | H | rows (this run) | rows (2026-07-11) | match |
   |---|---|---|---|
   | 1 | 7,791 | 7,791 | Y |
   | 3 | 4,765 | 4,765 | Y |
   | 5 | 6,151 | 6,151 | Y |
   | 7 | 23,751 | 23,751 | Y |
   | 14 | 23,889 | 23,889 | Y |

   Identical to the byte. Since split assignment depends only on `cell_id`/`date_T`/`year`/
   `spatial_block_tiger` — none of which changed — row membership per fold (random/temporal/
   spatial) is unchanged. The Sarasota-County (12_115) holdout and the H=14 ~49-row embargo
   bleed are therefore unchanged in substance; both caveats from the 2026-07-11 review
   (prevalence confound, zero-embargo boundary bleed) still apply and must still be cited
   wherever the retrained numbers are reported.

3. **Feature-exclusion check (new, this run).** Confirmed in code and data:
   `wind_u_ms/wind_v_ms/wind_speed_ms/wind_dir_deg/wind_along_ms/wind_cross_ms` are **not** in
   `ALWAYS_EXCLUDE` (L106-129) and are 100% non-null in the parquet (65,939/65,939 each) — they
   are now live features, as intended. `precip_mm` and `salinity_pss` remain in
   `ALWAYS_EXCLUDE` and remain 100% NA (0/65,939 non-null) — correctly still excluded
   placeholders.

**Conclusion:** Adding wind features did not alter split construction, row membership, or fold
boundaries. No new leakage introduced. The two 2026-07-11 caveats (Sarasota prevalence
confound on the spatial split; zero-embargo H=14 boundary bleed, ~49 rows/0.33%) remain in force
and must accompany any reporting of the new wind-augmented model numbers.

---

## Addendum (2026-07-14, R-SPLIT) — Re-verification after bio-optical features added

**Trigger:** A7 retrained Stage-1 RF with 71 new bio-optical discrimination features
(RBD/KBBI, bbp_ratio_morel/bbp_deficit, nLw(667/678), published-rule flags + 60 trend
variants; `model_dataset.parquet` grew 65,939×114 → 65,939×194). A7 reported the split
logic byte-identical to the previously-signed-off pipeline. Scope here: re-confirm that
claim and re-verify split integrity against the new `best_model.rds`.

### 1. Diff-check — split construction code unchanged

`git diff -- R/07_modeling.R` (uncommitted, working tree vs last commit) shows the only
changes are: header/NOTE comments, a `FEATURE_SET_TAG <- "bio_inclusive"` metadata string
(does not affect training), 7 new entries added to `ALWAYS_EXCLUDE` (`kbbi_raw`,
`kbbi_invalid`, `bio_missing`, `bio_cloud_flag`, `bio_feature_filled`,
`bio_IS_PLACEHOLDER`, `bio_chl_missing` — all bio-optical QC/meta flags, none are
`cell_id`/`date_T`/`spatial_block_tiger`/`year`, so none touch split keys), a new
per-horizon `is.infinite()` STOP-guard on bio feature columns (feature-integrity check,
not split logic), and a new BEFORE-vs-AFTER reporting block appended after model training
completes (reads a frozen backup CSV for comparison, writes
`bio_before_after_comparison.csv`; runs after all splitting/training is done).

**Not touched by the diff:** `TRAIN_FRAC` (L~101), `TEMPORAL_CUTOFF_YEAR` (L~101, still
`2016L`), `MIN_BLOCK_ROWS`/`merge_tiny_blocks()`, the `year` derivation
(`dt[["year"]] <- as.integer(substr(...))`), `feat_cols <- setdiff(names(h_dt), c(excl_H,
target_col, "year"))`, `set.seed(SEED + H)` + `pos_idx`/`neg_idx`/`sample()` (random
split), `temp_train_idx`/`temp_test_idx <- which(h_dt$year < / >= TEMPORAL_CUTOFF_YEAR)`
(temporal split), and the spatial-block holdout (`block_sizes`, `cumulative >= 0.15`,
`holdout_blocks`, `spat_test_idx`). Confirmed by direct inspection of current line
content, not just diff absence — these blocks read byte-identical to the 2026-07-13
addendum's citations, only shifted a few lines by inserted comments elsewhere.

### 2. Independent re-derivation from the retrained `model_dataset.parquet`

Re-ran the split logic independently (`Rscript --vanilla`, renv lib path, arrow +
data.table) directly against the new 195-column dataset (194 feature/label cols + derived
`year`), reproducing `07_modeling.R`'s exact split code:

| H | rows | temp_train | temp_test | spatial holdout block(s) | spat_test | spat_test% |
|---|---|---|---|---|---|---|
| 1 | 7,791 | 4,787 | 3,004 | 12_115 | 3,279 | 42.1% |
| 3 | 4,765 | 2,813 | 1,952 | 12_115 | 2,228 | 46.8% |
| 5 | 6,151 | 3,474 | 2,677 | 12_115 | 2,399 | 39.0% |
| 7 | 23,751 | 14,871 | 8,880 | 12_115 | 6,576 | 27.7% |
| 14 | 23,889 | 14,868 | 9,021 | 12_115 | 6,388 | 26.7% |

Row counts and spatial holdout (**always and only block 12_115 / Sarasota County**, same
row counts and percentages) are **byte-identical** to the 2026-07-11 review table and the
2026-07-13 addendum. Adding 80 new columns did not change which rows exist, which cell
falls in which spatial block, or which rows fall before/after the 2016 cutoff — expected,
since none of `cell_id`/`date_T`/`year`/`spatial_block_tiger` changed.

**H=14 embargo re-check (the previously-flagged boundary case):** re-computed bleed rows
(train rows where `date_T + H` lands ≥ 2016-01-01) directly against the new dataset:

| H | bleed rows | % of train | cells affected |
|---|---|---|---|
| 1 | 1 | 0.021% | 1 |
| 3 | 3 | 0.107% | 3 |
| 5 | 12 | 0.345% | 10 |
| 7 | 23 | 0.155% | 20 |
| 14 | **49** | 0.330% | 33 |

Exact match to the 2026-07-11 table, all five horizons. **The H=14 zero-embargo boundary
bleed is unchanged, not newly worsened.**

### 3. Direct check against the retrained `best_model.rds` artifact

Loaded the new `outputs/models/best_model.rds` (`feature_set = "bio_inclusive"`,
confirming this is the post-bio retrain) and compared its stored `train_idx`/`test_idx`
(H=7, temporal) against the independently-recomputed temporal split indices:

- `length(test_idx)` = 8,880 both ways.
- `setequal(recomputed, stored)` = **TRUE**; `identical(recomputed, stored)` = **TRUE**
  (same set, same order).
- `max(year)` among stored `train_idx` rows = **2015**; `min(year)` among stored
  `test_idx` rows = **2016**. No cross-boundary rows in either direction.
- `best$feat_cols`: `"year"` absent (correctly excluded as split key); `"month"`/`"doy"`
  present (correctly included as features, per `scoring_reconciliation.md`'s authoritative
  rule); the 8 checked bio-optical level features (`rbd`, `kbbi`, `bbp_551`,
  `bbp_morel_550`, `bbp_ratio_morel`, `bbp_deficit`, `nlw_667`, `nlw_678`) are present as
  trained features, as A7 intended.

### Verdict: **PASS — split construction unaffected, retrained best_model.rds cleared**

The bio-optical feature addition did not alter split construction, row membership, fold
boundaries, or the retained model's stored train/test indices. No new leakage introduced.
The two standing caveats from 2026-07-11 remain in force and must continue to accompany
any reporting of the bio-inclusive model numbers:

1. Spatial split holds out only Sarasota County (12_115), which has 1.4–1.5× the HAB
   positive rate of the rest of the data — spatial PR-AUC is prevalence-inflated, not
   evidence of geographic generalization.
2. H=14 temporal split has a 49-row (0.33%) zero-embargo boundary bleed, unchanged in
   count, percentage, or affected cells.

No action required of `modeling`. A7's bio-inclusive `best_model.rds` (H=7, temporal) is
cleared on split-integrity grounds.

---

## 2026-07 · P0-A (temporal embargo) + P0-B (spatial buffer) — GATE REVIEW: **PASS**

**Reviewer:** R-SPLIT (fable-5, train/test split leakage, block authority).
**Scope:** the two split-defect repairs in `R/07c_split_repair.R` (adopted pre-bio re-freeze) and
the apparatus fix in `R/07_modeling.R`. Verified independently from the parquet — did not trust the
harness's own drop report.

**Checklist:**
1. **Control reproduces the frozen baseline (no accidental change).** PASS. Control arm (repair OFF,
   bio excluded) reproduces `model_results.csv` exactly: random split Δ=0 all rows; all persistence
   rows Δ=0; H=7 temporal rf pr_auc=0.5022, tp=382/fp=254/fn=693/tn=7551. 0 unexpected rows
   (`outputs/tables/split_repair_validation.csv`).
2. **P0-A embargo — no training label_date in the test period.** PASS at every horizon. Independent
   recomputation: max train label_date (date_T + H) = 2015-12-31 (H=1/3), 2015-12-28 (H=5),
   2015-12-30 (H=7/14) — all < the 2016-01-01 cutoff. The ~49-row H=14 leak is closed.
3. **P0-B buffer — no train cell within R of any test cell.** PASS at every horizon. Independent
   min train→test cell distance = 20,000 m = R at every horizon (drop `<R`, keep `≥R`). Residual
   test-cells-within-R = 0 by construction.
4. **Test sets unchanged (repairs drop only training rows).** PASS. Temporal test = year≥2016;
   spatial test = holdout blocks; both identical to pre-repair. Confirmed by persistence rows Δ=0
   (persistence depends only on the test set) and identical n_test/n_pos.
5. **Orthogonality (one-change attribution).** PASS. Embargo touches only the temporal split, buffer
   only the spatial split, random split untouched (Δ=0). Temporal Δ = embargo effect; spatial Δ =
   buffer effect; no cross-confound.

**Headline delta:** H=7 temporal PR-AUC 0.5022 → 0.5008 (Δ = −0.0014), inside the ±0.02 pivot band
(§7.3) — not a pivot trigger. Spatial PR-AUC drops materially (H=7 0.663→0.617) — the buffer
removing real border leakage, expected and correct.

**Open item (not blocking P0-A/P0-B, blocking E-01):** the 20 km buffer is < E-01's ring-2 reach
(~20 km). Before E-01 runs, widen `config split_repair.spatial_buffer_m` to ≥ 30000 (ring radius +
1 cell) or the neighbour features re-open the leak. Recorded as `NOTE(limitation)` in
`R/07c_split_repair.R` and PROJECT.md §2.1.

**Verdict: PASS — no merge block.** Both repairs are sound; the re-frozen baseline is honest.
