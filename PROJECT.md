# PROJECT.md — BloomGuard GIS: Tree-Side Improvement Program

**Governance — three files, three functions, not three sources of truth.**

| File | Function | Status |
|---|---|---|
| `CLAUDE.md` | **How** we operate: model assignment, hard rules, push discipline, result cards | live, auto-loaded by Claude Code |
| `PLAN.md` | **The spec**: pinned decisions (§2), feature spec (§8), evaluation protocol (§9), guardrails (§1), agent roles (§6) | **live reference.** §3 milestones M1–M3 are complete; §11/§12 are complete. Its §6 model tags are superseded by CLAUDE.md. |
| `PROJECT.md` *(this file)* | **The program**: what is being built now, the queue, the scoreboard, the pivot triggers, and the corrections in §2 | live |

**Precedence.** On *how to operate*: CLAUDE.md. On *what to build next*: PROJECT.md. On *a pinned
scientific decision* (grid size, study area, label threshold, what "forecasting" means): PLAN.md §2
— **still binding, do not relitigate.** PLAN.md's line 3 ("this file wins") predates this file and
refers to the original build; it needs the banner in §10.

**PROJECT.md does not replace PLAN.md.** PLAN.md answers "what did we decide and why"; this file
answers "what are we doing now and when do we stop." If you find yourself wanting to edit PLAN.md
§2, that is an author decision, not an agent one.

---

## 1. Where the project actually stands

Repo state as pushed: **post-wind, pre-bio-optical.** `outputs/tables/model_results.csv` is the
authoritative scoring output. The bio-optical branch (`feat/bio-optical-discrimination-features`,
commit `21320f7`) has been **merged into `main` and pushed to the remote**. Bio-optical was a
documented negative result and **was not adopted**, so the canonical `model_results.csv` still
reports the pre-bio model we ship; the bio-inclusive variant is preserved as
`model_results_bio_inclusive.csv`. The public repo now reflects that work.

`data/processed/model_dataset.parquet` — 65,939 × 114, final.

---

## 2. What the master record got wrong (read this before trusting any number)

Four corrections found by reading the repo. Each one changes what a headline claim means. They
are recorded here, not only in script headers, because that is exactly how they got lost.

### 2.1 The splits do not have the honesty properties we have been claiming

R-SPLIT issued **conditional passes**, written as `NOTE(limitation)` in `R/07_modeling.R:38–60`,
and they never propagated to any summary document:

- **Temporal split has zero embargo.** No purge/gap at the 2016 boundary. At H=14, ~49 training
  rows (0.33% of the H=14 training set) have a label date falling inside the test period. Small,
  bounded by HABSOS sparsity — but the effect on PR-AUC is "negligible but not zero," and we have
  no CI, so "negligible" is an assertion.
- **Spatial split has no buffer.** **14.6% of spatial test cells lie within ~10 km of a train
  cell** at county-block borders. Residual spatial autocorrelation that cannot be removed without
  sub-county blocking or a buffer zone.
- **Spatial split has a prevalence confound.** The holdout deterministically isolates Collier
  County (block `12_115`), the dominant hotspot: 11.4% positive vs 8.4% in the random test set
  (1.35×). Spatial H=7 PR-AUC (0.658) exceeding random (0.631) reflects **held-out prevalence,
  not better geographic generalisation.** It is "geographic transfer to a high-prevalence region"
  and must be reported as such. It is also a single fixed geography — n=1, no rotation.

**Consequence:** the temporal split is the headline honest number, and it is honest *modulo a
missing embargo*. Fix before measuring anything (§3, P0-A). **E-01 is unrunnable until the
spatial buffer exists** — neighbour features turn a 14.6% border adjacency into a direct leakage
channel, which is what makes E-01 the most leakage-prone experiment in the queue.

### 2.2 The RF loses to persistence at default thresholds — but this is an operating point, not a skill gap

**Corrected from an earlier draft of this file, which overstated it.** `config.yaml` names
`recall`, `pr_auc`, `false_negative_rate` as primary. At **default thresholds**, persistence has
higher recall and lower FNR than the RF at every horizon and split (H=7 temporal: 0.627/0.373 vs
0.3553/0.6447). But recall at a default threshold is an **operating point**, not skill. PR-AUC is
threshold-free, and at **matched recall = 0.80** the RF beats persistence at H=3/5/7/14 and loses
only at H=1:

