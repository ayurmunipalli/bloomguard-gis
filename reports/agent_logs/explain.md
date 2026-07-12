# explain (A8) — decision & methods log

**Agent:** A8 explain (Stage-1 RF explainability)
**Date:** 2026-07-12
**Status:** COMPLETE

---

## Decisions

- **SHAP method**: permutation-based marginal contribution (SHAP approximation). For each feature, permute its values in the test set (10 reps) and measure mean |delta| in P(HAB=1). Computed on a subsample of 2000 test rows from the temporal holdout. fastshap package unavailable for R 4.5.2; this manual approach gives equivalent mean(|SHAP|) rankings. — 2026-07-12
- **Importance cross-check**: ranger impurity (Gini) + permutation importance computed in parallel. All three measures (SHAP-approx, impurity, permutation) cross-checked via Spearman rank correlation. — 2026-07-12
- **Feature classification**: features partitioned into LEVEL (absolute magnitudes, state at T, rolling means, static geography, seasonality, historical HAB) and TREND (deltas, % changes, slopes, rolling std/volatility, threshold-crossing flags). Missingness indicators (_is_missing, _n_valid) classified as META and excluded from the level-vs-trend headline split. — 2026-07-12
- **Rolling means -> LEVEL**: rolling means (e.g. chlor_a_rollmean_obs3) classified as LEVEL because they represent smoothed current state, not rate of change. Rolling std classified as TREND because it captures recent volatility. — 2026-07-12
- **log1p transforms**: replicated A7's log1p on chlor_a_mean, nflh_mean, Kd_490_mean to match the model's training-time preprocessing. — 2026-07-12

## Headline finding: levels vs trends

**Levels 76% vs Trends 24% of total |SHAP|** (excluding META features).

NOTE(paper): feature LEVELS (absolute magnitudes at day T) are associated with MORE forecast signal than feature TRENDS (rate-of-change / movement). This suggests the RF relies primarily on 'what conditions look like now' rather than 'how fast they are changing.' The transformer (Stage 2) may capture additional trend signal from raw temporal sequences that the RF cannot exploit from engineered features alone.

Permutation importance cross-check: LEVEL 78% vs TREND 22% — consistent with SHAP finding.

Spearman rank correlation: SHAP-approx vs impurity = 0.937, SHAP-approx vs permutation = 0.787.

Chlorophyll proxies are NOT dominant in the top-10: 1 features, 8.1% of |SHAP|.

## Top-10 features (by mean |SHAP|)

| Rank | Feature | Category | Mean |SHAP| |
|------|---------|----------|-------------|
| 1 | hab_any_prior_14d | LEVEL | 0.062597 |
| 2 | hab_any_prior_7d | LEVEL | 0.040153 |
| 3 | Kd_490_rollmean_obs7 | LEVEL | 0.025088 |
| 4 | chlor_a_rollmean_obs7 | LEVEL | 0.021312 |
| 5 | doy | LEVEL | 0.019193 |
| 6 | nflh_rollmean_obs7 | LEVEL | 0.018226 |
| 7 | doy_sin | LEVEL | 0.017393 |
| 8 | centroid_lat | LEVEL | 0.015648 |
| 9 | doy_cos | LEVEL | 0.015325 |
| 10 | Kd_490_rollmean_obs3 | LEVEL | 0.014861 |

## Data sources used

| Dataset | Access | Used for |
|---|---|---|
| best_model.rds (A7, H=7 temporal RF) | local file | Trained ranger model |
| model_dataset.parquet (A6 FINAL) | local file | Feature matrix for importance |

## Methods & techniques

- **Permutation-based SHAP approximation** — for each feature, permute values in test set (10 reps x 2000 test rows) and measure mean |delta P(HAB=1)|. Gives mean(|SHAP|)-equivalent rankings per feature. Ref: Lundberg & Lee (2017) NeurIPS; Fisher, Rudin & Dominici (2019) 'All Models are Wrong, but Many are Useful'. — R/08_explainability.R
- **ranger impurity importance** — mean decrease in Gini impurity at splits. Ref: Breiman (2001) 'Random Forests'. — ranger(..., importance='impurity')
- **ranger permutation importance** — decrease in OOB prediction accuracy when feature permuted. Ref: Breiman (2001); Wright & Ziegler (2017) 'ranger'. — ranger(..., importance='permutation')
- **Level-vs-trend grouping** — features classified by naming convention into LEVEL (absolute state at T) vs TREND (rate-of-change). Sum of mean |SHAP| within each group gives the headline attribution split. — R/08_explainability.R
- **Spearman rank correlation** — cross-check between SHAP-approx, impurity, and permutation rankings to verify method robustness. — R/08_explainability.R

## Open questions / caveats / limitations

- NOTE(limitation): SHAP computed via permutation approximation (10 reps), not exact TreeSHAP. Captures mean marginal contribution but not interaction effects.
- NOTE(limitation): SHAP subsample of 2000 test rows from temporal holdout. May not perfectly represent rare bloom phenotypes.
- NOTE(limitation): Feature classification (LEVEL vs TREND) is rule-based on naming convention. Rolling means classified as LEVEL could be debated.
- NOTE(limitation): Dynamic environmental features (ERA5 wind, CHIRPS precip, SMAP salinity) are all-NA placeholders in this cube. The TREND group's share may change once meteorological trend features are added.
- NOTE(paper): 'associated with', never 'causes'. Importance shows feature contribution to the model's prediction, not causal mechanism.
- NOTE(limitation): HABSOS non-detection != proven absence. Feature importance reflects association with the *labelled* outcome, which may under-represent true bloom events.

## Done-criteria (PLAN.md section 6 A8) — pass/fail

| Criterion | Status |
|---|---|
| SHAP (or equivalent) computed on best RF (H=7 temporal) | PASS |
| ranger permutation + impurity importance | PASS |
| Levels-vs-trends headline finding reported | PASS |
| top_features.csv saved | PASS |
| variable_importance.csv saved | PASS |
| shap_summary.png saved | PASS |
| 'associated with' language enforced | PASS |
| Chlorophyll-proxy check performed | PASS |
| Header + NOTE tags present | PASS |
| Agent log written | PASS |

