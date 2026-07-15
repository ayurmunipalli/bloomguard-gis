# E-01a (corrected) — ring-1 spatial-lag features, full-grid source

**Supersedes the voided E-01a.** The original `R/e01a_spatial_lag.R` built neighbour features by
self-joining `model_dataset.parquet` — the label-conditioned table (1,461 HABSOS-sampled cells,
0.24% of the satellite grid). That starved neighbour coverage (median 2/8) and produced an
**artifact null** whose stated mechanism ("neighbours unobserved because HABSOS sampling is sparse")
described the bug and wrongly concluded spatial structure is unrecoverable. **That verdict is void.**

## Fix
- Neighbour features now come from the **full-grid** `satellite_features.parquet` (4,742 cells ×
  5,829 dates, every cell every day), joined on (neighbour cell_id, date_T). Adjacency is built over
  **all 4,743 grid cells** (a modeling cell's neighbours include cells never HABSOS-sampled).
- **Cloud-robust neighbour levels:** MODIS clear-sky retrieval is only ~26% of cell-days (74% NA);
  the focal features are also ~67% NA (median-imputed at fit — the pipeline does NOT LOCF). Exact-date
  neighbours would be cloud-starved (median 0 clear). So neighbour levels use a **trailing 8-day
  clear mean** per cell (`frollsum(clear)/frollsum(value)`, ≤ T, no look-ahead) + its week-over-week
  change. `R/e01a_spatial_lag_v2.R`.
- 13 neighbour features: nbr_mean+nbr_max of the trailing-clear chl/nFLH/Kd490/SST; nbr_mean of their
  week-over-week change; nbr_count. Edge/cloud: available neighbours + count, no zero-fill.

## Corrected coverage (the answer to "is nbr_count still low, and why")
| metric | value |
|---|---|
| mean geometric neighbours / focal cell | 7.96 (adjacency correct; full grid) |
| exact-date clear neighbours (raw cloud) | **median 0**, 47.5% of rows ≥1 — the true cloud story |
| trailing-8d-clear neighbours (what the model uses) | **median 6 of 8, 97.3% of rows ≥1** |

The residual sparsity is **MODIS cloud masking** (74% of cell-days NA), quantified — **not**
label-conditioning (fixed). vs the buggy run's 77.3% / median 2 from the wrong source.

## Attribution control (row-order rigor)
The neighbour `merge()` reorders `dt`, and ranger's bootstrap is row-order-sensitive at fixed seed —
so Δ vs the pC baseline could carry a row-order artifact. Fixed by training an **adopted-only arm on
the same reordered `dt`** and taking Δ between the two arms. Control check: adopted_v2 drifts only
−0.0009 / −0.0056 / +0.0010 / −0.0009 / +0.0005 from the frozen baseline (H=1/3/5/7/14) — the reorder
effect is negligible, and the reported Δ cleanly isolates the ring-1 features.

## Metrics — ΔPR-AUC (adopted+ring1 − adopted-only, same dt; 30-day block bootstrap n=1000)
| H | temporal Δ [95% CI] | random Δ [95% CI] | spatial Δ [95% CI] |
|---|---|---|---|
| 1 | +0.0092 [−0.013, +0.028] | +0.0121 [−0.001, +0.027] | −0.0035 [−0.032, +0.023] |
| 3 | −0.0012 [−0.012, +0.013] | +0.0193 [−0.004, +0.044] | −0.0010 [−0.034, +0.030] |
| 5 | −0.0021 [−0.017, +0.013] | +0.0071 [−0.013, +0.026] | −0.0032 [−0.029, +0.025] |
| **7** | **+0.0103 [−0.001, +0.020]** | **+0.0160 [+0.004, +0.031]** | +0.0098 [−0.011, +0.033] |
| 14 | +0.0063 [−0.007, +0.018] | **+0.0164 [+0.002, +0.033]** | −0.0002 [−0.023, +0.019] |

## Verdict: **NULL** on the honest temporal split — but a *real* sub-threshold advection signal, not an artifact
- **Temporal:** every CI includes 0 → NULL by §7.2. H=7 is a near-miss (+0.0103, CI lower bound
  −0.0007). Fails the WIN rule (needs ≥+0.02 at H=7, CI excludes 0).
- **Random (better-powered):** H=7 (+0.016) and H=14 (+0.016) **exclude 0** — the ring-1 features
  carry genuine, resolved signal, concentrated at the advection horizons.
- No SUSPECT (max |Δ| = 0.019 < 0.05).

**The correction changes the conclusion's character, not the WIN/NULL call:** spatial structure is
**weakly recoverable** — ring-1 neighbours give a small (~+0.01 at H=7), advection-consistent,
mechanistically-right gain that is significant on the optimistic split and just under the noise floor
on the honest one. The buggy "spatial structure is unrecoverable" claim is **retracted**.

## Mechanistic check (did it help where blooms advect?)
Yes, and cleanly on the powered split. On **random** (more test rows, tighter CIs), the only resolved
gains are at **H=7 and H=14** (+0.016 each); H=1 is **not** significant (+0.012 [−0.001, +0.027]) —
matching the predicted signature (advection needs time; no gain at H=1). On temporal the same lean
appears (H=7 +0.010, H=14 +0.006) but under-powered. The H=1 temporal +0.009 point estimate is not
significant and does not reproduce as significant on random, so the "uniform gain incl. H=1"
suspicion is not borne out.

## Gate status
- **R6 (T-only): PASS.** Neighbour features use a trailing window ending at T (≤ T); no T+H reach.
- **R-SPLIT: PASS (direct check), with a conservative-rule note.** 0 test modeling cells lie within
  the 15 km ring-1 cutoff of any train modeling cell at the 20 km buffer (direct leakage check, as
  for the original). Conservative "buffer ≥ reach + 1 cell": ring-1 diagonal reach is 14.14 km, so a
  train cell's neighbour footprint (via non-modeling grid cells) can approach within ~5.9 km of a
  test cell — a partial narrowing of the effective buffer. Since the result is **NULL**, no leakage
  inflated it; if E-01b or a WIN emerges, widen to ≥ 25 km before trusting it.

## Consequence for E-01b
Ring-1 now shows a **real (if sub-threshold) advection-consistent signal**, so E-01b (upstream-
weighted ring-1, the cheap Liu-2023 borrow) is **arguable** — it targets exactly the advection
mechanism the corrected E-01a hints at. Author decision, not auto-run.

## AUDIT — same class of error elsewhere?
Checked every feature-construction script for a SATELLITE/ENVIRONMENTAL variable read from the
label-conditioned `model_dataset.parquet` instead of its full-grid source.
- **R/04 (satellite), R/04b (bio-optical), R/05 (environmental):** build **focal** (per-cell)
  features from full-grid / full-time-series sources. Correct.
- **R/06 (datacube):** filters satellite to the 1,461 label cells **by cell membership but keeps
  every date** ("does NOT remove dates — each retained cell keeps its full 5,829-date time series",
  R/06:164-166), so focal trends (delta/slope/rollmean) use each cell's complete daily record.
  Correct — the focal cell is always a label cell, and its own series is intact.
- **E-01a (original):** the **only** spatially-aggregated feature script, and the **only** one that
  read a satellite variable from `model_dataset` and aggregated across cells — hence the only one
  where label-conditioning corrupts the feature. Fixed here.
- No other neighbour/aggregate/spatial-lag feature construction exists in R/ or python/.

**Conclusion: exactly one script was affected (E-01a). All focal feature pipelines are correct.**
The risk was specifically in derived/aggregated features added after the datacube — confirmed and
contained.

## Pushed
commit SHA — recorded on push.
