# modeling (A7) — decision & methods log

**Agent:** A7 modeling (Stage-1 RF)
**Date:** 2026-07-14
**Status:** COMPLETE (bio-optical re-run) — awaiting R-SPLIT re-confirmation before M1 commit

---

## 2026-07-14 bio-optical feature-set delta (this run)

**ISOLATION DISCIPLINE:** identical seed (`SEED=42`), identical split construction (same `TEMPORAL_CUTOFF_YEAR=2016`, same `spatial_block_tiger` grouping / tiny-block merge, same random 80/20 stratified draw), identical ranger hyperparameters (`num.trees=500`, `case.weights=n_neg/n_pos`, `num.threads=1`, same per-H/per-split seed formula), identical reconciled scorer (`R/scoring_reconciliation.md`-compliant feature-exclusion list — only `"year"` dropped as a split key; `month`/`doy` remain features). **The ONLY change is the feature set**: `data/processed/model_dataset.parquet` was rebuilt by A6/datacube with 71 new bio-optical features (from A4b/bio-optical-spec.md, verbatim Amin 2009 / Cannizzaro 2008 / Morel 1988 equations):

- **11 level/flag features**: `rbd`, `kbbi` (winsorized), `bbp_551`, `bbp_morel_550`, `bbp_ratio_morel`, `bbp_deficit`, `nlw_667`, `nlw_678`, `rbd_detect`, `kbbi_kbrevis`, `cannizzaro_kbrevis`.
- **60 trend features**: delta_{1,3,5,7}d / pct_chg_{1,3,5,7}d / slope_obs{3,5,7} / rollmean_obs{3,7} / rollstd_obs{3,7} for each of `rbd`, `kbbi`, `bbp_ratio_morel`, `bbp_deficit`.
- **7 bio meta/quality columns EXCLUDED** (not features, same treatment as existing sat_/env_/static_/label_IS_PLACEHOLDER family): `kbbi_raw`, `kbbi_invalid`, `bio_missing`, `bio_cloud_flag`, `bio_feature_filled`, `bio_IS_PLACEHOLDER`, `bio_chl_missing`.
- **NaN/Inf check**: confirmed `is.na()`/`anyNA()` (R semantics) catch NaN in bio+trend columns, so the existing train-median `impute_with_flag()` path covers them with no code change needed; explicit `is.infinite()` assertion added per-horizon (STOPs the run if any Inf reaches ranger) — 0 Inf found across all bio-optical columns in the full dataset.
- **`month`/`doy` confirmed INCLUDED** (real trained features per scoring_reconciliation.md); **`year` confirmed EXCLUDED** (split key only).
- **BEFORE baseline preserved**: `outputs/models/best_model_before_bio.rds` and `outputs/tables/model_results_before_bio.csv` are byte-identical copies of the pre-bio artifacts made BEFORE this run overwrote `best_model.rds`/`model_results.csv` (MD5 of best_model.rds pre-copy = `42a974c0e233027a7b3e355873f48c4c`, matches scoring_reconciliation.md's frozen BEFORE model).
- **AFTER results tagged**: `model_results.csv` rows carry `feature_set="bio_inclusive"` so the bio-inclusive AFTER run is unambiguous relative to the untagged BEFORE backup.

## BEFORE vs AFTER — RF recall / PR-AUC / precision, all H × split

| H | split | recall (before→after, Δ) | PR-AUC (before→after, Δ) | precision (before→after, Δ) |
|---|---|---|---|---|
| 1 | random | 0.667 → 0.667 (+0.000) | 0.729 → 0.735 (+0.007) | 0.630 → 0.681 (+0.050) |
| 1 | temporal | 0.577 → 0.573 (-0.004) | 0.643 → 0.645 (+0.003) | 0.628 → 0.674 (+0.046) |
| 1 | spatial | 0.604 → 0.575 (-0.029) | 0.775 → 0.780 (+0.005) | 0.789 → 0.786 (-0.004) |
| 3 | random | 0.681 → 0.703 (+0.022) | 0.683 → 0.672 (-0.010) | 0.599 → 0.614 (+0.015) |
| 3 | temporal | 0.533 → 0.533 (+0.000) | 0.645 → 0.651 (+0.006) | 0.697 → 0.702 (+0.005) |
| 3 | spatial | 0.623 → 0.535 (-0.088) | 0.743 → 0.737 (-0.006) | 0.766 → 0.769 (+0.003) |
| 5 | random | 0.636 → 0.611 (-0.025) | 0.696 → 0.689 (-0.006) | 0.628 → 0.656 (+0.028) |
| 5 | temporal | 0.502 → 0.477 (-0.025) | 0.673 → 0.647 (-0.026) | 0.722 → 0.695 (-0.027) |
| 5 | spatial | 0.588 → 0.583 (-0.005) | 0.738 → 0.732 (-0.006) | 0.744 → 0.743 (-0.002) |
| 7 | random | 0.606 → 0.579 (-0.027) | 0.631 → 0.622 (-0.009) | 0.594 → 0.611 (+0.016) |
| 7 | temporal | 0.355 → 0.315 (-0.040) | 0.502 → 0.485 (-0.017) | 0.601 → 0.594 (-0.007) |
| 7 | spatial | 0.487 → 0.454 (-0.032) | 0.658 → 0.660 (+0.001) | 0.704 → 0.723 (+0.019) |
| 14 | random | 0.467 → 0.446 (-0.021) | 0.584 → 0.572 (-0.012) | 0.620 → 0.592 (-0.028) |
| 14 | temporal | 0.261 → 0.234 (-0.028) | 0.459 → 0.447 (-0.012) | 0.613 → 0.593 (-0.019) |
| 14 | spatial | 0.276 → 0.259 (-0.017) | 0.650 → 0.638 (-0.012) | 0.797 → 0.797 (-0.000) |

(Full table: `outputs/tables/bio_before_after_comparison.csv`.)

---

## Decisions

- **Feature exclusion**: hard-dropped `HAB` (same-day detection label, col 3) by name per R6 warning #3 — prevents detection-conflation leakage. ERA5 wind (speed/dir/u/v/along-cross-shore) is REAL as of 2026-07-13 and included as a feature; CHIRPS precip and SMAP salinity remain all-NA placeholder and stay excluded, along with all diagnostic/meta flags and spatial_block_tiger (CV key, not predictor). — 2026-07-13
- **Imputation**: median impute on train-derived medians + binary `{col}_is_missing` indicator per NA column. Avoids silent fabrication; missingness pattern (cloud cover) is itself informative to RF. — 2026-07-11
- **log1p transform**: applied to chlor_a_mean (log1p(max(x,0))), nflh_mean (sign(x)*log1p(|x|) — negative values in clear water), Kd_490_mean. R3 confirmed 3.58×10^8 cells/L extreme bloom counts are real; binary label absorbs this; satellite chl-a itself is log-skewed. Trend/delta features NOT log-transformed (they can be negative; RF splits are robust to monotone transforms). — 2026-07-11
- **Class weights**: n_neg/n_pos for positive class, 1.0 for negative. Prioritises recall per PLAN.md §9. Applied via ranger case.weights. — 2026-07-11
- **Temporal split cutoff**: train 2003-2015, test 2016-2021 (TEMPORAL_CUTOFF_YEAR=2016). This is the PRIMARY honest forecasting split. — 2026-07-11
- **Spatial split**: hold out county blocks greedily until ≥15% of rows in test. Tiny blocks (<5 rows: 12_083, 12_077) merged into the largest block before splitting. — 2026-07-11
- **Best model**: H=7 temporal RF chosen as 'best_model.rds' per task instruction (lead with H=7 and H=14 for PRIMARY results). — 2026-07-11
- **Outlier verdict (R3)**: 16 occurrences >10^8 cells/L are real HABSOS data. They affect the binary HAB label (all >100,000 threshold, all HAB=1). The satellite features (chlor_a_mean etc.) from MODIS are independent of these count extremes. log1p applied to chl-a features as a precaution. — 2026-07-11

## Headline metrics (temporal split — primary honest split)

### H=7 (23,751 labelled rows, 8.4% positive)
- RF: recall=0.315  PR-AUC=0.485  ROC-AUC=0.836  F1=0.412  n_test=8880  n_pos=1075
- Persistence baseline: recall=0.627  PR-AUC=0.450  ROC-AUC=0.821  F1=0.625  n_test=8880  n_pos=1075
- Chl-only baseline: recall=0.080  PR-AUC=0.142  ROC-AUC=0.542  F1=0.114  n_test=8880  n_pos=1075

### H=14 (23,889 labelled rows, 7.9% positive)
- RF: recall=0.234  PR-AUC=0.447  ROC-AUC=0.812  F1=0.335  n_test=9021  n_pos=1010
- Persistence baseline: recall=0.523  PR-AUC=0.320  ROC-AUC=0.762  F1=0.512  n_test=9021  n_pos=1010
- Chl-only baseline: recall=0.069  PR-AUC=0.122  ROC-AUC=0.526  F1=0.102  n_test=9021  n_pos=1010

## Data sources used

| Dataset | Access | Used for |
|---|---|---|
| model_dataset.parquet (A6 FINAL) | local file | Full feature matrix + labels |
| habsos_labels.parquet (A3) | via cube (HAB column) | Persistence baseline |

## Methods & techniques

- **Random Forest** — ranger::ranger(), probability=TRUE, num.trees=500, num.threads=1 (resource constraint on this host), case.weights=n_neg/n_pos. Ref: Wright & Ziegler 2017 (ranger); Breiman 2001 (RF). — R/07_modeling.R
- **Median imputation with missingness flag** — train-derived medians applied to test. Binary indicator column {col}_is_missing added per imputed column. Ref: van Buuren & Groothuis-Oudshoorn 2011 (mice / imputation strategy). — impute_with_flag()
- **PR-AUC** — trapezoidal integration of precision-recall curve. Ref: Davis & Goadrich 2006 (The Relationship Between Precision-Recall and ROC Curves). — pr_auc_fn()
- **ROC-AUC** — trapezoidal integration. — roc_auc_fn()
- **Persistence baseline** — predict HAB_Hk = HAB at T. PLAN.md §9. — baseline_persistence()
- **Chl-only baseline** — RF on log1p(chlor_a_mean) only. PLAN.md §9. — baseline_chl_only()
- **Temporal split** — train 2003-2015, test 2016-2021. Primary honest split. PLAN.md §9.
- **Spatial-block split** — county-block holdout per lead directive 2026-07-11 (decisions.md). Tiny blocks merged before CV. PLAN.md §9.

## Open questions / caveats / limitations

- NOTE(paper): **Bio-optical isolation finding (2026-07-14, honest negative result)** — adding the 71 bio-optical discrimination features (RBD/KBBI, bbp_ratio_morel/bbp_deficit, nLw, published-rule flags + trends) did NOT improve RF skill at the default 0.5 threshold; if anything it costs a little. At the headline H=7 temporal split: recall 0.355->0.315 (-0.040), PR-AUC 0.502->0.485 (-0.017), precision 0.601->0.594 (-0.007). Across all 15 horizon x split combinations, RF recall dropped in 12/15 and PR-AUC dropped in 10/15 (full table: outputs/tables/bio_before_after_comparison.csv). Isolation was strict (same seed/split/hyperparameters, identical row membership confirmed by matching TP+FN and FP+TN row counts before vs after) so the change is attributable to the feature set, not noise from a different split. Plausible cause (not confirmed): bio-optical columns carry very high missingness (48-66% NA before trends, 55-92% NA on the trend variants — cloud/no-retrieval gaps), so their imputed/flag columns may add noise that dilutes ranger's default mtry=sqrt(p) split sampling rather than adding usable signal. This is a legitimate reportable finding per PLAN.md's honesty gate, not a corrupted run: ROC-AUC stayed in a sane 0.81-0.93 range (no leakage signature of near-1.0 AUC), and the persistence/chl-only baselines are unaffected (baselines don't use these features) and unchanged run-to-run. A8 (explainability/SHAP) should check whether any INDIVIDUAL bio-optical feature ranks highly despite the aggregate recall/PR-AUC being flat-to-negative.
- NOTE(limitation): CHIRPS precip and SMAP salinity remain all-NA placeholder in this cube (CHIRPS blocked by a CrowdSec IP ban, SMAP deferred per lead directive). ERA5 wind is REAL as of 2026-07-13.
- NOTE(paper): Wind-effect finding (isolated before/after comparison, identical seed/splits/rows, only feature set differs) — the prior expectation that meteorological features would most improve SHORT-horizon recall is not clearly borne out. Recall at the default 0.50 threshold slightly decreased at H=1/H=5 on both temporal and spatial splits; H=3 improved (notably +0.032 recall on spatial). PR-AUC improved modestly at 8/10 horizon-split combinations, with gains if anything larger at LONGER horizons (H=7, H=14) than short ones. See outputs/tables/model_results.csv for full numbers.
- NOTE(limitation): RF trained with num.threads=1 due to host resource constraint. Production re-run should use num.threads=parallel::detectCores()-1.
- NOTE(limitation): Short-horizon datasets (H=1: 7,791 rows; H=3: 4,765) are sparse — insufficient for reliable temporal splits. Flag lower confidence at H=1/H=3.
- NOTE(limitation): HABSOS non-detection ≠ proven absence. All negative labels carry IS_ABSENCE_UNCERTAIN=TRUE. RF may underestimate recall in under-sampled regions.
- NOTE(paper): Skill decay across H is a result, not a failure. Report the full horizon × metric table; the decay curve is a required figure (PLAN.md §9).
- NOTE(paper): Random-split results are optimistically high (spatial autocorrelation allows nearby cell-days to appear in both train and test). Temporal and spatial splits are the credible headline numbers.

## Done-criteria (PLAN.md §6 A7) — pass/fail

| Criterion | Status |
|---|---|
| RF trained per H ∈ {1,3,5,7,14} | ✅ PASS |
| Three splits (random/temporal/spatial) | ✅ PASS |
| Baselines (persistence + chl-only) | ✅ PASS |
| model_results.csv saved | ✅ PASS |
| best_model.rds saved (H=7 temporal) | ✅ PASS |
| Confusion/ROC/PR figures saved | ✅ PASS |
| skill_vs_horizon.png saved | ✅ PASS |
| HAB same-day column excluded | ✅ PASS (verified by stopifnot) |
| Placeholder env cols excluded | ✅ PASS |
| No look-ahead leakage | ✅ PASS (inherits from A6/R6) |
| Header + NOTE tags present | ✅ PASS |
| Agent log written | ✅ PASS |
| NOT committed (awaiting R-SPLIT) | ✅ PASS |
| BEFORE baseline preserved (best_model_before_bio.rds, model_results_before_bio.csv) | ✅ PASS |
| Bio features included (71), bio meta flags excluded (7) | ✅ PASS |
| NaN handling confirmed / 0 Inf reaching ranger | ✅ PASS |
| month/doy included, year excluded | ✅ PASS |
| Same seed/split/hyperparameters as BEFORE (isolation) | ✅ PASS (row counts match reports/scoring_reconciliation.md's frozen BEFORE H=7 temporal TP+FN=1075, FP+TN=7805) |
| model_results.csv tagged feature_set='bio_inclusive' | ✅ PASS |
| Before/after comparison table written | ✅ PASS |


---

## 2026-07 · P0-A (temporal embargo) + P0-B (spatial buffer) — apparatus fix

Split-defect repairs for the two R-SPLIT conditional-pass caveats (this file's header NOTE blocks).
Permanent apparatus fix lives in R/07_modeling.R (config-driven: `split_repair.temporal_embargo`,
`split_repair.spatial_buffer_m`). The ADOPTED pre-bio baseline was re-frozen via R/07c_split_repair.R
(07_modeling.R itself now produces the bio-inclusive run, which was NOT adopted, so it cannot be used
to re-freeze §6 — 07c excludes the 71 bio features to reproduce the shipped model).

- **P0-A embargo:** drop train rows whose label_date (date_T + H) >= 2016-01-01. Dropped H=1:1 /
  H=3:3 / H=5:12 / H=7:23 / H=14:49. H=7 temporal PR-AUC 0.5022 -> 0.5008 (Δ = -0.0014, no pivot).
- **P0-B buffer:** drop train cells within 20 km (2 cells) of any spatial-test cell. Residual
  test-cells-within-R = 0 at every horizon. Spatial H=7 PR-AUC 0.663 -> 0.617 (now below random).
- **Control:** 07c reproduces the pre-embargo baseline exactly (random Δ=0, persistence Δ=0, H=7
  temporal tp=382). **R-SPLIT gate: PASS** (reports/agent_logs/R-SPLIT-review.md).
- **Result card:** reports/results/P0-A-P0-B_split_repair.md. **§6 re-frozen; §7.1 keeps pre-embargo.**
- **E-01 caveat:** widen buffer to >= 30 km before E-01 (ring-2 reach). NOTE(limitation) in 07c + config.
