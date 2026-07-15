# E-07 — cloud-robust temporal compositing of the focal satellite features

## Hypothesis (author's, strong prior)
The focal satellite features (chl/nFLH/Kd490/SST + their trends) are ~67% NA (cloud) and
median-imputed at fit — constants on 2/3 of rows. Recovering the real values via trailing
clear-sky compositing should move metrics materially; this is "almost certainly the project's real
ceiling."

## Change (exactly one, cleanly attributed)
Replace median-imputation of the 4 satellite levels + their 60 trend features with a **trailing
composite**: most recent clear-sky retrieval within a **W=8-day** window ending at T (LOCF, ≤ T),
+ a `days_since_clear_<var>` age feature per variable, + all trends recomputed on the composited
series (R/06 `add_trend_features` verbatim). `_is_missing` flag kept for rows still unfilled.
`R/e07_cloud_composite.R`. Two arms trained on the **same dt** (raw-control vs composite) so Δ
isolates the compositing; control drifts only −0.001 / −0.006 / +0.001 / −0.001 / +0.001 from the
frozen baseline (H=1/3/5/7/14) — clean.

## Window choice (frozen on training only)
Coverage/staleness on temporal-training rows (year<2016): W=3 fills 52–80% (median age 1 d), **W=8
fills 81–97% (median age 2–3 d)**, W=14 fills 90–99% (age up to 14 d). **W=8 chosen** — recovers the
bulk of coverage at low staleness (a ≤3-day-old value is still highly autocorrelated; label
autocorrelation ~0.6 at ≤7 d), where W=14 adds only +5–9% at double the worst-case staleness. The
age feature lets the tree discount stale fills. Frozen before scoring.

## Coverage recovered (modeling rows)
| var | raw NA | composited NA | % real / composited / still-imputed |
|---|---|---|---|
| chlor_a | 66.7% | **14.9%** | 33.3 / 51.9 / 14.9 |
| nFLH | 72.1% | **19.6%** | 27.9 / 52.5 / 19.6 |
| Kd490 | 67.0% | **15.2%** | 33.0 / 51.8 / 15.2 |
| SST | 46.6% | **3.7%** | 53.4 / 42.9 / 3.7 |

**~52% of rows moved from a constant median-fill to a real recent-clear retrieval.** The fix works
as designed.

## Metrics — ΔPR-AUC composite − raw-control (30-day block bootstrap, n=1000)
| H | temporal Δ [95% CI] | random Δ [95% CI] | spatial Δ [95% CI] |
|---|---|---|---|
| 1 | −0.0079 [−0.032, +0.020] | +0.0192 [−0.008, +0.052] | +0.0200 [−0.008, +0.050] |
| 3 | −0.0117 [−0.035, +0.012] | −0.0001 [−0.038, +0.033] | +0.0095 [−0.027, +0.040] |
| 5 | −0.0095 [−0.037, +0.030] | +0.0092 [−0.028, +0.048] | +0.0088 [−0.022, +0.040] |
| **7** | **+0.0073 [−0.007, +0.021]** | **−0.0238 [−0.045, −0.005]** | +0.0114 [−0.007, +0.032] |
| 14 | +0.0051 [−0.012, +0.022] | −0.0103 [−0.029, +0.009] | −0.0161 [−0.037, +0.005] |

`p@r80` deltas are similarly ~0 / mixed-negative (temporal H=7 −0.011).

## Verdict: **NULL** — feature imputation is NOT the ceiling
Every temporal ΔPR-AUC CI includes 0 → NULL by §7.2 (H=7 +0.0073, fails the ≥+0.02 WIN rule). The
only resolved effect anywhere is **negative** (random H=7 −0.024). **Recovering 52% of the satellite
features from constant to real does not improve the honest forecast.**

**Why (mechanism, not excuse):** the raw arm already imputes with training-median **plus an
`_is_missing` flag**, so the tree was never blind — it branches on "clear vs cloudy" and falls back
to the median (≈ the seasonal expectation it also has via `month`/`doy`) when cloudy. The marginal
information in a 2–3-day-old real chl value, over "seasonal median + it-is-cloudy + HAB-history
lags," is small for forecasting a bloom H days ahead. The slight short-horizon negatives (H=1/3/5
temporal, −0.008 to −0.012) suggest the composited *trends* (deltas on an LOCF-filled series carry
stale-carry artifacts) add mild noise where the freshest value matters most.

## SUSPECT gate — not triggered, but gate evidence recorded
No Δ exceeds +0.05 (max temporal +0.0073; max anywhere +0.020). Gates checked regardless:
- **R6 (no look-ahead): PASS.** Every composited value's retrieval_date ≤ T by construction
  (`days_since_clear ≥ 0` for all rows; asserted). The window is strictly trailing.
- **R-SPLIT (embargo not crossed): PASS.** No temporal-training row's feature date reaches the test
  period — the window is backward-only and the newest training feature date < 2016-01-01 cutoff.

## Consequence — the four provisional negatives
The author flagged that wind / bio-optical / ordinal / spatial were all measured on 33%-real
features, so their verdicts were provisional. **That concern is substantially reduced, not confirmed:**
the RF's skill is **insensitive** to whether the satellite features are median-imputed or composited
(NULL either way), so feature degradation was not limiting the RF — the negatives are unlikely to be
artifacts of imputation. **Not formally re-tested** (author said report first; not re-running). The
weight of evidence now points at label density / intrinsic predictability as the ceiling, not
feature quality.

## Possible follow-up (author decision, not run)
Levels-only composite (keep raw obs-indexed trends) to test whether the composited-trend noise is
masking a small levels benefit at short horizons. Cheap, one re-run. Only if you want to chase the
short-horizon negatives.

## Gate status
R6: PASS · R-SPLIT: PASS.

## Pushed
commit SHA — recorded on push.
