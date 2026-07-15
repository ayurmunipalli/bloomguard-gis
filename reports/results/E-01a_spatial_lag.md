# E-01a — ring-1 spatial-lag features

## Hypothesis (written before the run)
The per-cell design discards spatial coherence. At H=7/14 a cell's risk depends on what is
advecting *toward* it, so queen-neighbourhood (ring-1) features observed at T should raise PR-AUC —
**concentrated at H=7/14 (advection needs time), absent at H=1** (no time to drift). Expected
signature: a gain that grows with horizon.

## Change (exactly one)
Added a ring-1 (queen-adjacency, centroid dist < 15 km → 10 km orthogonal + 14.14 km diagonal;
ring-2 at 20 km excluded) neighbour-feature block to the **adopted** feature set. **69 new features:**
`nbr_mean` + `nbr_max` of the 4 levels (chl, nFLH, Kd490, SST) at T, `nbr_mean` of all 60 existing
trend features (Δ, %chg, rolling slope/mean/std) at T, and `nbr_count` (valid-neighbour count).
Files: `R/e01a_spatial_lag.R` (build+train), `R/e01a_bootstrap.R` (scoring). Option (c): current
**20 km buffer, ring-1 only — no buffer change, no A7 re-freeze.** Nothing else changed (same seed,
splits, hyperparameters as the re-frozen baseline).

**Edge/coastline cells:** a cell with < 8 neighbours uses the available ones (`na.rm`) plus
`nbr_count`; missing neighbours are **NA → imputed-with-flag, never zero-filled** (the D4 bug class).

## Feature parity
Baseline = adopted RF (`rf_adopted`, post-embargo+buffer). E-01a = baseline features **+** the 69
ring-1 features, same test rows (paired). The only difference is the neighbour block.

## Data reality (matters for the verdict)
The neighbour signal is **sparse**: only **77.3%** of modeling rows have ≥1 valid neighbour, and the
**median `nbr_count` is 2** (of a possible 8). HABSOS sampling is sparse in space-time, so at a
given date T a focal cell's neighbours are usually *unobserved at T* — the "what is advecting toward
me" signal is mostly missing exactly where the hypothesis needs it.

## Metrics — ΔPR-AUC vs re-frozen baseline (30-day block bootstrap, n=1000, 95% CI)
**Temporal (headline):**
| H | baseline | E-01a | Δ PR-AUC [95% CI] | CI excl. 0? |
|---|---|---|---|---|
| 1 | 0.6437 | 0.6360 | −0.0076 [−0.019, +0.005] | no |
| 3 | 0.6544 | 0.6342 | −0.0202 [−0.038, +0.009] | no |
| 5 | 0.6724 | 0.6628 | −0.0096 [−0.031, +0.008] | no |
| **7** | **0.5008** | **0.4969** | **−0.0039 [−0.017, +0.009]** | **no** |
| 14 | 0.4589 | 0.4601 | +0.0012 [−0.019, +0.018] | no |

**Every temporal-horizon CI includes 0.** Random split: H=3 −0.050 [−0.081, −0.018] (NEGATIVE —
feature dilution), others null. Spatial split: H=7 +0.0263 [+0.005, +0.049] resolved positive,
others null — but the spatial split is the confounded, single-fixed-geography holdout (§2.1), and
the honest temporal H=7 is null, so this is a curiosity, not a result (see Mechanistic check).

## Verdict: **NULL**
Δ at H=7 temporal = −0.0039, CI includes 0 → fails the §7.2 WIN rule (needs ≥+0.02, CI excludes 0,
sustained ≥3/5). No temporal horizon shows a resolved gain. Ring-1 spatial-lag features do not
improve the honest forecaster. **A clean NULL is the finding — do not tune it.**

## Mechanistic check (did it move what it should?)
**No — and that is what makes the null trustworthy.** The hypothesis predicts a gain that *grows*
with horizon (advection). Observed temporal Δ by horizon: −0.008 / −0.020 / −0.010 / −0.004 / +0.001
(H=1/3/5/7/14) — flat-to-negative, **no advection signature**. The lone resolved positive is spatial
H=7 (+0.026), but (a) it is on the prevalence-confounded spatial split, (b) it does not appear on
the honest temporal split, and (c) it does not sustain across horizons — so it is not evidence of
advective skill. The likely mechanism for the null: neighbours are unobserved at T for ~1 in 5 rows
entirely and median 2/8 elsewhere, so same-date neighbour aggregation cannot carry the advection
signal. (This also means a denser label/sampling regime, not more neighbour engineering, is what a
spatial approach would need — consistent with the deferred supervision fix.)

## SUSPECT / leakage check
- **Not SUSPECT.** Max |Δ| = 0.050 (random H=3, negative); spatial H=7 +0.026 < the +0.05 threshold.
- **R6 (T-only) — PASS.** Every neighbour feature is aggregated from neighbour rows at the *same*
  `date_T` as the focal row (join on cell only; grouped within a single date). No T+H reach.
- **R-SPLIT (buffer separates ring-1) — PASS.** Independent check: at every horizon, **0** kept train
  cells have a test cell within the 15 km ring-1 cutoff; min train→test cell distance = 20 km > 15 km.
  The 20 km buffer fully separates train/test for ring-1 reach (14.14 km). Test sets unchanged.

## Baselines
No improvement over the baseline, so the P0-C picture is unchanged: RF still ties persistence on
PR-AUC at H=7 temporal and the transformer remains a tie. E-01a adds nothing to beat.

## Ring-2
**Not built, and not to be revisited** — the instruction is ring-2 only if ring-1 shows real signal;
it does not. E-01b (upstream-weighted) is likewise not pursued on this basis.

## Gate status
R6: PASS · R-SPLIT: PASS.

## Pushed
commit SHA — recorded on push.