| H | RF p@r80 | Persistence p@r80 | RF PR-AUC | Persistence PR-AUC |
|---|---|---|---|---|
| 1 | 0.4980 | **0.5192** | **0.6427** | 0.6158 |
| 3 | **0.5142** | 0.4143 | **0.6446** | 0.5827 |
| 5 | **0.4671** | 0.2768 | **0.6726** | 0.5339 |
| 7 | **0.2759** | 0.2145 | **0.5022** | 0.4503 |
| 14 | **0.2353** | 0.1677 | **0.4587** | 0.3196 |

**The real finding is that the curves cross.** At H=7 temporal, persistence achieves 674 TP /
409 FP (recall 0.627, precision 0.6223) — more catches at a *better* FP-per-TP ratio (0.607) than
the RF's 382 TP / 254 FP (0.665). So persistence dominates around recall ≈ 0.63. But the RF wins
at recall 0.80 and wins PR-AUC at every horizon. Neither dominates globally.

Two consequences: **(a)** the RF's PR-AUC edge over persistence is partly an artifact — PR-AUC
systematically undervalues a near-binary predictor whose score distribution is coarse, because the
curve interpolates poorly away from its one good point; **(b)** crossing curves are the textbook
condition where **ensembling or cascading beats either component** — which is why E-03 exists.

**Still true and still uncomfortable:** at H=7, the primary horizon, a one-line baseline catches
674 of 1,075 blooms where the RF catches 382. Any claim that the RF is the headline forecaster
must report the matched-recall comparison, not the default-threshold one — and must say where
persistence is better. The honest framing: *persistence owns H=1; the RF earns its keep from
H ≈ 5 out, and by H=14 wins decisively (+0.139 PR-AUC).*

### 2.3 The RF-vs-transformer comparison is feature-mismatched

`head_to_head_comparison.csv` holds **pre-wind** RF rows; `model_results.csv` holds **post-wind**.
The transformer rows are byte-identical in both — it **never received wind features**. So the
current head-to-head compares a post-wind RF against a no-wind transformer.

Temporal PR-AUC margins, RF over transformer: H=1 +0.0136 · H=3 +0.0099 · H=5 +0.0367 ·
H=7 +0.0092 · H=14 +0.0061. On the **pre-wind** (matched-feature) table, the transformer *leads*
at H=3 (+0.0006) and H=14 (+0.0075). The master record already noted these two flips but recorded
them as wind's contribution rather than as what they are: **the RF's win at H=3 and H=14 is
smaller than the wind effect that produced it, and the wind effect was itself declared null.**

Meanwhile the transformer's recall is 2–3× the RF's at every horizon (H=7 temporal: 0.8149 vs
0.3553; FNR 0.1851 vs 0.6447).

**The defensible claim is: "RF ties or beats the transformer on PR-AUC; the transformer has far
higher recall; on matched features the PR-AUC difference is within noise at most horizons."**
Not "RF beats the transformer." Fix by either giving the transformer wind (retrain, A11) or
reporting the pre-wind matched comparison as the head-to-head. **Author decision — this changes a
headline claim.**

### 2.4 The horizon arms are not comparable

Total rows per horizon: **H=1 7,791 · H=3 4,765 · H=5 6,151 · H=7 23,751 · H=14 23,889.**
H=7 and H=14 have ~4× the data because **HABSOS sampling is weekly** — a cell sampled at T and
again at T+7 is common; T and T+3 is not. Train prevalence also drops with horizon (9.9% → 6.7%).

So the skill-vs-horizon decay curve (`outputs/figures/skill_vs_horizon.png`, a required figure) is
partly a sample-size and prevalence curve. It also explains the non-monotonicity — H=5 PR-AUC
(0.6726) exceeds H=1 (0.6427), which no physical story predicts.

**A-DOC: the decay figure needs n_test and base rate on it, or it misleads.** Stage 0 must report
effective events **per horizon**, not pooled.

### 2.5 The importance table is test-derived, and the two importance measures disagree

`mean_abs_shap` in `top_features.csv` / `variable_importance.csv` is computed by permuting
features **in the test set** (`R/08_explainability.R:169–178`, `X_test <- te_dt[shap_idx, ]`).
It is a valid diagnostic. It is **invalid as a feature-selection criterion** — pruning by it is
test-set leakage. `permutation_importance` (ranger OOB) and `impurity_importance` are train-side
and safe. **They disagree materially:**

| Measure | Source | "Dead" features | Top feature |
|---|---|---|---|
| `mean_abs_shap` | **test set** | 86 / 149 below 0.001 | `hab_any_prior_14d` (rank 1, 20.1% of mass with `_7d`) |
| `permutation_importance` | OOB (train) | 22 / 149 at ≤ 0 | `doy`, then seasonality + rolling means — **HAB lags not in the top 10** |

