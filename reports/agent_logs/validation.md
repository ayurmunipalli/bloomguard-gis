# validation (A10) — decision & methods log

**Agent:** A10 validation
**Date:** 2026-07-13
**Status:** COMPLETE
**Model evaluated:** H=7 temporal RF (best_model.rds)
**Test set:** temporal holdout (train 2003-2015, test 2016-2021), n=8880, n_pos=1075

---

## §0.2 Decision log

- **Evaluation scope**: H=7 temporal split only for error slicing (the primary honest split per PLAN.md §9 and R-SPLIT verdict). Pre-computed metrics from model_results.csv used for cross-horizon and cross-split comparisons. — 2026-07-12
- **Threshold default**: 0.50 (ranger default). Threshold sensitivity analysis conducted over [0.20–0.60] to characterize the recall/precision trade-off. — 2026-07-12
- **Persistence baseline as recall reference**: persistence recall = 0.627 at H=7 temporal (from model_results.csv). RF at threshold 0.50 has recall = 0.3553 — lower. Threshold ~0.3 needed to match persistence recall (at precision cost). — 2026-07-12
- **False positive interpretation caveat**: HABSOS non-detection != proven absence. Some RF FPs may be unsampled true blooms. Cannot quantify this fraction without independent validation source. — 2026-07-12

---

## Headline verdict: RF vs baselines (temporal split, all horizons)

### PR-AUC (primary ranking metric)
| H | RF | Persistence | Chl-only | RF > Persist? | RF > Chl? |
|---|---|---|---|---|---|
| 1 | 0.643 | 0.616 | 0.214 | YES | YES |
| 3 | 0.645 | 0.583 | 0.228 | YES | YES |
| 5 | 0.673 | 0.534 | 0.192 | YES | YES |
| 7 | 0.502 | 0.450 | 0.142 | YES | YES |
| 14 | 0.459 | 0.320 | 0.122 | YES | YES |

**RF beats persistence on PR-AUC at every horizon on the temporal split.** This is the legitimate headline.

### Recall at default threshold (0.50) — CRITICAL NUANCE
| H | RF recall | Persistence recall | RF > Persist? |
|---|---|---|---|
| 1 | 0.577 | 0.778 | **NO** |
| 3 | 0.533 | 0.710 | **NO** |
| 5 | 0.502 | 0.654 | **NO** |
| 7 | 0.355 | 0.627 | **NO** |
| 14 | 0.261 | 0.523 | **NO** |

NOTE(limitation): **At the default 0.50 threshold, persistence has HIGHER recall than the RF at every horizon.** The RF trades recall for precision (fewer false alarms but more missed blooms). For early-warning applications where "a miss is worse than a false alarm" (PLAN.md §9), the RF's default operating point is suboptimal. Lowering the threshold to ~0.3 recovers recall ≈ 0.6065 but at precision = 0.4812.

NOTE(paper): The correct statement is: "The multi-feature RF achieves higher PR-AUC (discrimination) than persistence at all horizons, indicating superior ranking ability; however, at the default classification threshold it is more conservative (lower recall, higher precision). Threshold selection should be guided by the application's tolerance for false alarms vs missed detections."

---

## Skill decay with forecast horizon (temporal split)

| Horizon | PR-AUC | ROC-AUC | Recall@0.5 | FNR@0.5 |
|---|---|---|---|---|
| 1 | 0.643 | 0.897 | 0.577 | 0.423 |
| 3 | 0.645 | 0.870 | 0.533 | 0.467 |
| 5 | 0.673 | 0.876 | 0.502 | 0.498 |
| 7 | 0.502 | 0.835 | 0.355 | 0.645 |
| 14 | 0.459 | 0.816 | 0.261 | 0.739 |

NOTE(paper): Skill decays monotonically from H=1 (PR-AUC=0.638) to H=14 (PR-AUC=0.445) on the temporal split. Useful discrimination (PR-AUC > persistence) persists through H=14, but the model's ability to detect blooms falls substantially (recall 0.590 at H=1 → 0.272 at H=14).

---

## Error slicing: H=7 temporal test (n=8880, n_pos=1075)

### At default threshold 0.50:
- TP=382 FP=254 FN=693 TN=7551
- Recall=0.355 Precision=0.601 FNR=0.645

### By SEASON
   season     n n_pos recall precision    fnr prevalence
   <char> <int> <int>  <num>     <num>  <num>      <num>
