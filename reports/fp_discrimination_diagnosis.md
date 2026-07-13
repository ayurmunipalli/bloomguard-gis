# False-positive discrimination diagnostic — RF, H=7 temporal

**Dispatched:** validation A10 (diagnostic) + explain A8 (interpretation/cross-reference)
**Date:** 2026-07-13
**Model:** does NOT change the model. Uses the reconciled scoring from
`reports/scoring_reconciliation.md` — `outputs/models/best_model.rds`'s stored
`prob_rf`/`act`/`test_idx` (H=7 temporal), confirmed bit-exact against `model_results.csv`.
Default operating point: threshold 0.50. n_test=8880, n_pos=1075 (12.11% base rate).

## Scope limitation — H=14 could NOT be produced

**No model or per-row predictions exist for H=14 temporal.** `outputs/models/best_model.rds`
persists exactly one fitted model (H=7 temporal — the "best model" convention in
`07_modeling.R`); the other 14 horizon×split RF fits in that script's loop, including
H=14 temporal, are transient in-memory objects never saved to disk. A repo-wide search
(`find . -name "*.rds" -o -name "*prob*"`) confirms `best_model.rds` is the only such
artifact. Producing the H=14 diagnostic would require fitting a new ranger RF for H=14
temporal — i.e., retraining — which this dispatch explicitly forbids. **This report covers
H=7 temporal only.** If the H=14 comparison is wanted, that requires either relaxing the
no-retrain constraint for a one-off H=14 fit (not done here) or accepting H=7 as
representative of the pattern at short/low-precision horizons.

## Data caveat — heavy missingness on the diagnostic features

Raw (pre-imputation) MODIS values are missing for a large share of the test set (cloud
cover / no valid retrieval that day):

| Feature | NA count | NA % of n_test=8880 |
|---|---|---|
| chlor_a_mean | 6196 | 69.8% |
| nflh_mean | 6644 | 74.8% |
| sst_mean | 4560 | 51.4% |
| dist_to_shore_m | 0 | 0.0% |

The quantile cross-tabs below use **only rows with an observed (non-imputed) value** for
the feature being binned — imputed rows are excluded from that feature's table (not
silently zero-filled or lumped into a bin), so each table's `n` is smaller than 8880 and
varies by feature. This means the finding characterizes false positives *on days with a
clear-sky chlorophyll/fluorescence retrieval*, not the full test set.

## No FAI column exists in this pipeline

Per your instruction not to estimate: **`nflh_mean` (fluorescence) is used as the FAI
proxy because no floating-algae-index (FAI) column exists anywhere in
`model_dataset.parquet`.** Confirmed via direct column-name search — zero matches for
"fai" (case-insensitive) in the entire schema. PLAN.md §8-A specifies FAI as a planned,
*distinct* index from nFLH, but it was never implemented by A4 (sat-features); only
chlor_a, nFLH, Kd_490, and SST were actually pulled from MODIS (per
`data/metadata/data_sources.md`). This is a genuine gap in the feature set, not a
reporting omission on my part.

## Findings — FP rate by feature quartile (observed rows only)

Quartile boundaries are computed on the test-set distribution of each feature
(`type=7` quantiles). "FP rate" = FP / (FP+TN), i.e. the false-positive rate among rows
that were **actually negative** in that bin. "Share of all FP" = this bin's FP count
divided by the total FP count (among observed rows for that feature).

### Chlorophyll-a (`chlor_a_mean`, mg/m³) — n=2684 observed

| Quartile | Range | n | FP | TN | FP rate | Share of all FP |
|---|---|---|---|---|---|---|
| Q1 (lowest) | 0.273–2.951 | 671 | 4 | 618 | **0.64%** | 7.55% |
| Q2 | 2.951–4.587 | 671 | 2 | 611 | **0.33%** | 3.77% |
| Q3 | 4.598–8.119 | 671 | 8 | 553 | **1.43%** | 15.09% |
| Q4 (highest) | 8.125–77.226 | 671 | 39 | 476 | **7.57%** | **73.58%** |

**FP rate rises ~12× from Q1 to Q4, and the top chlorophyll quartile alone accounts for
nearly three-quarters (73.58%) of all false positives** among observed rows.

### nFLH / fluorescence proxy for FAI (`nflh_mean`) — n=2236 observed

| Quartile | Range | n | FP | TN | FP rate | Share of all FP |
|---|---|---|---|---|---|---|
| Q1 (lowest) | −0.187–0.125 | 559 | 2 | 525 | **0.38%** | 4.65% |
| Q2 | 0.125–0.202 | 559 | 3 | 493 | **0.60%** | 6.98% |
| Q3 | 0.202–0.311 | 559 | 16 | 477 | **3.25%** | 37.21% |
| Q4 (highest) | 0.311–1.265 | 559 | 22 | 392 | **5.31%** | **51.16%** |

Same rising pattern, weaker than chlorophyll but still clear: FP rate up ~14× from Q1 to
Q4, top quartile carries just over half of all false positives.

### SST (`sst_mean`, °C) — n=4320 observed