**Hypothesis (not yet a finding — P0-J tests it).** The HAB lag features are informative as a
function of **sampling regime, not physics.** Train is 2003–2015 (sparse HABSOS sampling: a cell
rarely has a prior observation within 7–14 days, so the lag is mostly absent and carries little
OOB signal). Test is 2016–2021 (intensive sampling: the lag is dense and highly predictive). The
RF therefore learned to **under-weight a feature that becomes reliable exactly when it is
evaluated** — while persistence uses that signal directly and unconditionally.

If it holds, one mechanism explains three separate anomalies: the importance disagreement (§2.5),
the persistence dominance at mid-recall (§2.2), and the train/test prevalence shift (§5). It also
**promotes the supervision fix** from deferred to a live candidate, because it means the temporal
split is partly measuring transfer across a sampling regime rather than across time.

**P0-J:** compute the non-missing rate of `hab_any_prior_7d` and `hab_any_prior_14d` in train vs
test, per horizon. One query. It either confirms this or kills it, and either way it belongs in
the paper.

---

## 3. P0 — prerequisites. Nothing in §5 runs until these land.

| ID | Status | Task | Owner | Why it blocks |
|---|---|---|---|---|
| **P0-A** | not started | **Add an H-day embargo** around the temporal boundary: no training row's label date may fall in the test feature-date range. Re-run A7. | `modeling` (fable-5), gate R-SPLIT | Every baseline number is measured without it. |
| **P0-B** | not started | **Add a spatial buffer** to the block holdout: drop train cells within ≥1 neighbourhood radius of any test cell. Report how many rows this costs. | `modeling`, gate R-SPLIT | **E-01 cannot run without it.** |
| **P0-C** | not started | **Block-bootstrap CIs on the frozen baseline** (§5), n=1000, blocks = contiguous time segments. | `validation` (opus-4-8) | Without them no Δ in §4 is interpretable. |
| **P0-D** | **DONE** | **Deleted `head_to_head_comparison.csv`** (stale pre-wind RF numbers that disagreed with `model_results.csv`). | `modeling` | Stale numbers get cited. |
| **P0-E** | **DONE** | **Merged the bio-optical branch into `main` and pushed to the remote** (`21320f7`). | lead | A documented negative result exists only on one laptop. |
| **P0-F** | not started | **Fix `IS_PLACEHOLDER_ROW` AND→OR** at `R/05_environmental_features.R:773`. Re-run A5→A6. No retrain. | `env-features` | Row-level honesty flag silently zeroed once wind went real; precip/salinity are still placeholders. |
| **P0-G** | not started | **`renv::record("ecmwfr")`** — narrow only, never a blind snapshot. | lead | Reproducibility. |
| **P0-H** | not started | **Compute `prec_at_recall80` for the transformer.** It is empty for all 15 transformer rows. | `transformer` (fable-5) | It is the only metric that compares RF vs transformer at a matched operating point. Without it §2.3 cannot be settled. |
| **P0-I** | not started | **Recompute feature importance train-side** (OOB or training-fold CV) and write it as a separate, clearly-labelled column/table. Mark `mean_abs_shap` as diagnostic-only. | `explain` (opus-4-8) | E-00 cannot prune without it. See §2.5. |
| **P0-J** | not started | **Test the sampling-regime hypothesis:** non-missing rate of `hab_any_prior_7d`/`_14d`, train vs test, per horizon. One query. | `validation` (opus-4-8) | Confirms or kills the single mechanism that would explain §2.2 + §2.4 + §2.5 at once. |

**P0-A and P0-B will move the baseline.** Expect the temporal number to shift slightly and the
spatial number to drop. Re-freeze §5 afterward. This is the point: a baseline measured on a
leaky split cannot anchor a program whose effects are ~0.01.

---

## 4. The model roster (what we are actually training)

| Model | Status | Role |
|---|---|---|
| **Random Forest** (ranger) | exists, `best_model.rds` | Interpretable anchor + mentor's RTM method. **Stops being the model we improve; becomes the model we compare against.** |
| **GBDT** — CatBoost or LightGBM | **new (E-02)** | The push model. E-03/E-04/E-05/E-06 all land here. |
| **Persistence** | exists | Reference baseline — **and now a live component** (E-03). |
| **Chlorophyll-only** | exists | Reference baseline. Unchanged. |
| **Transformer** | **done, frozen** | M3 complete; 15 `.pt` files archived. Two closing tasks only (P0-H, E-00b), then it is a paper section, not a track. |
| **TabPFN v2** | **new, one-shot** | Single cheap test of "can any pretrained transformer tie the RF here." Run once, report, done. |