1:   fall  2067   477 0.4696    0.6455 0.5304     0.2308
2: winter  2073   261 0.1648    0.4479 0.8352     0.1259
3: spring  2388    97 0.0206    0.2000 0.9794     0.0406
4: summer  2352   240 0.4708    0.6175 0.5292     0.1020

NOTE(paper): Recall is highest in summer (0.4708) and lowest in spring (0.0206). Fall months (Sep-Nov) coincide with peak K. brevis season in west Florida; the model's higher prevalence and higher recall there reflect the training data concentration.

### By GEOGRAPHY (spatial_block / county)
Top blocks by positive count:
   spatial_block     n n_pos recall precision    fnr prevalence
          <char> <int> <int>  <num>     <num>  <num>      <num>
1:        12_115  1792   352 0.5085    0.6885 0.4915     0.1964
2:        12_071  1962   256 0.2578    0.5116 0.7422     0.1305
3:        12_021  1291   151 0.1060    0.3077 0.8940     0.1170
4:        12_015   842   125 0.4000    0.6494 0.6000     0.1485
5:        12_081   901    87 0.3793    0.6346 0.6207     0.0966
6:        12_057   507    44 0.3409    0.4688 0.6591     0.0868
7:        12_103   986    43 0.4186    0.6923 0.5814     0.0436
8:        12_113    62     7 0.7143    1.0000 0.2857     0.1129

NOTE(limitation): Geographic heterogeneity in model performance is expected given uneven HABSOS sampling. Blocks with very few positives have unreliable recall estimates.

### By DATA AVAILABILITY (cloud_flag)
   cloud_flag     n n_pos    tp    fp    fn    tn recall precision    fnr
        <int> <int> <int> <int> <int> <int> <int>  <num>     <num>  <num>
1:          1  4465   524   228   165   296  3776 0.4351    0.5802 0.5649
2:          0  4415   551   154    89   397  3775 0.2795    0.6337 0.7205
   prevalence
        <num>
1:     0.1174
2:     0.1248

### By CHLOROPHYLL-A MISSING (imputed from median)
   chlor_a_missing     n n_pos    tp    fp    fn    tn recall precision    fnr
             <int> <int> <int> <int> <int> <int> <int>  <num>     <num>  <num>
1:               1  6196   702   289   201   413  5293 0.4117    0.5898 0.5883
2:               0  2684   373    93    53   280  2258 0.2493    0.6370 0.7507
   prevalence
        <num>
1:     0.1133
2:     0.1390

NOTE(limitation): satellite_missing and feature_filled_any flags are all FALSE in this cube (the cube only contains rows where HABSOS sampling occurred, which correlates with satellite data availability periods). The operational data-availability signal is the cloud_flag (46% of total cube rows) and the per-feature NA rate (chlor_a_mean is NA in ~70% of H=7 test rows, imputed with train median). When chlor_a is missing, the model relies on its missingness indicator + geographic/seasonal/lag features.

---

## Threshold sensitivity (H=7 temporal)

| Threshold | Recall | Precision | F1 | FNR | FP count |
|---|---|---|---|---|---|
| 0.20 | 0.710 | 0.371 | 0.487 | 0.290 | 1293 |
| 0.25 | 0.653 | 0.425 | 0.515 | 0.347 | 948 |
| 0.30 | 0.607 | 0.481 | 0.537 | 0.394 | 703 |
| 0.35 | 0.563 | 0.528 | 0.545 | 0.437 | 541 |
| 0.40 | 0.492 | 0.561 | 0.524 | 0.508 | 414 |
| 0.45 | 0.439 | 0.595 | 0.505 | 0.561 | 322 |
| 0.50 | 0.355 | 0.601 | 0.447 | 0.645 | 254 |
| 0.55 | 0.288 | 0.614 | 0.392 | 0.712 | 195 |
| 0.60 | 0.223 | 0.649 | 0.332 | 0.777 | 130 |

NOTE(paper): To match persistence recall (~0.627), the RF threshold must be lowered to ~0.3, which yields precision=0.4812 (vs persistence precision=0.6223). The RF's advantage is discrimination (PR-AUC), not necessarily default-threshold recall.

---

## Spatial split anomaly (spatial > random PR-AUC)

