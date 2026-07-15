# E-06 (Stage 1) — ordinal severity reframe

Authorized target change (re-opens evaluation). 5-class FWC severity target; binary derived as
(class≥3), validated 100% (STOP #1, `E-06_stop1_distribution.md`). Adopted feature set (no bio, no
E-01a neighbours); repaired splits (embargo + 20 km buffer); same seed/hyperparameters as the frozen
baseline. Two models trained per the plan: **ordered forest** (4 cumulative ranger prob. forests,
respects ordering — the ordinal metrics come from it) and, added for a meaningful binary verdict,
**multiclass ranger** (5-class; binary = P(3)+P(4)).

## Hypothesis (before the run)
A denser gradient (classes 1–2 add 8.6–16.5% of previously-HAB=0 rows) lifts the **binary** forecast
at H=7 temporal (≥+0.02 PR-AUC, CI excludes 0), and yields a usable severity model (QWK, category
accuracy comparable to Medina 2024).

## Methodological note carried from the plan (not hidden)
The ordered forest's binary derivation P(class≥3) is the **k=3 cumulative forest**, which trains on
exactly `(sev≥3)==HAB_H` with the adopted features/weights — i.e. it **is the binary baseline
re-fit**, so its binary Δ is ≈0 *by construction*. To actually test whether the denser target helps
the binary boundary, the multiclass derivation (P3+P4, where intermediate classes can shift the
class-3 split) was added. **Limitation:** multiclass does not exploit class ordering (QWK still
scores its ordering); and it optimizes a 5-class-balanced objective, not the binary threshold.

## PRIMARY VERDICT — binary PR-AUC Δ vs frozen baseline (30-day block bootstrap, n=1000), temporal
| H | ordered P≥3: Δ [95% CI] | multiclass P3+P4: Δ [95% CI] |
|---|---|---|
| 1 | −0.0025 [−0.013, +0.006] · null | −0.0330 [−0.058, −0.012] · **neg** |
| 3 | +0.0022 [−0.006, +0.009] · null | −0.0333 [−0.049, −0.014] · **neg** |
| 5 | −0.0023 [−0.009, +0.006] · null | −0.0503 [−0.076, −0.023] · **neg** |
| **7** | **−0.0006 [−0.005, +0.003] · null** | **−0.0197 [−0.036, −0.002] · neg** |
| 14 | +0.0041 [−0.001, +0.009] · null | −0.0278 [−0.049, −0.006] · **neg** |

**Verdict: the ordinal reframe did NOT improve the binary forecast.**
- **Ordered forest → NULL** at every horizon (CI includes 0). Confirms the structural point: respecting
  the class-3 threshold reproduces the binary model — no free binary gain from the ordinal target.
- **Multiclass → NEGATIVE** at every horizon (CI excludes 0, Δ<0; H=7 −0.0197 [−0.036, −0.002]).
  Thresholding back from a 5-class-balanced model **costs** binary skill — capacity spent separating
  intermediate classes dilutes the class-3 boundary.
- **This is the fourth problem-bounding negative (bio-optical, wind, and E-06's two binary
  derivations), bounding the problem at label density:** even a denser target does not lift the
  binary daily-exceedance forecast at H=7. *(Corrected from "fifth": the earlier count included the
  E-01a spatial-lag null, which was an artifact of reading the wrong source table; corrected E-01a′
  shows a real sub-threshold advection signal and is not a problem-bounding negative.)* `p@r80` tells the same story (ordered
  ≈0, multiclass negative).

**No leakage SUSPECT.** No positive Δ anywhere exceeds +0.05 (none even excludes 0 positively). The
|Δ|>0.05 flag fired only on H=5 multiclass (−0.050) — a real *loss*, not a leakage *gain*; §7.2's
SUSPECT rule is for suspicious positive jumps, so no STOP-for-review is warranted.