**Not doing:** a bigger transformer; time-series foundation models (Chronos/TimesFM/Moirai —
built for continuous zero-shot forecasting, not rare-event binary exceedance); GNN; U-Net/ConvLSTM.
The last two are **deferred behind Stage 0 and a target reframe**, not rejected.

---

## 5. The experiment queue (ordered — do not reorder without author sign-off)

One change each. One Result Card each (`CLAUDE.md`). Scored against the re-frozen §6 baseline.
**Nothing here runs until P0 lands** — adding a model to a broken ruler does not help.

### Stage 0 · Effective event count `[RUN FIRST]` — `validation`, opus-4-8
Cluster positive labels in space-time into **independent bloom onsets**. Report `N_events` and
`N_positive_cell_days` **per horizon per split** (§2.4: the arms are not comparable, so pooled
numbers are meaningless). One afternoon. It is the decision variable for the whole program and
has never been done.

| `N_events` | Action |
|---|---|
| **< ~100** | Deep is arithmetically hopeless here. Tree-only. This *explains* the transformer null rather than merely observing it — a stronger claim than the null alone. |
| **~100–1,000** | Tree-favoured regime. Proceed. Deep stays deferred. |
| **> ~1,000** | Deep becomes arguable **after** spatial reframing. Finish the tree queue anyway. |

### Stage 0b · TabPFN v2 (parallel) — `transformer`, fable-5
Same features, same splits, near-zero engineering. Its sweet spot (≤10K samples, less harmed by
uninformative features than an MLP) matches this regime. If TabPFN cannot beat the RF on honest
splits, the ceiling is the **framing**, not our transformer implementation. Finding either way.

### E-00 · Feature pruning `[blocked on P0-I]` — `datacube` + `modeling`
**Hypothesis.** 22/149 features have OOB permutation importance ≤ 0. With ranger's default
`mtry ≈ √114 ≈ 10`, each split chooses among ~10 candidates; dead features dilute that draw.
Pruning reduces variance at no cost.

**Prune on train-side OOB importance only.** Never on `mean_abs_shap` — it is test-derived and
pruning by it is selection leakage (§2.5). The 86/149 "dead by SHAP" figure is a **diagnostic**;
do not use it as the threshold.

Cheap, and it cleans the base that E-01 adds features to — which is why it precedes E-01.
**Success:** WIN rule; but a NULL with no loss is still adopted for variance reduction — say so
explicitly and re-freeze.

### E-00b · Transformer re-run on pruned features — `transformer`, fable-5
**This is the highest-value remaining use of the transformer, and it converts a bare null into a
mechanism.** Grinsztajn's mechanism (2) predicts uninformative features hurt neural nets far more
than trees. So pruning should help the transformer **more** than the RF. Re-run both on the E-00
feature set (**with wind, for parity — §2.3**) and compare the gap before vs after.

- Gap closes → we have demonstrated Grinsztajn (2) on real HAB data. A finding, not a null.
- Gap holds → the null is stronger and better explained.

Either outcome is a paper section. Cost: one re-run.

### E-01 · Spatial-lag features `[HIGHEST PRIORITY — blocked on P0-B, E-00]` — `datacube` + `modeling`
**Hypothesis.** The per-cell design discards spatial coherence. At H=7/14 a cell's risk depends
more on what is advecting *toward* it than on its own state. This is also the only region where
the RF clearly beats persistence (§2.2), so it is the right place to push.

**Build.** Queen-neighbourhood mean/max of chl, nFLH, Kd490, SST; ring-2 (~20 km) variants;
neighbour *trend* features, not just levels. Then, as a **separate block**:
- **E-01a** isotropic neighbours
- **E-01b** upstream-weighted by climatological current direction — the cheap tree-side borrow of
  the Liu 2023 Lagrangian insight

Attribute independently. If E-01a wins and E-01b adds nothing, that is itself a finding.

**Leakage — R6 and R-SPLIT scrutinise specifically.** Neighbour features at T are legitimate; any
reaching toward T+H are fatal. **The spatial buffer must widen with the neighbourhood radius**
(P0-B) — with a 14.6% border adjacency and no buffer, E-01 leaks by construction. A large gain
without P0-B is a bug, not a result.

**Success.** WIN rule, evaluated preferentially at H=7 and H=14.

### E-02 · GBDT + AUPRC surrogate + calibration — `modeling`, fable-5
RF is bagging and near its ceiling. **The reason to move to boosting is not out-of-the-box
accuracy — it is that boosting unlocks custom objectives, monotone constraints, and native
imbalance handling.** E-03…E-06 all depend on it.