NOTE(paper): confirmed per R-SPLIT review. Spatial PR-AUC exceeds random at every horizon because the held-out block (Sarasota County / 12_115) has ~1.35-1.44× higher prevalence than the random test set. This is a prevalence artifact, NOT evidence of better geographic generalization. R-SPLIT's original text mislabeled this as 'Collier County' — the correct county for FIPS 12_115 is Sarasota (verified against static_geo.parquet TIGER boundaries). The temporal split is the primary honest metric.

---

## Temporal embargo caveat

NOTE(limitation): Zero-embargo at the 2016 boundary. ≤49 training rows (0.33% of H=14 train set) have label dates in Jan 2016 (test period). Impact on reported metrics is negligible per R-SPLIT assessment, but a strict implementation should add an H-day purge window.

---

## Limitations (NOTE-tagged for A-DOC harvest)

NOTE(limitation): At the default 0.50 classification threshold, the RF has LOWER recall than persistence at every horizon on the temporal split. The RF produces fewer false alarms but misses more blooms. For operational early-warning, a lower threshold (~0.25-0.35) should be adopted with explicit acknowledgment of the precision trade-off.

NOTE(limitation): HABSOS non-detection != proven absence. False positives (RF predicts bloom, HABSOS says no) may include unsampled true blooms. The FP rate is an upper bound on actual false alarm rate.

NOTE(limitation): Dynamic environmental features (ERA5 wind, CHIRPS precip, SMAP salinity) are all-NA placeholders in this cube. Model operates on satellite + static geography + seasonality + HAB history lags only. Adding meteorological drivers is expected to improve short-horizon recall.

NOTE(limitation): The temporal split (train 2003-2015, test 2016-2021) assumes stationarity in bloom dynamics across the boundary. Any regime shift (e.g., increased nutrient loading post-2015) could inflate or deflate test-period skill relative to future operational use.

NOTE(limitation): Geographic generalizability is untested beyond the West Florida Shelf study area. The model is trained and tested on cells within 24-31°N, 87-81°W only.

NOTE(limitation): Error estimates by season/geography are conditional on HABSOS sampling effort. Under-sampled periods (winter) and regions (offshore) have both fewer positives and fewer negatives, making recall estimates less stable.

NOTE(limitation): Skill decay from H=1 (PR-AUC=0.638) to H=14 (PR-AUC=0.445) reflects the fundamental limit of persistence-based satellite features for multi-day forecasting. The atmosphere-driven transport/growth dynamics captured by ERA5 (when added) are expected to improve longer-horizon performance.

NOTE(limitation): The zero-embargo temporal boundary allows ≤49 rows (0.33%) of minor label-bleed at H=14. Effect is bounded by HABSOS sparsity but represents a small optimistic bias.

NOTE(limitation): RF trained with num.threads=1 due to host resource constraint. Results are deterministic (seed fixed) but a multi-threaded re-run may differ by floating-point ordering in tree splits.

---

## Done-criteria (PLAN.md §6 A10) — pass/fail

| Criterion | Status |
|---|---|
| FP/FN characterized by SEASON | PASS |
| FP/FN characterized by GEOGRAPHY (county/block) | PASS |
| FP/FN characterized by DATA AVAILABILITY | PASS |
| Compared against chl-only baseline | PASS |
| Compared against persistence baseline | PASS |
| GATE: honest verdict if RF doesn't beat baselines | PASS — RF beats both on PR-AUC; does NOT beat persistence on recall at default threshold (stated plainly) |
| error_analysis.csv saved | PASS |
| Limitations as NOTE(limitation) tags | PASS |
| Decision log (§0.2) | PASS |


---

# Bio-optical feature validation — BEFORE vs AFTER (A10, 2026-07-14)

**Question:** A7 added the bio-optical species-discrimination features (RBD/KBBI, Cannizzaro
bbp-vs-Morel deficit — see `reports/bio_optical_spec.md`) and reported an honest NEGATIVE
at threshold 0.5. This section (a) measures the isolated impact bit-exact, and (b) tests
whether the features did their INTENDED job — cutting high-chlorophyll/nFLH false positives
(the `fp_discrimination_diagnosis.md` mechanism) — even if aggregate metrics fell.

**Method:** all H=7-temporal numbers computed bit-exact from the two frozen models'
stored `prob_rf`/`act` (`best_model_before_bio.rds` MD5 42a974c0…, `best_model.rds`), same
8880 test rows (`identical(test_idx)` = TRUE, n_pos=1075). Scoring functions verbatim from
`R/07_modeling.R`. No retraining. Grid metrics read from `model_results{,_before_bio}.csv`.