| Quartile | Range | n | FP | TN | FP rate | Share of all FP |
|---|---|---|---|---|---|---|
| Q1 (coldest) | 10.9–22.1 | 1080 | 16 | 919 | 1.71% | 18.18% |
| Q2 | 22.1–25.8 | 1080 | 27 | 963 | 2.72% | 30.68% |
| Q3 | 25.8–30.1 | 1080 | 11 | 899 | 1.21% | 12.50% |
| Q4 (warmest) | 30.1–35.3 | 1080 | 34 | 910 | 3.60% | 38.64% |

**No clean monotonic pattern** — Q3 is actually the lowest FP-rate bin, not the middle of
a trend. SST does not show the same clear discriminative signature as chlorophyll/nFLH.

### Distance to shore (`dist_to_shore_m`) — n=8880 observed (no NAs)

| Quartile | Range | n | FP | TN | FP rate | Share of all FP |
|---|---|---|---|---|---|---|
| Q1 (nearest) | 51–686 m | 2262 | 48 | 1984 | 2.36% | 18.90% |
| Q2 | 695–2023 m | 2215 | 52 | 1838 | 2.75% | 20.47% |
| Q3 | 2056–3540 m | 2202 | 81 | 1836 | 4.23% | 31.89% |
| Q4 (farthest) | 3595–67201 m | 2201 | 73 | 1893 | 3.71% | 28.74% |

**Mild, non-monotonic pattern** (rises Q1→Q3, then dips slightly at Q4) — far weaker than
the chlorophyll/nFLH signal and does not point to a clean "false positives are offshore"
or "false positives are nearshore" story.

## Joint cross-tab — chlorophyll AND nFLH both in top quartile

| Chl-a Q4? | nFLH Q4? | n | FP | TN | FP rate |
|---|---|---|---|---|---|
| No | No | 1344 | 8 | 1214 | 0.65% |
| No | Yes | 333 | 5 | 272 | 1.81% |
| Yes | No | 333 | 13 | 281 | 4.42% |
| **Yes** | **Yes** | 226 | 17 | 120 | **12.41%** |

When both chlorophyll-a and nFLH are simultaneously in the top quartile, the false-positive
rate is **~19× higher** than when neither is (12.41% vs 0.65%).

## Cross-reference to existing SHAP/importance ranking (A8, `top_features.csv`)

⚠️ **Staleness caveat:** `top_features.csv`/`variable_importance.csv` were computed
2026-07-12, on the **pre-ERA5-wind** `best_model.rds` — before the wind features existed.
The physical chl-a/nFLH/SST features themselves are unchanged by the wind addition, so
their relative importance is still informative context, but this ranking does not include
wind features and was not recomputed post-reconciliation (recomputing it would mean
re-running A8's explainability pass, which is out of scope for this diagnostic dispatch).

With that caveat: `chlor_a_rollmean_obs7` ranks #4 and `nflh_rollmean_obs7` ranks #6 of all
features by mean |SHAP| (out of 155). The model already relies heavily on chlorophyll and
fluorescence trend signal to make its HAB=1 calls — consistent with (not proof of) the FP
pattern above: the model appears to be keying on the same generic "elevated phytoplankton
optical signature" for both true blooms and its false alarms, because it has no
species-specific signal to distinguish *K. brevis* from other high-chlorophyll conditions
(e.g., other algal taxa, resuspended sediment plumes, or river-discharge-driven turbidity
episodes that also elevate chl-a/nFLH without being a *K. brevis* bloom).

## Verdict

**False positives are predominantly high-chlorophyll / high-nFLH water, not spread across
the feature space.** Chlorophyll-a shows a strong, ~monotonic, ~12× rise in FP rate from
lowest to highest quartile, concentrating 74% of all false positives in its top quartile.
nFLH shows the same pattern, more weakly (~14× rise, 51% concentration). Jointly, cells in
the top quartile of *both* have a false-positive rate ~19× higher than cells in neither.
SST and distance-to-shore show no comparable concentration — their FP-rate patterns are
weak and non-monotonic.

This is **associated with** a bio-optical species-discrimination gap, not proof of one:
the model (and its input features) cannot distinguish *K. brevis* blooms from other
conditions that also elevate chlorophyll/fluorescence. This is consistent with, but not
confirmed by, the pre-wind SHAP ranking's reliance on chlorophyll/nFLH trend features. The
practical reading: adding species-discriminating bio-optical features (e.g., a proper FAI,
which does not currently exist in this pipeline, or spectral-shape features that
distinguish *K. brevis*'s pigment signature from generic phytoplankton) is the kind of
change indicated by this pattern — **no such feature is implemented here; this diagnostic
does not recommend or select a specific fix, per the "do not implement" instruction.**

## What this diagnostic does NOT establish

- Causality — "associated with," not "causes" (PLAN.md guardrail).
- The H=14 (or any horizon besides H=7) version of this pattern — no data exists to check
  it without retraining.
- Whether a bio-optical fix would actually work — that's a feature-engineering question
  requiring new data (e.g., actual FAI, Rrs band-ratio features) not present in this cube.
- The ~70-75% missingness on chl-a/nFLH means this finding describes false positives *on
  cloud-free days*; false positives on cloudy days (where the model relied on imputed
  medians + missingness flags + other features) are not characterized by this cut.