There is also a case-specific reason to expect more than the usual +0.00–0.03: RF's `mtry`
subsampling dilutes across a feature set with many dead columns, while GBDT is greedy over all
features per split. **CatBoost is the best fit** — native categorical handling for `county_fips` /
`month` / `spatial_block`, and ordered boosting targets exactly this small-sample overfitting
regime.

Blocked temporal CV with a gap. AUPRC/AP surrogate (SOAP, libAUC) instead of logloss.
**Recalibrate (isotonic, held-out temporal block) *after* class weighting** — `scale_pos_weight`
destroys calibration, and p@r80 is a threshold on the score distribution, so an uncalibrated score
makes that operating point meaningless. Ship a calibration curve with every PR curve from here on.
**Keep the RF** as the interpretable anchor; if the GBDT ties, ship the RF.

### E-03 · Persistence ↔ tree cascade / ensemble — `modeling`, fable-5
**Promoted ahead of the bio-optical repair: higher expected value, lower cost.** §2.2 shows the PR
curves cross — persistence owns recall ≈ 0.63, the tree owns recall ≈ 0.80 and long horizons.
Crossing curves are the textbook ensembling condition, and Shwartz-Ziv & Armon found ensembles
beat either component.

Try, in order of cheapness: score averaging / rank averaging; a cascade (persistence gates,
tree adjudicates); stacking with a calibrated meta-learner. **Nothing new is trained** — this
combines models that already exist.

**Watch for:** if §2.5's hypothesis holds, the RF is under-weighting the lag feature and this
ensemble is partly *compensating for a fixable training-distribution problem*. If so, the
supervision fix is the better answer and this is a patch. Report both readings.

### E-04 · Bio-optical extraction fix — `sat-features` + `modeling`
D6 is not "the features don't work." They removed the **right** FPs (every one from the top chl
quartile) but **too few** — ~22 FPs removed vs ~40 TPs suppressed, so the concentration ratio
*rose* from ~19× to ~22×. That is an extraction problem.

- **E-04a · flags as booleans.** Feed the published criteria as binary features rather than raw
  continuous indices: `RBD > 0.15 & KBBI > 0.3·RBD` (Amin 2009); `Chl > 1.5 mg m⁻³ & bbp(550) <
  Morel-1988 Case-1 expected` (Cannizzaro 2008). Hand the tree the split instead of making it find
  the threshold under sparse positives.
- **E-04b · interactions.** Explicit `chl × discrimination` terms. The discrimination is only
  meaningful conditional on high chl; a shallow tree with few positive events may never find it.
- **E-04c · shelf-specific thresholds.** Amin's 0.15 was validated elsewhere. Sweep **on training
  folds only**; freeze before scoring. **Most at risk of test-set optimisation — the sweep never
  touches test years.**

**Success.** WIN rule **and** FP concentration ratio must **fall below 19×**. A PR-AUC gain with a
rising ratio means the features moved the wrong errors → NEGATIVE regardless of the metric.

### E-05 · Monotone constraints — `modeling` (requires E-02)
Real domain monotonicity (risk increases in chl level, in RBD) regularises against noise-fitting,
which disproportionately helps small-sample rare-event problems. Constrain only where the physics
is unambiguous. **Do not constrain SST** — the chl/SST relationship for *K. brevis* is not
monotone in an obvious direction, and a wrong constraint is worse than none. A NULL that costs
nothing and improves defensibility is worth keeping if PR-AUC is flat within CI; say so.

### E-06 · Ordinal severity reframe `[AUTHOR DECISION — biggest swing]`
FWC order-of-magnitude categories → denser gradient, higher effective-positive count, alignment
with Medina 2024. Threshold back to binary at eval for comparability. **This is a label change,
not a tree tweak.** It re-opens the evaluation story. Agents may not initiate it.

### Deferred
- **Supervision fix** (restrict training to well-sampled periods; add a sampling-density feature so
  the model can condition on regime; HABSOS+satellite label fusion). **Promoted from "parked" to a
  live candidate by §2.5** — if the sampling-regime hypothesis holds, this is the root cause behind
  the persistence dominance and the importance disagreement, and no architecture beats it. Changes
  the label and the evaluation. **Author call, and P0-J decides whether to escalate it.**
- **Deep / spatial field / pretraining.** Gated on Stage 0. Do not start. Note E-01's neighbour
  features are hand-crafted message passing — **if E-01 wins, a GNN is the principled version**, and
  that is the clean escalation story.
- **CHIRPS precip** (blocked, transient 403/CrowdSec — retry from a different IP after cooldown);
  **SMAP salinity** (skipped: 40–70 km, too coarse for a 10 km grid).