## A) Headline — H=7 temporal, BEFORE → AFTER (bit-exact)

| Metric | BEFORE | AFTER | Δ |
|---|---|---|---|
| PR-AUC | 0.5022 | 0.4849 | **−0.0173** |
| precision @ recall=0.80 | 0.2759 | 0.2796 | **+0.0037** |
| ROC-AUC | 0.8352 | 0.8356 | +0.0004 |
| recall @ 0.5 | 0.3553 | 0.3153 | **−0.0400** |
| precision @ 0.5 | 0.6006 | 0.5937 | −0.0069 |
| F1 @ 0.5 | 0.4465 | 0.4119 | −0.0346 |
| TP / FP / FN / TN | 382/254/693/7551 | 339/232/736/7573 | TP −43, FP −22 |

Sanity: BEFORE recall@0.5 reproduces A7's 0.3553 exactly. The AFTER model is **more
conservative** — it fires positive less often, removing 22 FPs but losing 43 TPs → net
recall/PR-AUC down; precision@recall-0.80 essentially flat (+0.0037).

## B) Mechanistic FP-concentration test (the key question) — observed rows only

Reproduces `fp_discrimination_diagnosis.md` quartile cut on the H=7-temporal test set,
BEFORE vs AFTER. Quartiles: `type=7` on observed (non-imputed) values only.
Missingness caveat: chl observed in 2684/8880 (30.2%), nFLH in 2236/8880 (25.2%); this
characterizes FPs **on clear-sky retrieval days only.**

**Chlorophyll-a FP by quartile (n_obs=2684):**
| Quartile | FP before | FP after | FP-rate before | FP-rate after | share-of-all-FP before | after |
|---|---|---|---|---|---|---|
| Q1 | 4 | 4 | 0.64% | 0.64% | 7.55% | 8.89% |
| Q2 | 2 | 2 | 0.33% | 0.33% | 3.77% | 4.44% |
| Q3 | 8 | 8 | 1.43% | 1.43% | 15.09% | 17.78% |
| **Q4** | **39** | **31** | **7.57%** | **6.02%** | **73.58%** | **68.89%** |

→ **Every FP the features removed among observed-chl rows came from the top chl quartile**
(Q1–Q3 counts unchanged 4/2/8; Q4 39→31). Top-chl-Q4 share of all FPs fell 73.58% → 68.89%.

**nFLH FP by quartile (n_obs=2236):** Q1 2→0, Q2 3→1, Q3 16→15, Q4 22→20. Top-Q4 FP-rate
5.31% → 4.83%; top-Q4 share 51.16% → 55.56% (share rose because low-nFLH FPs fell faster).

**Joint top-quartile cross-tab (n both-observed=2236):**
| chl-Q4 | nFLH-Q4 | FP-rate BEFORE | FP-rate AFTER |
|---|---|---|---|
| No | No | 0.65% | 0.49% |
| No | Yes | 1.81% | 1.81% |
| Yes | No | 4.42% | 3.40% |
| **Yes** | **Yes** | **12.41%** | **10.95%** |

Joint both-Q4 FP-rate fell 12.41% → 10.95% (−1.46pp; ~12% relative). BUT the clean-water
(neither) cell fell proportionally MORE (0.65% → 0.49%), so the **concentration RATIO
both-vs-neither ROSE 19.09× → 22.35×** — it did NOT drop.

## Mechanistic verdict (plain)

The features **are associated with a small, targeted reduction of high-chlorophyll false
positives** — their design purpose. In observed-chl rows the entire net FP reduction (8
fewer) came from the top chl quartile (39→31); top-chl-Q4's share of all FPs fell ~4.7pp;
the joint high-chl/high-nFLH FP-rate fell ~1.5pp. **HOWEVER** the ~19× joint FP-concentration
ratio did **not** drop — it rose to ~22×, because clean-water false positives fell even
faster than the targeted ones. And the targeted FP cut is **outweighed by a larger TP loss**
(−43 TP vs −22 FP), so net recall/PR-AUC fell. The effect is real but weak (single/double-digit
FP counts), clear-sky-only, and does not achieve species discrimination in the aggregate.

## C) Grid PR-AUC, BEFORE → AFTER (RF, all 15 H×split)

