# E-01 buffer-cost — 20 km → 30 km spatial buffer (measure-only)

**Measure-only. E-01 was NOT run; nothing retrained.** Recomputed which spatial-split *training*
cells the buffer drops at each radius (same split logic as `R/07c`/`R/07d`), on the frozen
re-frozen splits. Spatial split only. Test sets unchanged (the buffer drops only training cells).

`n_train_pos` = **training** positives after the buffer (what the model would learn from); test
positives are separate and unchanged. (The "H=3: 342 / H=5: 386" in the request are the *pre-buffer*
spatial positive counts; the 20 km column below is already post-buffer, hence slightly lower.)

## Cost table (spatial split)

| H | buffer | n_train | n_train_pos |
|---|---|---|---|
| **1** | 20 km | 4,062 | 446 |
|   | 30 km | 3,423 | 359 |
|   | **delta** | **−639** | **−87  (−19.5%)** |
| **3** | 20 km | 2,335 | 314 |
|   | 30 km | 2,133 | 280 |
|   | **delta** | **−202** | **−34  (−10.8%)** |
| **5** | 20 km | 3,409 | 377 |
|   | 30 km | 2,948 | 317 |
|   | **delta** | **−461** | **−60  (−15.9%)** |
| **7** | 20 km | 15,216 | 1,076 |
|   | 30 km | 12,991 | 889 |
|   | **delta** | **−2,225** | **−187  (−17.4%)** |
| **14** | 20 km | 15,557 | 988 |
|   | 30 km | 13,420 | 810 |
|   | **delta** | **−2,137** | **−178  (−18.0%)** |

## Leakage checks at 30 km (both must pass — they do)
| H | residual % test cells within 30 km of a train cell | min train→test cell distance |
|---|---|---|
| 1 | 0% | 30 km |
| 3 | 0% | 30 km |
| 5 | 0% | 30 km |
| 7 | 0% | 30 km |
| 14 | 0% | 30 km |

Residual = **0% at every horizon** (target met); min train→test distance = **30 km ≥ 30 km** at
every horizon. A 30 km buffer is clean for ring-2 (~20 km) features.

## Recommendation: **(c) — keep the 20 km buffer, build ring-1 (~10 km) features only.**

**Decision threshold used: >15% training-positive loss at any horizon → prefer ring-1.**
The 30 km bump breaches 15% at **4 of 5 horizons** (H=1 −19.5%, H=5 −15.9%, H=7 −17.4%,
H=14 −18.0%; only H=3 is under at −10.8%). With spatial positives already thin, losing ~1 in 5 of
the training positives to gain one extra neighbour ring is a poor trade.

Why (c) over the alternatives:
- **(a) 30 km + full ring-2** — costs 16–20% of training positives at four horizons. Rejected by the
  threshold; the marginal spatial reach of ring-2 does not justify the loss on this thin, single
  fixed-geography holdout (n=1, no rotation — §2.1).
- **(b) 30 km + ring-1** — over-buffers: ring-1 reaches ~10 km, which is clean at a 20 km buffer
  (buffer ≥ ring radius + 1 cell = 10 + 10 = 20 km). Paying the 30 km positive cost for ring-1
  features buys no extra reach — strictly dominated by (c).
- **(c) 20 km + ring-1** — **no additional positive cost** (the 20 km buffer is already in place and
  gate-passed, residual 0 at ring-1 reach), keeps the clean evaluation, and still captures
  first-order spatial coherence (queen-neighbourhood, the largest single spatial signal). Caps
  spatial reach at one ring — an acceptable, honest limitation given the positive scarcity.

If ring-1 (E-01a isotropic) comes back NULL, that itself is a finding (spatial structure isn't the
bottleneck at these horizons); ring-2 can be revisited only if ring-1 shows a real gain worth the
positive cost.

## Config / next action (STOP — author decision)
`config.yaml split_repair.spatial_buffer_m` **left unchanged at 20000** — I did not bump it, since
the recommendation keeps 20 km and the choice is yours. If you choose (a)/(b), set it to 30000 and
re-run A7 (R/07c re-freeze) under it before E-01. **STOP: awaiting your decision (a/b/c).**