- **FAI** — permanently uncomputable from daily MODIS L3m (needs ~859/1240 nm bands absent from the
  product; confirmed twice). Disclosed as a limitation; nFLH is the fluorescence discriminator.
  **Do not re-litigate.**

---

## 6. Frozen baseline — RF, temporal split (post-wind, pre-bio-optical, **pre-embargo**)

From `outputs/tables/model_results.csv`. **Re-freeze after P0-A/P0-B, and again after E-00.**

| H | PR-AUC | p@r80 | Recall | Precision | FNR | Test prev | Train prev | n_test | n_pos |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.6427 | 0.4980 | 0.5772 | 0.6276 | 0.4228 | 15.7% | 9.9% | 3,004 | 473 |
| 3 | 0.6446 | 0.5142 | 0.5331 | 0.6968 | 0.4669 | 18.5% | 12.7% | 1,952 | 362 |
| 5 | 0.6726 | 0.4671 | 0.5023 | 0.7219 | 0.4977 | 16.2% | 12.3% | 2,677 | 434 |
| **7** | **0.5022** | **0.2759** | **0.3553** | **0.6006** | **0.6447** | **12.1%** | **7.2%** | **8,880** | **1,075** |
| 14 | 0.4587 | 0.2353 | 0.2614 | 0.6125 | 0.7386 | 11.2% | 6.7% | 9,021 | 1,010 |

H=7 temporal confusion (authoritative, A7 == A10 post-reconciliation):
**TP=382 · FP=254 · FN=693 · TN=7551.**

**Note the train/test prevalence shift:** test prevalence is ~1.6× train at every horizon, because
the 2016 cutoff holds out the post-2015 HABSOS intensive-sampling era. The temporal split is
therefore also a **sampling-regime shift**, not only a time shift. Real, and arguably the honest
thing to test — but it must be stated, because it means the temporal number partly measures
transfer across a sampling regime.

**FP concentration diagnostic (the E-03 target).** Top quartile of *both* chl and nFLH: 12.4% FP
rate vs 0.65% for neither ≈ **19×**. Rose to ~22× post-bio-optical. SST and distance-to-shore show
no comparable concentration — a clean control.

**Reference baselines, temporal PR-AUC:** persistence 0.6158 / 0.5827 / 0.5339 / 0.4503 / 0.3196;
chl-only 0.2139 / 0.2282 / 0.1918 / 0.1417 / 0.1220 (H=1/3/5/7/14).

---

## 7. Scoreboard — are we on track, and when do we pivot?

### 7.1 Live scoreboard
Scoreboard rows are for work that produces a metric. Non-metric P0 chores are tracked in §3 only.
A-DOC (opus-4-8) appends one row per experiment. Never rewrite history; supersede.

| ID | Experiment | Status | H=7 PR-AUC | Δ | 95% CI | H=14 PR-AUC | Δ | Beats pers. @r80? | FP conc. | Verdict | Gates |
|----|-----------|--------|-----------|---|--------|-------------|---|---|---|---------|-------|
| — | **BASELINE (RF, pre-embargo)** | frozen | 0.5022 | — | *P0-C* | 0.4587 | — | ✓ (0.276 vs 0.215) | 19× | — | conditional |
| P0-A | Temporal embargo | not started | | | | | | | | | |
| P0-B | Spatial buffer | not started | | | | | | | | | |
| P0-H | Transformer p@r80 | not started | | | | | | | | | |
| P0-I | Train-side importance | not started | | | | | | | | | |
| P0-J | Sampling-regime test | not started | | | | | | | | | |
| — | **BASELINE re-frozen** | pending | | | | | | | | | |
| S0 | Effective event count | not started | | | | | | | | | |
| S0b | TabPFN v2 | not started | | | | | | | | | |
| E-00 | Feature pruning (OOB) | blocked P0-I | | | | | | | | | |
| E-00b | Transformer re-run, pruned | blocked E-00 | | | | | | | | | |
| E-01a | Spatial lag (isotropic) | blocked P0-B, E-00 | | | | | | | | | |
| E-01b | Spatial lag (upstream) | blocked P0-B, E-00 | | | | | | | | | |
| E-02 | GBDT + AUPRC + calib | not started | | | | | | | | | |
| E-03 | Persistence↔tree cascade | blocked E-02 | | | | | | | | | |
| E-04a | Bio-opt flags as booleans | not started | | | | | | | | | |
| E-04b | Bio-opt interactions | not started | | | | | | | | | |
| E-04c | Shelf-specific thresholds | not started | | | | | | | | | |
| E-05 | Monotone constraints | blocked E-02 | | | | | | | | | |
| E-06 | Ordinal severity | not authorized | | | | | | | | | |

