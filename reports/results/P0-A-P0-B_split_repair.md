# P0-A + P0-B — temporal embargo & spatial buffer (split-defect repairs)

Measurement-apparatus repairs, not experiments. They fix the two split defects R-SPLIT
conditionally passed (`R/07_modeling.R:51-72`). Orthogonal — embargo touches only the temporal
split, buffer only the spatial split, random split untouched — so they cannot confound each other
and ship together.

## Hypothesis (written before the run)
The pre-embargo baseline is honest *modulo* two known leaks. Closing them will move the temporal
number negligibly (embargo drops ~49 rows at H=14) and drop the spatial number (buffer removes
border adjacency). |Δ| at H=7 temporal PR-AUC should stay well under the 0.02 pivot trigger.

## Change (exactly two, attributable)
- **P0-A temporal embargo** (`R/07c_split_repair.R`, `R/07_modeling.R`): drop every training row
  whose `label_date = date_T + H` falls in the test period (≥ 2016-01-01). Temporal split only.
- **P0-B spatial buffer**: drop every training **cell** within R of any spatial-test cell.
  R = `config.yaml split_repair.spatial_buffer_m`, default 20 000 m (2 cells). Spatial split only.
- Files: `R/07c_split_repair.R` (new; re-freezes the adopted pre-bio baseline under repaired
  splits), `R/07_modeling.R` (permanent apparatus fix), `config.yaml` (buffer param),
  `outputs/tables/model_results.csv` (re-frozen rf/persistence/chl rows; 15 transformer rows
  preserved), `outputs/tables/model_results_p0ab.csv` + `split_repair_validation.csv` (artifacts).

## Feature parity
Every arm uses the **adopted pre-bio** feature set (the 71 bio-optical features excluded, matching
the shipped model — NOT the bio-inclusive run `07_modeling.R` now produces). Control arm confirms
parity: reproduces the frozen baseline exactly.

## Reproduction control (the go/no-go gate)
`R/07c_split_repair.R` runs a CONTROL arm (repair OFF) that **must** reproduce `model_results.csv`.
It does, exactly: random split Δ=0 (all rows), all persistence rows Δ=0, H=7 temporal rf
pr_auc=0.5022 / tp=382 / fp=254 / fn=693 / tn=7551, 0 unexpected rows. Only after this passed were
the repaired numbers trusted.

## Metrics — re-frozen baseline (RF, temporal, post-embargo)
| H | PR-AUC | p@r80 | Recall | Precision | FNR | n_test | n_pos |
|---|---|---|---|---|---|---|---|
| 1 | 0.6437 | 0.5000 | 0.5877 | 0.6362 | 0.4123 | 3,004 | 473 |
| 3 | 0.6544 | 0.4957 | 0.5249 | 0.6835 | 0.4751 | 1,952 | 362 |
| 5 | 0.6724 | 0.4652 | 0.5138 | 0.7264 | 0.4862 | 2,677 | 434 |
| **7** | **0.5008** | **0.2750** | **0.3581** | **0.6073** | **0.6419** | **8,880** | **1,075** |
| 14 | 0.4589 | 0.2295 | 0.2574 | 0.6005 | 0.7426 | 9,021 | 1,010 |

H=7 temporal confusion: **TP=385 · FP=249 · FN=690 · TN=7556.**

## Δ vs pre-embargo baseline
- **H=7 temporal PR-AUC: 0.5022 → 0.5008 (Δ = −0.0014).** Inside ±0.02. **No pivot trigger.**
- Temporal Δ (embargo), all H: +0.0010 / +0.0098 / −0.0002 / −0.0014 / +0.0002 (H=1/3/5/7/14) — all
  negligible, confirming the pre-embargo number was honest.
- Spatial Δ (buffer), all H: −0.0115 / −0.0047 / −0.0213 / −0.0417 / −0.0261. The spatial number
  drops as predicted; post-buffer spatial H=7 (0.617) now sits *below* random (0.631), confirming
  the earlier spatial>random gap was border leakage, not geographic generalisation.
- Random Δ: 0 at every horizon (untouched control).
- **No block-bootstrap CI** on these deltas (P0-C, not yet run). The H=7 temporal Δ is a
  point estimate; treated as UNRESOLVED in the strict §7.2 sense but well inside the pivot band, so
  it does not gate the re-freeze. P0-C should CI it alongside the frozen baseline.

## Drop report
| H | P0-A embargo rows dropped | P0-B cells dropped | P0-B rows dropped | test-within-R before→after |
|---|---|---|---|---|
| 1 | 1 | 17 | 450 | 43.8% → 0% |
| 3 | 3 | 11 | 202 | 39.1% → 0% |
| 5 | 12 | 9 | 343 | 38.1% → 0% |
| 7 | 23 | 9 | 1,959 | 44.4% → 0% |
| 14 | 49 | 8 | 1,944 | 35.3% → 0% |

## Verdict
**NULL at H=7 temporal (apparatus fix, adopted).** The temporal repair moves nothing beyond noise;
the spatial repair correctly removes leakage. Both adopted; baseline re-frozen. This is the intended
outcome of a measurement-apparatus repair — the ruler is now honest without moving the headline.

## Mechanistic check
Did the repairs move the errors they were supposed to? Yes. Embargo removes exactly the
label-straddling training rows (max train label_date < cutoff at every H). Buffer removes exactly
the near-border training cells (residual test-within-R = 0). Persistence rows unchanged (test set
untouched) — the repairs touched only training, as designed.

## Baselines
Persistence temporal PR-AUC unchanged (0.6158 / 0.5827 / 0.5339 / 0.4503 / 0.3196). At matched
recall=0.80, RF still beats persistence at H=7 (p@r80 0.275 vs ~0.215).

## Importance source
N/A — no feature selection involved.

## Gate status
- **R-SPLIT: PASS** — independent verification (`reports/agent_logs/R-SPLIT-review.md`, 2026-07):
  control reproduces baseline; embargo leak closed at every H; buffer ≥ 20 km at every H; test sets
  unchanged; orthogonality holds. No merge block.
- **R6:** N/A (no datacube/feature change).

## Limitations
- The 20 km buffer is below E-01's ring-2 reach (~20 km). **Widen to ≥ 30 km before E-01**
  (`config split_repair.spatial_buffer_m`) or neighbour features re-open the leak.
- The 15 frozen transformer rows were trained on pre-repair training sets (M3, frozen). Their test
  evaluations remain valid (test sets unchanged); their training was not embargoed/buffered.
- No block-bootstrap CI yet (P0-C).

## Pushed
commit SHA — recorded on push.