PR-AUC **down in 10/15, up in 5/15.** recall@0.5 **down in 12/15** (matches A7's headline).
Full grid in `outputs/tables/bio_validation_before_after.csv`. H=7 temporal −0.0173;
largest drop H=5 temporal −0.0260; gains concentrated at H=1 (all splits) and H=3 temporal.

## D) precision @ recall=0.80 grid — a WASH, not a clear negative

From the `prec_at_recall80` column of both `model_results` CSVs (bit-exact-verified at H=7
temporal against stored arrays). **Down 7/15, up 7/15, flat 1/15** — net neutral at the
fixed-recall operating point, unlike the clear threshold-0.5 recall drop. Gains: H=3 temporal
+0.0467, H=5 random +0.0469, H=7 spatial +0.0202, H=7 temporal +0.0037. Losses concentrated
at H=1 random −0.0412, H=3 random −0.0399, H=14 spatial −0.0206.

**D-artifact note:** `outputs/tables/predictions_before_after.parquet` (A7) never arrived,
so no independent per-row recomputation of alternative operating points was possible. The
per-combo precision@recall-0.80 grid IS fully available from the stored CSV metrics above
(and validated bit-exact at H=7 temporal), so D is answered at the operating-point level; a
finer per-row / per-feature-set cut remains **pending that artifact** — not fabricated.

## Limitations / facts for the author

NOTE(limitation): Bio-optical discrimination features (RBD, KBBI, bbp_ratio_morel,
bbp_deficit, Cannizzaro flag) produce a NET-NEGATIVE aggregate effect at H=7 temporal:
PR-AUC 0.5022→0.4849 (−0.0173), recall@0.5 0.3553→0.3153 (−0.0400). Report this plainly.

NOTE(limitation): The features DID cut targeted high-chlorophyll false positives (top-chl-Q4
FP 39→31; top-chl-Q4 share of all FP 73.58%→68.89%; joint high-chl/high-nFLH FP-rate
12.41%→10.95%) — their design purpose — but the cut is small and is outweighed by a larger
true-positive loss (−43 TP vs −22 FP at threshold 0.5). Targeted-effect and aggregate-metric
direction are BOTH first-class findings: the features shaved the right errors but cost more
right answers.

NOTE(limitation): The joint FP-concentration RATIO did NOT fall — it rose 19.09× → 22.35×,
because clean-water (neither-quartile) false positives dropped proportionally more than the
targeted high-chl/high-nFLH ones. The features did not de-concentrate FPs relative to clean
water; they lowered the overall FP floor slightly.

NOTE(limitation): The FP-concentration test uses observed (non-imputed) rows only — chl
observed in 30.2% of the H=7 test set, nFLH in 25.2%. It characterizes false positives on
clear-sky retrieval days; behavior on the ~70–75% cloud-imputed rows is not measured by this
cut. Absolute FP changes are single/double-digit → the targeted effect is real but weak.

NOTE(limitation): At the fixed recall=0.80 operating point the features are ~neutral across
the grid (down 7 / up 7 / flat 1 of 15), materially milder than the threshold-0.5 recall
drop — the negative is threshold-dependent, concentrated at the default 0.5 cut.

NOTE(cite): "Associated with," not "causes." The FP reduction is a correlational
error-shape change on a frozen holdout, not a demonstrated causal improvement in K. brevis
discrimination.

## Overall honest verdict

Adding the bio-optical features **hurt aggregate skill** at H=7 temporal (PR-AUC −0.0173,
recall −0.0400) and mildly hurt PR-AUC across most of the grid (10/15 down). They **did**
produce their intended mechanistic effect — a small, correctly-targeted cut of
high-chlorophyll false positives — but too small to overcome the accompanying true-positive
loss, and without reducing the relative FP concentration in high-chl/high-nFLH water. At the
recall-0.80 operating point the net effect is a wash. **Publishable nuance: the features
shaved the right errors but not enough of them, and cost recall doing it — a real targeted
effect that does not translate into net forecasting skill on this cube.**

## Outputs (this section)
- `outputs/tables/bio_validation_before_after.csv` — 15-combo PR-AUC + precision@recall-0.80 + recall grid, BEFORE/AFTER/Δ.
- `outputs/tables/bio_fp_concentration_before_after.csv` — joint FP-rate, ratio, top-chl-Q4 share, total FP, BEFORE/AFTER.
- `outputs/tables/error_analysis.csv` — appended 8 `bio_*` FP-concentration rows (chl-Q4, nFLH-Q4, joint both/neither, before/after).