### 7.2 Verdict rule (apply mechanically)

- **WIN** — ΔPR-AUC ≥ +0.02 at H=7 temporal, 95% CI on Δ excludes 0, sustained ≥3/5 horizons, and
  the mechanistic check passes.
- **NULL** — CI includes 0. **Document and move on. Do not tune it.**
- **NEGATIVE** — CI excludes 0 and Δ < 0, **or** the metric moved while the mechanistic check
  failed. Publishable. Keep it.
- **UNRESOLVED** — no CI. Not a verdict. Go compute it.
- **SUSPECT** — Δ > +0.05 from a single change. Leakage bug report until R6 and R-SPLIT clear it.

### 7.3 Pivot triggers (pre-committed, so we cannot rationalise later)

| Trigger | Pivot |
|---|---|
| P0-A/P0-B move H=7 temporal PR-AUC by > 0.02 | The old baseline was leaking materially. Re-examine every claim in the master record built on it before proceeding. |
| **P0-J confirms the sampling-regime hypothesis** (§2.5) | Escalate the **supervision fix** to a live experiment ahead of E-04. It would be the root cause, and no architecture beats it. Author decision. |
| **E-00b closes the RF↔transformer gap** | Grinsztajn mechanism (2) demonstrated on real HAB data. The transformer section becomes a *mechanistic finding*, not a null. Report it as the paper's methodological contribution. |
| **E-03 (cascade) beats the tuned GBDT** | The tree alone was never the right unit. Say so — and check §2.5 first, in case the cascade is compensating for a fixable training-distribution problem rather than a real complementarity. |
| Stage 0 returns `N_events < 100` | Deep is closed for this design. Tree-only. Fold into the transformer-null section — it upgrades an observation into a mechanism. |
| **E-01 and E-02 both NULL** | The ceiling is the *framing*, not the tree. Skip E-04/E-05. Go to the author for the E-06 decision. |
| E-01 NULL but E-02 WIN | Spatial structure isn't the bottleneck on this shelf at these horizons — a real, interesting finding. Continue. |
| E-04 NEGATIVE again (ratio still rising) | Bio-optical discrimination does not transfer to this framing. Close permanently; write D6 + E-04 as one coherent negative. Stop. |
| **E-06 also NULL** | The ceiling is label quality or intrinsic predictability, not modelling. Pivot to the supervision fix — or stop and write. Both defensible. |
| **H=14 PR-AUC still < 3× base rate after E-01** | Long-horizon skill is at its intrinsic ceiling. **Stop chasing H=14.** No tree tweak fixes an unforecastable target. Report the decay curve — it *is* the result. |
| **Nothing ever beats persistence on recall + FNR** | Then say so plainly in the paper. The RF's contribution is long-horizon PR-AUC and a mappable calibrated risk surface, not recall. That is a narrower but true claim — and a true narrow claim beats an overreaching one. |
| Any experiment re-run with new hyperparameters after a NULL | **Halt.** Test-set optimisation. |
| ≥ 3 consecutive NULLs | The program has answered its question: the RF is hard to beat on this shelf. **That is the paper. Write it.** |

### 7.4 The honest read on "on track"

**E-01 and E-03 are the only experiments with a plausible path to a large gain.** E-00 and E-02 are
cleanup and unlock. E-05 is consolidation. E-04 is a repair attempt on a known negative. E-06 is
the real swing but changes the target. **E-00b and P0-J are the two cheapest ways to convert an
existing null into an explained mechanism** — the best paper-value-per-hour on the board. If the queue delivers +0.03–0.06 PR-AUC at mid-to-long horizons and nothing at H=14,
that is a **successful outcome** — and a better paper than a mystery +0.15.

**The two bars, kept separate.** (A) Beat our own RF: §7.2 WIN rule. (B) Beat published SOTA:
Medina et al. 2024 report **accuracy on weekly-max abundance categories** at 1-week/4-week
(73%/84%). That is not comparable to binary daily-exceedance PR-AUC, and our H=14 is not their
4-week horizon. Putting 0.64 next to 73% would not survive a reviewer. Bar B becomes real only
via E-06 (adopt the ordinal target, report category accuracy at matched horizons on our splits) —
or is honestly retired with "a direct numerical comparison is not available," which is perfectly
publishable. **Note the published *forecasting* frontier is a Lagrangian physics model (Liu 2023)
and a boosted random forest (Medina 2024) — not a deep net. Improving the tree *is* competing at
the frontier.**