## Ordinal metrics (ordered forest — the model that respects ordering), temporal
| H | QWK (ord) | QWK (mc) | ordinal-PR P≥1 / ≥2 / ≥3 / ≥4 |
|---|---|---|---|
| 1 | 0.662 | 0.616 | — / — / 0.641 / 0.375 |
| 3 | 0.658 | 0.597 | 0.768 / 0.736 / 0.657 / 0.357 |
| 5 | 0.645 | 0.628 | 0.739 / 0.720 / 0.670 / 0.428 |
| **7** | **0.517** | 0.541 | 0.663 / 0.600 / 0.500 / 0.282 |
| 14 | 0.418 | 0.477 | 0.609 / 0.553 / 0.463 / 0.223 |

QWK is moderate-to-substantial and decays with horizon (as expected) — the model **does** rank
severity, a capability the binary PR-AUC does not measure. Ordering helps QWK at short horizons
(ordered > mc at H≤5); at long horizons the noisy multiclass edges it.

## Per-class recall / precision (ordered forest), temporal — the mechanism for the null
Recall by class (0/1/2/3/4): H=7 = 0.971 / **0.000** / 0.040 / 0.364 / 0.203; H=14 = 0.975 / 0.000 /
0.042 / 0.230 / 0.154. **The middle classes (1 "very low", 2 "low") are essentially unlearnable** —
the model absorbs them into background or medium. Only background (class 0) and the old-positive
region (3/4) carry signal. **This is why the reframe cannot help the binary:** the extra gradient is
in exactly the classes the features cannot separate at these horizons.
**Thin-class-4 caveat (carried loudly):** class 4 has 94–262 training positives (thinnest at short-
horizon spatial); its recall (0.15–0.38) and precision (0.38–0.49) have wide CIs — read as
indicative, not precise.

## Bar B — H=7 weekly-max category accuracy (5 FWC classes)
Ordered forest: temporal **0.758**, spatial 0.815, random 0.823. Multiclass: temporal 0.730.
**Comparable target, different splits/region** — Medina et al. 2024 report **73%** at 1-week on
weekly-max abundance categories. Our honest-temporal H=7 (0.758) sits in the same neighbourhood, but
this is **not** "we beat Medina": different class definitions, different holdout protocol, different
region, and category accuracy is inflated by the dominant background class (0). Reported for
comparability only. **We have no true 4-week arm — H=14 is NOT Medina's 4-week horizon.**

## Verdict (§7.2): **NULL (ordered) / NEGATIVE (multiclass) on the binary — the reframe does not improve the binary forecast.**
A clean fourth problem-bounding negative that bounds the problem at label density (see the STOP #2
note above on the corrected count). **But** E-06 is not a dead end: it
produces a calibrated severity model with real ordinal skill (QWK ~0.52 at H=7) and category accuracy
near the published SOTA target — a Path-B (severity forecasting) deliverable the binary track never
had. The middle-class collapse locates the ceiling: severity resolution here is effectively
background / bloom-present, not a clean 5-level scale.

## Mechanistic check
Did the target move what it should? No net binary gain, and the *reason* is diagnosed, not asserted:
per-class recall shows the intermediate gradient is unlearnable, so the denser target adds
capacity-splitting cost (multiclass NEGATIVE) without a separable middle signal, and the threshold
mechanism (ordered) just reproduces the binary. Consistent, honest null.

## Gate status
R6: N/A (no datacube/feature change; target derived from existing max_count). R-SPLIT: uses the
already-gated repaired splits; binary target byte-validated == HAB_H.

## STOP #2 — reporting before any further modeling
Next moves are **author decisions, not automatic:** (1) GBDT (CatBoost/LightGBM) on the ordinal
target with a custom/ordinal objective that optimizes the class-3 boundary while using finer labels
as auxiliary — the one path that could turn the multiclass NEGATIVE into a binary gain; (2) lower the
positive threshold to 50k (would repopulate class 2/3 boundary); (3) weak-label / sampling-density
pretraining. Halting here.

## Pushed
commit SHA — recorded on push.
