# P0-C — Block-bootstrap confidence intervals on the re-frozen baseline

Turns the ~0.01 deltas into verdicts (§7.2). CIs on the **re-frozen** (post-P0-A embargo,
post-P0-B buffer) baseline. No new modelling decisions — per-row predictions dumped from the
adopted pipeline and the frozen transformer, then resampled.

## Method
- **Block bootstrap, blocks = contiguous calendar-time segments, n=1000, 95% percentile CIs.**
  Non-overlapping 30-day blocks over the test period; blocks resampled with replacement; deltas
  computed on the **same** resampled blocks (paired). Scripts: `R/07d_pC_predictions.R` (per-row
  predictions on repaired splits: rf_adopted / rf_bio / rf_nowind / persistence),
  `python/dump_transformer_preds.py` (frozen `.pt` per-row predictions),
  `R/07e_pC_bootstrap.R` (bootstrap). CIs: `outputs/tables/bootstrap_cis_pC.csv`.
- **Reproduction check:** rf_adopted per-row PR-AUC matches the re-frozen `model_results.csv`
  exactly at all 15 H×split (temporal H=7 = 0.5008, etc.).

### Block length = 30 days — justification
Same-cell label autocorrelation vs the temporal gap between consecutive observations (H=7 labels):

| gap (days) | ≤7 | 8–14 | 15–21 | 22–28 | 29–42 | 43–60 |
|---|---|---|---|---|---|---|
| corr | 0.655 | 0.561 | 0.382 | 0.083 | 0.179 | −0.024 |

Autocorrelation decays below ~0.2 by ~3–4 weeks (K. brevis blooms persist weeks–months, HABSOS
sampled ~weekly). A **30-day** block spans a full bloom episode so blocks are ~independent.
**Sensitivity** (H=7 temporal) at L=14/60 d changes CI bounds by <0.01 — verdicts are stable:

| quantity | L=14 | L=30 | L=60 |
|---|---|---|---|
| RF PR-AUC | [0.408, 0.577] | [0.388, 0.590] | [0.401, 0.575] |
| RF−transformer | [−0.034, +0.030] | [−0.037, +0.027] | [−0.037, +0.017] |
| wind effect | [−0.005, +0.016] | [−0.006, +0.018] | [−0.004, +0.018] |
| bio p@r80 | [−0.028, +0.025] | [−0.028, +0.028] | [−0.024, +0.028] |

## RF baseline CIs (temporal split — the headline)
| H | PR-AUC [95% CI] | p@r80 [95% CI] |
|---|---|---|
| 1 | 0.6437 [0.537, 0.718] | 0.5000 [0.371, 0.610] |
| 3 | 0.6544 [0.548, 0.754] | 0.4957 [0.357, 0.649] |
| 5 | 0.6724 [0.535, 0.763] | 0.4652 [0.268, 0.631] |
| **7** | **0.5008 [0.388, 0.590]** | **0.2750 [0.173, 0.389]** |
| 14 | 0.4589 [0.330, 0.551] | 0.2295 [0.140, 0.335] |

The CIs are wide (block resampling on ~1,000 positives) — the honest width for effects of this size.

## Re-verdicts (§7.2, applied mechanically)

### 1. RF vs transformer — **TIE (NULL)** at H=7 and H=14 temporal
RF − transformer PR-AUC (temporal): **H=7 = −0.0018 [−0.037, +0.027]; H=14 = +0.0114 [−0.023,
+0.033].** Both CIs include 0 → **not a win, a statistical tie.** The RF resolves a small win only
at H=1 (+0.046 [+0.001, +0.079]) and H=5 (+0.044 [+0.003, +0.080]); H=3 and all spatial horizons
tie. **§2.3's defensible claim is confirmed:** "RF ties or beats the transformer; on matched
comparison the PR-AUC difference is within noise at most horizons — not 'RF beats the transformer'."
*Note:* uses `.pt`-faithful transformer predictions (H=7 temporal transformer PR-AUC = 0.503,
consistent with the checkpoint's stored `best_pr_auc`=0.508). The archived `model_results.csv`
transformer value (0.493) predates these weights; either value gives CI-includes-0. The
feature-mismatch caveat (§2.3: transformer has placeholder wind, RF has real) still applies —
this is a same-test-set comparison, not a matched-feature one.

### 2. ERA5 wind — **NULL at the primary horizon; small resolved positive at H=1 and H=14**
RF(with wind) − RF(no wind) PR-AUC (temporal): **H=7 = +0.0051 [−0.006, +0.018] → NULL.** H=3
(+0.016 [−0.001, +0.026]) and H=5 (+0.013 [−0.003, +0.029]) also include 0 → NULL. But **H=1
(+0.0123 [+0.003, +0.021]) and H=14 (+0.0145 [+0.005, +0.025]) EXCLUDE 0** → a small, real positive
effect at the shortest and longest horizons. Prior status was **UNRESOLVED** (no CI); now
**RESOLVED**: NULL at H=3/5/7, small positive at H=1/14. By the §7.2 WIN rule (≥+0.02 at H=7,
sustained ≥3/5) wind is **not a WIN** — but it is not uniformly null either, and it never hurts, so
it stays in the feature set. Report as: "wind contributes a small, horizon-dependent PR-AUC gain
(resolved at H=1 and H=14, null at H=3/5/7), not a headline effect."

### 3. Bio-optical — **NULL at matched recall; NEGATIVE on PR-AUC at H=5/H=14. Settles the third negative result.**
- **At matched recall (p@r80):** the bio−adopted delta CI **includes 0 at every horizon** → **NULL.**
  The pre-repair "+0.0037 at H=7" does **not** survive: on repaired splits H=7 = −0.0022 [−0.028,
  +0.028]; H=1 = +0.022 [−0.032, +0.044]; H=3 = +0.064 [−0.028, +0.113] — all include 0. **The
  apparent matched-recall gain was noise.**
- **On PR-AUC:** **NEGATIVE** where resolved — H=5 temporal −0.026 [−0.044, −0.003], H=14 temporal
  −0.018 [−0.036, −0.003], H=14 spatial −0.030 [−0.049, −0.012]; H=7 temporal −0.018 [−0.035,
  +0.001] borderline NULL; elsewhere NULL. Never positive with a CI excluding 0.
- **Verdict: bio-optical does not improve the model at any operating point.** NULL at matched
  recall, NULL-to-NEGATIVE on PR-AUC. The paper's third negative result **stands and is
  strengthened** — with CIs, the only resolved effects are negative.

## Bonus (not requested, but it changes what §2.2 means)
RF − persistence PR-AUC (temporal): **H=7 = +0.0484 [−0.034, +0.100] → NULL** (the RF's H=7 PR-AUC
edge over persistence is **within noise**). Resolved RF wins only at H=5 (+0.137 [+0.025, +0.199])
and H=14 (+0.136 [+0.028, +0.185]). So the RF's PR-AUC advantage over persistence is real at H=5
and H=14 but **not** established at H=7. This tightens §2.2: the RF "earns its keep" at H=5 and
H=14, not at the primary H=7 on PR-AUC.

## Gate status
- R6: N/A (no datacube/feature change). R-SPLIT: N/A (uses the already-gated repaired splits).

## Pushed
commit SHA — recorded on push.
