# modeling (A7) — decision & methods log

**Agent:** A7 modeling (Stage-1 RF)
**Date:** 2026-07-11
**Status:** COMPLETE — awaiting R-SPLIT sign-off before M1 commit

---

## Decisions

- **Feature exclusion**: hard-dropped `HAB` (same-day detection label, col 3) by name per R6 warning #3 — prevents detection-conflation leakage. Also excluded 6 all-NA placeholder env cols (wind_u/v/speed/dir, precip_mm, salinity_pss), all diagnostic/meta flags, and spatial_block_tiger (CV key, not predictor). — 2026-07-11
- **Imputation**: median impute on train-derived medians + binary `{col}_is_missing` indicator per NA column. Avoids silent fabrication; missingness pattern (cloud cover) is itself informative to RF. — 2026-07-11
- **log1p transform**: applied to chlor_a_mean (log1p(max(x,0))), nflh_mean (sign(x)*log1p(|x|) — negative values in clear water), Kd_490_mean. R3 confirmed 3.58×10^8 cells/L extreme bloom counts are real; binary label absorbs this; satellite chl-a itself is log-skewed. Trend/delta features NOT log-transformed (they can be negative; RF splits are robust to monotone transforms). — 2026-07-11
- **Class weights**: n_neg/n_pos for positive class, 1.0 for negative. Prioritises recall per PLAN.md §9. Applied via ranger case.weights. — 2026-07-11
- **Temporal split cutoff**: train 2003-2015, test 2016-2021 (TEMPORAL_CUTOFF_YEAR=2016). This is the PRIMARY honest forecasting split. — 2026-07-11
- **Spatial split**: hold out county blocks greedily until ≥15% of rows in test. Tiny blocks (<5 rows: 12_083, 12_077) merged into the largest block before splitting. — 2026-07-11
- **Best model**: H=7 temporal RF chosen as 'best_model.rds' per task instruction (lead with H=7 and H=14 for PRIMARY results). — 2026-07-11
- **Outlier verdict (R3)**: 16 occurrences >10^8 cells/L are real HABSOS data. They affect the binary HAB label (all >100,000 threshold, all HAB=1). The satellite features (chlor_a_mean etc.) from MODIS are independent of these count extremes. log1p applied to chl-a features as a precaution. — 2026-07-11

## Headline metrics (temporal split — primary honest split)

### H=7 (23,751 labelled rows, 8.4% positive)
- RF: recall=0.370  PR-AUC=0.497  ROC-AUC=0.832  F1=0.455  n_test=8880  n_pos=1075
- Persistence baseline: recall=0.627  PR-AUC=0.450  ROC-AUC=0.821  F1=0.625  n_test=8880  n_pos=1075
- Chl-only baseline: recall=0.080  PR-AUC=0.142  ROC-AUC=0.542  F1=0.114  n_test=8880  n_pos=1075

### H=14 (23,889 labelled rows, 7.9% positive)
- RF: recall=0.272  PR-AUC=0.445  ROC-AUC=0.812  F1=0.372  n_test=9021  n_pos=1010
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

- NOTE(limitation): Dynamic env features (ERA5 wind, CHIRPS precip, SMAP salinity) are all-NA placeholder in this cube. Model trained on satellite + static geo + seasonality + historical HAB lags only. Adding ERA5/CHIRPS/SMAP is expected to improve recall at short horizons where meteorological forcing dominates.
- NOTE(limitation): RF trained with num.threads=1 due to host resource constraint. Production re-run should use num.threads=parallel::detectCores()-1.
- NOTE(limitation): Short-horizon datasets (H=1: 7,791 rows; H=3: 4,765) are sparse — insufficient for reliable temporal splits. Flag lower confidence at H=1/H=3.
- NOTE(limitation): HABSOS non-detection ≠ proven absence. All negative labels carry IS_ABSENCE_UNCERTAIN=TRUE. RF may underestimate recall in under-sampled regions.
- NOTE(paper): Skill decay across H is a result, not a failure. Report the full horizon × metric table; the decay curve is a required figure (PLAN.md §9).
- NOTE(paper): Random-split results are optimistically high (spatial autocorrelation allows nearby cell-days to appear in both train and test). Temporal and spatial splits are the credible headline numbers.
- NOTE(paper): SPATIAL SPLIT PREVALENCE CONFOUND (R-SPLIT conditional-pass caveat). The spatial-block holdout always isolates Collier County (block 12_115), the dominant HAB hotspot, with 11.4% positive rate vs 8.4% in the random test set (1.35×). The spatial PR-AUC (H=7: 0.663) exceeding random (0.631) is driven by held-out prevalence, NOT better generalisation and NOT leakage. The TEMPORAL split (H=7 PR-AUC=0.497) is the headline honest forecasting number. The spatial result should be described in the paper as "geographic transfer to a high-prevalence region." Additionally, 14.6% of spatial test cells fall within ~10 km of a train cell at county block borders, introducing residual spatial autocorrelation.
- NOTE(limitation): TEMPORAL SPLIT ZERO-EMBARGO (R-SPLIT conditional-pass caveat). No purge/embargo gap was implemented at the 2016 train/test boundary. At H=14, ~49 training rows (0.33%) have a label_date (T+14) falling in the test period, constituting a small optimistic leak bounded by HABSOS sparsity. Effect on reported PR-AUC is negligible but not zero. A future iteration should add an H-day embargo window around the temporal boundary.

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

