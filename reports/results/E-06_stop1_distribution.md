# E-06 STOP #1 — ordinal severity class distribution (before training)

**No model trained.** This is the pre-training gate. Built the 5-class FWC ordinal severity label
at each horizon from raw HABSOS `max_count` at T+H (the same shift-join `R/06` used for `HAB_H`),
validated the binary derivation, and report the class distribution per split per horizon.
Script: `R/e06_stop1_distribution.R`; data: `outputs/tables/e06_class_distribution.csv`.

## Ordinal target (FWC categories) — binary is derived, not replaced
| class | max_count (cells/L) | meaning |
|---|---|---|
| 0 | ≤ 1,000 | not present / background |
| 1 | (1,000, 10,000] | very low |
| 2 | (10,000, 100,000] | low |
| 3 | (100,000, 1e6] | medium ← old binary positive starts here |
| 4 | > 1e6 | high |

Binary = **(class ≥ 3)**, using strict `>` at 100k to match `R/03:143` (`HAB = max_count > 100000`).
Raw `max_count` is **carried through** (already present in `habsos_labels.parquet`); the binary
`HAB_H` is untouched and re-derivable, so every prior result stays reproducible and comparable.

## Validation — the derived binary reproduces HAB_H exactly
| H | (class≥3) == HAB_H ? | n labelled | sev NA where label present |
|---|---|---|---|
| 1 | ✅ TRUE | 7,791 | 0 |
| 3 | ✅ TRUE | 4,765 | 0 |
| 5 | ✅ TRUE | 6,151 | 0 |
| 7 | ✅ TRUE | 23,751 | 0 |
| 14 | ✅ TRUE | 23,889 | 0 |

**100% at every horizon.** The reframe is lossless: binary metrics remain exactly comparable.

## Class distribution — TRAINING splits (n; the class-4 flag lives here)
**Temporal (headline):**
| H | n | 0 (bg) | 1 (v.low) | 2 (low) | 3 (med) | 4 (high) |
|---|---|---|---|---|---|---|
| 1 | 4,786 | 3,687 (77.0%) | 289 (6.0%) | 327 (6.8%) | 326 (6.8%) | 157 (3.3%) |
| 3 | 2,810 | 2,023 (72.0%) | 226 (8.0%) | 238 (8.5%) | 226 (8.0%) | 97 (3.5%) |
| 5 | 3,462 | 2,617 (75.6%) | 220 (6.4%) | 252 (7.3%) | 250 (7.2%) | 123 (3.6%) |
| 7 | 14,848 | 12,565 (84.6%) | 636 (4.3%) | 725 (4.9%) | 674 (4.5%) | 248 (1.7%) |
| 14 | 14,819 | 12,695 (85.7%) | 611 (4.1%) | 659 (4.4%) | 613 (4.1%) | 241 (1.6%) |

**Spatial train:** class-4 = 113 / 94 / 112 / 262 / 262 (H=1/3/5/7/14).
**Random train:** class-4 = 262 / 189 / 237 / 480 / 481.
(Full table incl. test splits and percentages: `outputs/tables/e06_class_distribution.csv`.)

## STOP #1 flag decision
**No merge needed.** The threshold was "class 4 < 30 in any training split → consider merging 3+4."
**Minimum class-4 training count = 94** (H=3 spatial); every split is ≥ 30. Class 4 is thin at the
short-horizon spatial/temporal splits (94–157) — **per-class metrics for class 4 there will have
wide CIs; state the thin-class caveat** — but merging 3+4 is not required and would destroy the
top-category resolution the reframe is meant to add. Recommend keeping all 5 classes.

## Why the reframe is worth trying (the denser gradient)
Classes 1+2 ("very low" + "low") are **8.6–16.5%** of temporal training rows that the binary label
lumped entirely into HAB=0. The ordinal target roughly **doubles the count of informative
above-background examples** the model sees, without changing features or splits — exactly the
"denser gradient / higher effective-positive count" motivation in PROJECT.md §5 (E-06).

## STOP — awaiting author go-ahead before training
Per the instruction, halting here. On your go, the plan is: (1) ordinal RF/GBDT (5 classes) + the
unchanged binary RF as reference, adopted feature set (no E-01a neighbours), same repaired splits;
(2) metrics = quadratic-weighted kappa, per-class recall/precision (thin-class caveat for class 4),
ordinal PR; (3) threshold back to binary (class≥3) → PR-AUC + p@r80 with 30-day block-bootstrap CIs
vs the frozen baseline; (4) Bar B = weekly-max category accuracy at H=7 (no true 4-week arm — H=14
is NOT 4-week); (5) STOP #2 report before any further modeling. **Any decision to merge 3+4, lower
the threshold, or tune is yours, not automatic.**