---

## 8. The standing cost

Path 1 (write now) is complete and defensible **today**: a validated RF forecaster, a GIS risk
product with intra-cell drill-down, an honest transformer comparison, three well-characterised
negative results that bound the problem. Every redesign-and-remeasure pass spends some of the
rigor that makes those results credible, because each pass looks at the test set again. The
triggers in §6.3 cap that cost. **They are the mechanism, not a formality.**

Caveat, in fairness: §2 shows the current story has real defects (unfixed splits, an unstated
persistence deficit, a mismatched head-to-head). P0 is not optional under either path — it is
required to write the paper honestly, whether or not §4 ever runs.

---

## 9. Citations

**Do not cite:** "Harris et al. 2021, *Harmful Algae* 103:101999" — appears fabricated; that
article number belongs to an unrelated cyanobacteria paper.

- **Medina et al. (2024)**, *Harmful Algae* 102729 — boosted RF, 73%/84% at 1/4-week. **Bar B.**
- **Liu et al. (2023)**, *Deep-Sea Research II* 212:105335 — Lagrangian 3.5-day forecast SOTA.
- **Lyubchich et al. (2021)**, *JMSE* 9(9):999 — WFS ML forecasting; same >10⁵ cells/L threshold.
- **Yao/Hu et al. (2023)**, *RSE* 298:113833 — VIIRS CNN **detection**, F1≈89%. Different task.
- **Grinsztajn, Oyallon & Varoquaux (2022)**, NeurIPS D&B; **Shwartz-Ziv & Armon (2022)**,
  *Information Fusion* 81:84–90 — trees vs deep on tabular.
- **Zeng et al. (2023)**, AAAI 37(9):11121–11128 — DLinear vs transformers.
- **Hollmann et al. (2022/2025)**, ICLR / *Nature* s41586-024-08328-6 — TabPFN.
- **Qi et al. (2021)**, NeurIPS — SOAP, differentiable AUPRC.
- **Saito & Rehmsmeier (2015)**, *PLOS ONE* — PR > ROC under imbalance.
- **Amin et al. (2009)**, *Optics Express* 17(11):9126–44, doi:10.1364/OE.17.009126 — RBD/KBBI.
  RBD = nLw678−nLw667; KBBI = (nLw678−nLw667)/(nLw678+nLw667); nLw = Rrs·F0.
  F0(667)=1522.491, F0(678)=1480.511 W m⁻² µm⁻¹.
- **Cannizzaro et al. (2008)**, *Continental Shelf Research* 28(1):137–158 — bbp/chl.
- **Morel (1988)**, *JGR* 93(C9):10749–10768 —
  bbp(550)=0.30·C^0.62·[0.002+0.02·(0.5−0.25·log₁₀C)].
- **Hu et al. (2022)**, *Harmful Algae* 117:102289 — study area.
- **Green, J. W. (2022)**, *The Professional Geographer* 74(1):67–78 — RF/RTM.
- **Izadi et al. (2021)**, *Remote Sensing* 13(19):3863 — MODIS+XGBoost, closest analog.
- **Breiman (2001)**; **Wright & Ziegler (2017)** — Random Forests / ranger.
- **HABSOS** — NOAA/NCEI, CC0.

---

## 10. Housekeeping carried forward

1. **Banner on `PLAN.md` + README fix** (A-DOC, first action) — PLAN.md line 3 says "this file
   wins" and README line 12 says PLAN.md "is the source of truth"; both predate this file. Exact
   patches are in the chat handoff. Do not delete PLAN.md content — §2/§8/§9 are live spec.
2. Update `paper/design_rationale.md`: bio-optical section "planned" → the negative result; add
   §2 of this file (split caveats, persistence deficit, feature mismatch, horizon confound).
3. Commit the master record + the three research reports into `paper/refs_pdfs/` for A-DOC to fold
   into `paper/source_set.md`.
4. `R/07_modeling.R:24` says "DO NOT git-commit — awaiting R-SPLIT sign-off." It is committed and
   R-SPLIT conditionally passed. Update the header so it stops contradicting reality.
5. Mark `mean_abs_shap` as **diagnostic-only** in `outputs/tables/top_features.csv` and
   `variable_importance.csv` headers, and in `R/08_explainability.R`. It is test-derived (§2.5) and
   the next person to read that table will otherwise use it to select features.
6. **A-DOC:** §2.2, §2.3, §2.4 and §2.5 each change what a headline number means. None of them
   were in the master record; three lived only in script headers. Fold all four into
   `paper/design_rationale.md` and `paper/source_set.md` in the same pass.