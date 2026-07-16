# BloomGuard GIS — Project Plan (`PLAN.md`)

> **What this file is.** The decision record: *what did we decide, and why.*
> **What it is not.** The operating queue — that is `PROJECT.md` (*what are we doing now, and
> when do we stop*). The agent manual is `CLAUDE.md` (*how do agents behave*).
>
> **Precedence (D-22 — do not recreate three sources of truth):**
> `CLAUDE.md` governs agent behaviour · `PLAN.md §2/§8/§9` governs spec · `PROJECT.md` governs
> the current queue. Where they conflict, the more specific file wins for its own domain, and
> the conflict is a **stop-and-report event**, not something to resolve locally.
>
> Revision 2026-07-16. Supersedes the 2026-07 revision. Changes to §2 are logged in
> `reports/decisions.md` per the rule in that section.

---

## 0. Agent operating contract (read first)

Unchanged from the previous revision and still binding. Two conventions matter most:

**0.1 The notes convention.** Every script carries a header block (`FILE / PURPOSE / INPUTS /
OUTPUTS / TECHNIQUES / CITATIONS`) and inline `NOTE(paper)`, `NOTE(cite)`, `NOTE(limitation)`,
`NOTE(verify)` tags. This is how the author writes the paper.

> **Amendment (P-04).** A caveat that lives only in a script header **does not propagate**. Both
> split defects (D-07 embargo, D-08 buffer) were correctly identified by R-SPLIT, written as
> `NOTE(limitation)` in `R/07_modeling.R`, and reached no summary document — they were
> rediscovered months later by reading source. **Any `NOTE(limitation)` must be mirrored into
> `PROJECT.md` in the same commit that creates it.** A note that is not mirrored is not a note.

**0.2 The per-agent decision log.** `reports/agent_logs/<agent>.md`, sections: Decisions · Data
sources used · Methods & techniques · Open questions / caveats / limitations.

**0.3 No prose.** Agents write logs, diagnoses, tables, Result Cards, commit messages. The author
writes the paper.

---

## 1. Non-negotiable guardrails

1. **HABSOS non-detection ≠ absence.** It can mean "not sampled." Sampling effort is uneven in
   space and time. Every recall estimate carries this caveat.
2. **Never let a fill masquerade as an observation.** Filled rows carry `feature_filled = TRUE`.
   A gap is a gap; report `n_expected` vs `n_retrieved`.
3. **Resolution honesty.** MODIS ~4.6 km vs 10 km cells: ~4–6 pixels per cell, no sub-pixel
   precision. ERA5 ~28 km and SSH ~28 km are **regional** covariates. SMAP at 40–70 km is
   broad-context only and is currently a placeholder.
4. **One authoritative scorer.** `outputs/tables/model_results.csv`. See `CLAUDE.md` hard rule 3.
5. **Verify before asserting.** No claim about the repo, the data, or a constant without a
   command that produced it. See `CLAUDE.md` hard rule 12.

---

## 2. Pinned decisions (do not relitigate)

The lead may change these only with an explicit written rationale logged in `reports/decisions.md`.

### 2.0 Live decisions

| # | Decision | Locked value | Rationale |
|---|---|---|---|
| D0 | Primary language | **R** for data + spatial. Python only where no R path exists. | All existing work and the mentor's method are in R. |
| D1 | Study area | **24–31°N, 87–81°W**, defined in code | Established MODIS *K. brevis* extent, Hu et al. (2022) *Harmful Algae* 117:102289. |
| D2 | Positive label threshold | ***K. brevis* > 100,000 cells/L** | FWC/NOAA operational category boundary (class 3, "medium"). Matches the direct comparator Duus et al. (2026). **See D14 — lowering it was evaluated and rejected on evidence.** |
| D3 | Primary target | **Binary** (`HAB = 1` if cell-day exceeds D2) | E-06 confirmed the ordinal reframe is lossless but adds no skill; the derived binary reproduces `HAB_H` exactly. |
| D4 | Unit of analysis | **Grid cell × date**, **10 km × 10 km**, EPSG:5070 | Mentor's RTM method; 10 km sits above the ~4.6 km MODIS pixel and below the coarse environmental fields. |
| D5 | Prediction target & horizon | **`HAB` at cell *c*, day *T+H*** from features through *T*. Primary **H = 7**; report H ∈ {1,3,5,7,14}. | The label is a future event → genuine forecasting. |
| D6 | Framing honesty | "Forecasting" is earned only because the label is future. Report skill as a function of H; never claim an unvalidated lead. | Say the horizon, show the decay. |
| D9 | Explainability | SHAP + variable importance, **diagnostic only** | Selection must be train-derived — D-12. |
| D10 | Central data artifact | Spatiotemporal datacube, cell × date × variables | |
| D11 | Trend features are first-class | Every level gets deltas, % change, trailing slopes, threshold-crossing flags | **Amended by D18** — slopes must be calendar-day, not observation-order. |
| D12 | Intra-cell attention layer | GIS drill-down to ~4 km MODIS pixels. **A diagnostic overlay, NOT a validated sub-cell forecast.** | Built in A9; must not gate M1. |

### 2.1 Superseded decisions

| # | Was | Now | Rationale (logged 2026-07-16) |
|---|---|---|---|
| **D7** | Stage 1 RF → Stage 2 Transformer | **Stage 1 gradient-boosted trees (LightGBM). No deep stage.** | See D14(a). With **333 effective independent bloom events**, no from-scratch deep model can beat a tuned tree ensemble regardless of architecture or tuning — this is now a *measured* claim, not an empirical tie. Grinsztajn et al. (2022) NeurIPS; Shwartz-Ziv & Armon (2022) *Information Fusion* 81:84–90. |
| **D8** | Transformer is a committed second stage | **Retired.** The existing transformer result stands as a reported null (TIE, CI spans zero at H=7: −0.0018 [−0.037, +0.027]). | It is now a *predicted* null with a measured cause, which is a stronger result than an unexplained one. Do not re-run. Do not tune. `python/` is archived, not deleted. |

### 2.2 New decisions

| # | Decision | Locked value | Rationale |
|---|---|---|---|
| **D13** | **Two arms** | **Arm A (portable)** — satellite + global reanalysis only, zero HABSOS-derived features. **Arm B (instrumented)** — Arm A + HABSOS-derived lags + any gauge data. | The project thesis is deployability where no in-situ network exists. `hab_any_prior_*` requires a boat to have sampled the cell *at scoring time*, and is undefined on 99.76% of the grid on any given day — it breaks portability **and** makes an honest whole-shelf surface impossible. **A−B is the contribution**, not either arm alone. Arm B is the in-family point of contact with Duus et al. (2026). |
| **D14** | **Two separate limits. Do not conflate them.** | **(a) Data limit — 333 events.** The WFS produces **~17.5 independent bloom events/yr**; the 2003–2021 MODIS era gives **333** (spatial-merged, 14-day rule). **(b) Resolution floor — ~40 blocks.** The H=7 temporal CI is set by the **40 positive-carrying 30-day blocks** in the 2016-01-01 → 2021-08-24 test window (69 blocks total, 29 with zero positives). Measured half-width on `rf_roc` = **0.0334** ⇒ σ ≈ **0.108**. | **(a)** is a property of the ocean and sets *model capacity*: ~10 events/feature supports **~33 features**, not 149 (2.2 now); and no from-scratch deep model can beat a tuned tree ensemble at this event count (see D7). **(b)** is a property of the **evaluation design** and sets *what we can prove*. <br><br>**CORRECTION (Gate 0, 2026-07-16).** The previous revision claimed the floor followed from 1.96·σ/√333. **That derivation was wrong** — 333 is a shelf-wide count over 2003–2021; the H=7 CI is computed on a 5.6-year test slice. Two numbers that happened to agree were reported as mechanistic confirmation. They are different populations. The √333 match was numerology. <br><br>Still standing, still measured: CI width scales as **n_rows^-0.126**, not n^-0.5 — rows carry almost no independent information; the unit is the block, not the row. **Consequence:** any effect under ~±0.033 is unresolvable at H=7 **under the current single-cutoff split** — and per D20 that split is a design choice, not a physical limit. |
| **D20** | **The temporal split is n=1 and that is fixable** | Move to **rolling-origin CV** (train ≤2010 → test 2011; ≤2011 → test 2012; …). Report the single-2016-cutoff split alongside it for continuity. | D-10 already criticises the *spatial* split for being a single fixed geography (n=1, no rotation). The same objection applies to the temporal split and was never made. The 2016 cutoff puts **5.6 years / 40 positive blocks** in test. Rolling origin puts ~11 years / **~78 positive blocks** in test ⇒ half-width **0.0334 → ~0.024**, a **1.4× tightening**. **This is the only genuine power lever identified.** <br><br>**It is not free.** The estimand changes — "average skill across origins" is not "skill after 2016" — and must be stated as such, not swapped silently. The model refits per fold, so compute scales with fold count, and every fold needs its own embargo. **R-POWER owns the estimand statement.** |
| **D15** | **Row anchoring** | A row is `(cell, T = label_date − H)`. Features from satellite at *T*. **No feature-time HABSOS sample required.** | Removes the double-sampling requirement. H=7: 23,751 → **55,629** rows (verified). H1/H3/H5 gain **7–12×**, which retires the confound that "the skill-vs-horizon decay curve is partly a sample-size curve." **This is a confound fix, not a power fix** — per D14, rows do not tighten CIs. The power lever is D20. |
| **D16** | **Model** | **LightGBM**, monotonic constraints on physically-signed features (`chl↑→risk↑`, `nFLH↑→risk↑`), AUCPR-surrogate objective, pruned to **~33 features by train-side OOB rank** with a pre-declared cut. RF retained as a co-reported baseline. | E-02 was never run — confirmed zero references to lightgbm/xgboost/gbm anywhere in the repo. Native NA handling matters now that 66.7%-imputed chlorophyll is load-bearing (Arm A has no lags to fall back on). Monotonic constraints are the cheapest available regulariser at 333 events and are defensible to a reviewer. `mtry=11/114` currently gives any feature an **8.8%** chance of being considered per split; at 33 features it is 18%. **Terminology:** "boosted random forest" is not a thing — boosting and bagging are different ensembling schemes. Call it GBDT. |
| **D17** | **Arm B lags are continuous** | `log10_max_cells_prior_{7,14}d`, `days_since_last_positive`, `max_severity_prior_14d`, `log10_max_cells_neighbors_prior_7d`. | The current lags are **single bits**. `hab_any_prior_7d` makes 5,000,000 cells/L and 100,001 cells/L identical, and makes 99,999 cells/L identical to open ocean. HABSOS carries `organismQuantity` in cells/L across five orders of magnitude and the datacube discards all of it. This is the single largest information loss in the model and it is exactly Duus et al. (2026)'s dominant predictor. Arm B only — these are HABSOS-derived (D13). |
| **D18** | **Slopes are calendar-day** | Replace `_slope_obsK` with `_slope_Nd`. | D-03, live since the DRAFT. "Change per satellite observation" is not a rate: a 3-observation slope spans 3 days or 30 depending on cloud gaps. Tolerable when the lags did the work; **load-bearing under Arm A**. |
| **D19** | **Rich-persistence baseline is mandatory** | Every arm ships against a persistence baseline built from **the same lag features that arm uses**. | Persistence reaches 70–96% of RF PR-AUC. Enrich Arm B's lags (D17) and you will build an excellent persistence model — which is what a 0.972 ROC-AUC *is*. Duus et al. report no persistence baseline; we will. If Arm B hits 0.90 and rich-persistence hits 0.88, satellite bought 0.02 and we say so. <br><br>**PROMOTED TO LOAD-BEARING (R-PROV, 2026-07-16).** The current persistence baseline is **binary — two distinct values** (`HAB at T`). Its sensitivity is **below 0.80 at every horizon** (0.778/0.710/0.654/0.627/0.523), so it can *never* reach recall 0.80 and `prec_at_recall80` against it is a degenerate operating point, not a comparison. RF-vs-persistence now resolves as a WIN on PR at H=3/5/7/14 — **but that is a win over a two-valued predictor and must not be reported as a headline.** Duus et al.'s implicit baseline is continuous lagged cell counts. **D19's rich-persistence is the only honest bar; until it exists, no persistence claim is publishable.** |

---

## 3. Milestones & gates

### Gate 0 — Is the target measurable? `[PASSED 2026-07-16]`

**Result:** `7,temporal,rf_roc,0.836,0.7999,0.8667,TRUE,30,1000`. **0.900 lies above ci_hi = 0.8667**,
outside the interval by 0.0333. Not marginal. **Rule A — the target is measurable and falsifiable.**
`best_model.rds` md5 unchanged (`3ea9a5fa…`); no retrain. Machinery reused from
`R/07e_pC_bootstrap.R`; RF ROC points reproduce `model_results.csv` to 4 dp at all five horizons.

**What Gate 0 also produced — read these before planning any run:**

- **The cost of 0.900 is larger than everything satellite currently buys.**
  `d_rf_pers_roc` at H=7 = **0.0487 [0.0248, 0.0749]**. The target needs **+0.064**. The RF beats
  persistence by 0.049. **The gap to the target exceeds the total value of the satellite features
  over persistence.** A marginal-feature path to 0.900 does not exist; it has to come from D17's
  continuous lags — which lift persistence too (hence D19).
- **A new resolved result, to be reported with both metrics.** `d_rf_pers_roc` excludes zero at
  **all five horizons**, while on PR-AUC the RF-vs-persistence contrast is **NULL at H=7**. The
  honest sentence is: *the RF carries information beyond persistence — resolvable on ROC at every
  horizon — but not enough to resolve on PR-AUC at the primary horizon.* **Both halves, always.**
  PR-AUC is the pre-registered primary (§9). Leading with the ROC because it resolves is
  metric-shopping and a reviewer will find the PR table.
- **`chl_only` has no persisted per-row predictions**, so it cannot be bootstrapped without a
  retrain. Rows written blank at `n_boot=0` — a gap, not a value. **Every baseline must dump
  per-row predictions at scoring time or it cannot carry a CI** (see D19 — the rich-persistence
  baselines will hit this same wall).

### M0 — Stop the lies `[main]`

- **🔴 SCORER BUG — `R/07_modeling.R:266–314`.** `roc_auc_fn`, `pr_auc_fn`, and
  `precision_at_recall_fn` walk tied rows one at a time, so **within-tie row order changes the
  answer**. Harmless for continuous scores; catastrophic for persistence, which is **binary
  {0,1}**. Confirmed two ways: (i) 5 random shuffles of the same rows give 0.7806–0.7904 while
  natural order gives 0.8213 — *above every shuffle*, i.e. biased upward, not merely noisy;
  (ii) `(sens+spec)/2` computed from `model_results.csv`'s **own confusion matrices** reproduces
  0.8637/0.8270/0.8007/0.7873/0.7287 exactly — the file arithmetically contradicts itself.
  **Fix:** Mann-Whitney U with ties credited 0.5 (ROC); average precision (PR); tie-collapsed
  p@r80. **This is M0, not M2** — M2 is a retrain and would re-corrupt the table.
- **🔴 Re-run `R/07e_pC_bootstrap.R`** with average precision. `model_results.csv` is patched to
  canonical; `bootstrap_cis_pC.csv`'s `d_rf_pers` PR rows are not. **Two disagreeing artifacts are
  in the tree right now** (P-06, regenerated within one task of being fixed). Scoring the frozen
  dump is not a retrain.
- **D-04**: `R/05_environmental_features.R:775` — `&` → `|`. **PATCHED.** The register's framing
  (and mine) was wrong: I said "wind is real, so this is FALSE on every row → 0% placeholder." The
  data says `wind_is_placeholder = 0.3045` — wind is **70% real, not 100%** (`:659`/`:748` set TRUE
  wherever the ERA5 join left NA). The buggy AND rollup therefore read **30.45%**, not 0%. The fix
  makes the honest row-level flag **100%**, because CHIRPS and SMAP are placeholders on **every**
  row. That 100% is itself a disclosure — see the data-honesty note below. No retrain (env rebuild
  only; `model_dataset.parquet` changed in exactly two columns).
- **`renv.lock`**: 34 of 176 packages recorded; **`ranger` — the model — is unlocked**. This is not
  drift, the lockfile is decorative. A clean `renv::restore()` does not install the model.
- **`CLAUDE.md`**: claims commit `21320f7` is "stranded on one laptop" and the remote "lacks the
  bio-optical branch." Both false — it is on `origin/main`.

**Exit:** all three fixed on `main`, pushed. Then branch. Both arms inherit honest flags.

### M1 — The datacube rebuild (`feat/arm-a-portable`)
One rewrite of `R/06_build_datacube.R` producing **two feature sets from one row definition**
(D13, D15, D17, D18). Both arms share splits, folds, seeds, and scorer (A-ARM).

**Exit:** row counts match the verified §4 diagnostic (H=7 Arm A = 55,629 ± clouds); R-STARVE
passes on join cardinality; R-SPLIT passes on embargo + ≥25 km buffer (D-11 ring-1 reach).

### M2 — Model (D16, D19)
LightGBM both arms + rich-persistence baseline per arm + RF co-reported.
**Exit:** A−B with a block-bootstrap CI. If |A−B| < 0.033 the delta is unresolved and *that is the
result* (D14b).

### M3 — GIS risk surface `[co-equal deliverable, not an afterthought]`
Arm A only — Arm B's features are undefined on 99.76% of the grid, so **the portability argument
and the GIS deliverable are the same argument**. Ship at the operating point where the product is
decision-ready (default threshold: 7.1% of shelf flagged at 61% precision). Report the operating
envelope as a finding: at recall 0.80 the model flags 35% of the shelf and the map is useless.
Includes D12 drill-down.

### M4 — Paper
See §10.

> **M3 (transformer) from the previous revision is retired.** See D7/D8.

---

## 4. Repository structure

Unchanged. New environmental sources are **sections of `R/05_environmental_features.R`**
(A=TIGER, B=GEBCO, C=dist-to-shore, D=CHIRPS, E=ERA5, F=SMAP, G=seasonality, **H=SSH**), not new
scripts. `data/raw/` is organised **by domain** (`gis/`, `habsos/`, `satellite/`, `weather/`), not
by product. Every dataset gets a row in `data/metadata/data_sources.md` with the mandated schema.

---

## 5. Data sources

Authoritative table: **`data/metadata/data_sources.md`**. Do not duplicate it here (D-22).

Status summary as of 2026-07-16:

| Source | Status | Note |
|---|---|---|
| HABSOS DwC-A v1.5 | **REAL** | 94,810 cell-day rows, 7,523 positive (7.93%). CC0. |
| MODIS-Aqua L3m (chl, nFLH, Kd490, SST) | **REAL — FINAL** | 5,829/5,829 dates. **Do not re-pull** (~6 h for nothing). |
| Bio-optical (bbp_443, bbp_s, Rrs_667, Rrs_678) | **REAL** | 27,641,118 rows, 0 duplicates, 0 fabricated. |
| ERA5 10 m wind | **70% REAL** | `wind_is_placeholder = TRUE` on **30.45%** of rows (ERA5 join left NA — coastal/edge cells the ~28 km field did not cover). The ledger's "REAL, 65,939/65,939" **overstates** this, the same way it overstates SMAP ("deliberately skipped" vs. actually deferred). A-DOC must reconcile the ledger to the code, not the reverse. |
| GEBCO 2026 bathymetry | **REAL** | `depth_m` is model feature **rank 20**. ⚠️ **NON-COMMERCIAL licence** — unresolved, see §11. |
| TIGER 2023 | **REAL** | `dist_to_shore_m` is feature **rank 18**; 82 county blocks for spatial CV. |
| **CMEMS SSH** | **TO PULL** → Section H | Duus et al.'s only feature that passes the portability test. `sla`, `adt`, `ugosa`, `vgosa`. 2003-01-01 → 2021-12-31. Credential `~/.copernicusmarine/` — **not** `~/.cdsapirc` (C4). |
| CHIRPS precipitation | **PLACEHOLDER — parked** | 403 CrowdSec. Re-triggered *by the parallel pull loop itself* (B11 caused it). The feature would be catchment-integrated lagged runoff, not rain-over-ocean-cell. Low priority. |
| SMAP salinity | **PLACEHOLDER (100%)** | OPeNDAP auth deferred. 40–70 km — broad-context only. The master record's "deliberately skipped" is not what the code says. |

> **Data-honesty disclosure (surfaced by the D-04 fix).** With the honest OR rollup, `IS_PLACEHOLDER`
> is TRUE on **100%** of rows — because **CHIRPS precip and SMAP salinity never landed** (placeholder
> on every row) and **ERA5 wind is missing on 30%**. The modeling docs and the paper's data section
> must carry this. The register's per-source "REAL" claims describe intent, not the parquet. **Rule:
> A-DOC reconciles `data/metadata/data_sources.md` against the actual flag columns before M4, and
> every "REAL" is backed by a `mean(is_placeholder)` command or it is downgraded.**

---

## 6. Agent roster

Canonical names. Do not spawn duplicates. Model assignment and its rationale live in
**`CLAUDE.md § Model assignment`** — not duplicated here.

**Builders (Fable 5):** `env-features` (A5, Section H) · `datacube` (A6 — the rebuild) ·
`modeling` (A7) · `explain` (A8) · `gis` (A9 — **promoted to co-equal**) · `validation` (A10) ·
`doc-citations` (A-DOC) · **`arm-parity` (A-ARM — new)**.

**A-ARM** enforces Arm A/Arm B parity: identical folds, seeds, splits, scorer. D-16 (`ranger`'s
bootstrap is row-order-sensitive; `merge()` reorders `dt`; observed drift ∓0.001–0.006) means an
unmatched control silently drifts by most of an effect at the +/-0.033 floor (D14b).

**Auditors — continuous, on every write, not at milestone gates:**

| Agent | Model | Owns | The failure it exists for |
|---|---|---|---|
| **R-POWER** *(new)* | opus-4-8 | Pre-registration gate | Computes the expected effect against the D14 floor **before** a run. If the effect cannot resolve, **refuse** — or run pre-declared as underpowered. Would have stopped wind, bio-optical, spatial-lag, and cloud-compositing before each burned a week. Also owns: re-deriving D14(a)'s 333 under 7/14/30-day merge rules and reporting the **range**; and the D20 estimand statement. **The floor it gates on is the MEASURED one (D14b, +/-0.033), never a derived one** — the previous revision derived it from sqrt(333) and was wrong. |
| **R-STARVE** *(new)* | **fable-5** | Too-little-data | P-01: *"Every gate checks for too much information. Nothing checks for too little."* D-01 passed R6 **and** R-SPLIT because it wasn't leaking — it was starving, and the starved null read as a clean mechanistic finding. Verifies source-table cardinality on every join. **Judgment work → Fable. Merge-blocking.** |
| **R-SPLIT** | **fable-5** | Leakage | Embargo, ≥25 km buffer (D-11 ring-1 diagonal reach), prevalence confound (D-09). **Unchanged — was already Fable, deliberately. Merge-blocking.** |
| **R-PROV** *(new)* | opus-4-8 | Provenance & single truth | Every number traces to a command. No stale line refs (`07_modeling.R:24` is stale in the register). No second results table (D-19 was deleted; the hazard immediately regenerated as `model_results_bio_inclusive.csv`). Owns D-22. |

**Retired:** `sourcing` (A1), `grid-clean` (A2), `habsos-label` (A3), `sat-features` (A4) — all
complete; re-running A4 costs ~6 h for nothing. `transformer` (A11) — D7/D8.
`R1`–`R6` paired reviewers — folded into R-STARVE and R-PROV.

---

## 7. Execution order

```
Gate 0  ROC-AUC CI  ─────────────────────────────────────────► PASSED 2026-07-16
   │
M0  D-04 · renv.lock · CLAUDE.md  ────► push to main
   │
   ├─► branch feat/arm-a-portable
   │
M1  A6 datacube rebuild (D15 anchor, D17 Arm B lags, D18 slopes)
   │        │
   │        └─► A5 Section H (SSH) ── parallel, independent
   │
   ├─► R-STARVE + R-SPLIT gate ──► merge blocked until pass
   │
M2  A7 LightGBM × {Arm A, Arm B} × {model, rich-persistence, RF}   ◄── A-ARM parity
   │        │
   │        └─► R-POWER gate BEFORE each run
   │
M3  A9 GIS surface (Arm A only) + D12 drill-down     ◄── co-equal, runs parallel to M2
   │
M4  A-DOC source set ──► author writes the paper
```

---

## 8. Feature spec

Live spec. Amended, not replaced.

**Levels:** `chlor_a`, `nflh`, `Kd_490`, `sst` · bio-optical `RBD`, `KBBI`, `bbp_443`, `bbp_s`,
Cannizzaro/Morel discrimination · `depth_m`, `dist_to_shore_m` (**already present — rank 20 and
18**) · ERA5 wind speed/direction/u/v/along-shore/cross-shore · **SSH `sla`, `adt`, `ugosa`,
`vgosa`** (new, Section H).

**Trends (D11, amended by D18):** deltas at 1/3/5/7 d · % change with `pct_change_epsilon` ·
**calendar-day slopes `_slope_{3,5,7}d`** · rolling means/sd · threshold-crossing flags.

**Arm A:** everything above. **Zero HABSOS-derived columns.**

**Arm B (D17):** Arm A + `log10_max_cells_prior_{7,14}d` · `days_since_last_positive` ·
`max_severity_prior_14d` · `log10_max_cells_neighbors_prior_7d`.

**Retired:** `hab_any_prior_{7,14}d` — superseded by D17 in Arm B, removed entirely from Arm A.

**Permanently unavailable:** **FAI** — requires ~859 nm and ~1240 nm, absent from daily MODIS L3m.
Confirmed twice including a live OB.DAAC check. L2 swath processing is a different architecture and
out of scope. Disclosed as a limitation; `nFLH` is the fluorescence discriminator.

**Feature budget (D14/D16):** ~33 features, selected by **train-side OOB rank**, cut pre-declared.
Never `mean_abs_shap` — it is computed on the test set (D-12) and pruning by it is selection
leakage. Note OOB calls only 3/149 dead while SHAP calls 86 — that disagreement is itself a
symptom of 2.2 events/feature, so use ranked OOB with a declared cut, not a deadness threshold.

---

## 9. Evaluation protocol

Live spec. Amended.

**Splits:** random (indicative) · **temporal (primary)**, **rolling-origin CV per D20**, each fold
with its own embargo; the single-2016-cutoff split reported alongside for continuity · spatial,
TIGER county blocks, **≥25 km buffer**, reported with the D-09 prevalence confound stated.

> **Estimand honesty (D20).** Rolling origin estimates *average skill across origins*. The 2016
> cutoff estimates *skill after 2016*. These are different quantities. State which one every
> number is, every time. Swapping them silently to get a tighter interval is the same class of
> error as metric-shopping.

**Metrics:** **PR-AUC primary** and **precision-at-recall-0.80**, because ROC-AUC misleads under
imbalance (Saito & Rehmsmeier 2015, *PLOS ONE* 10(3):e0118432). **ROC-AUC co-reported** — it is
the only axis on which Duus et al. (2026) is readable, and it has been in `model_results.csv` all
along (H=7 = 0.836 [0.7999, 0.8667]).

> **Where ROC and PR disagree, report both.** They already do: RF-vs-persistence resolves on ROC at
> all five horizons (H=7: +0.0487 [0.0248, 0.0749]) and is **NULL on PR-AUC at H=7**. That is a
> real property of the comparison under imbalance, not a reason to pick the flattering axis.

**Baselines:** rich-persistence per arm (**D19**) · chlorophyll-only · RF.
**Every baseline dumps per-row predictions at scoring time.** `chl_only` did not, so its CI cannot
be computed without a prohibited retrain (Gate 0). A baseline without a prediction dump cannot
carry a CI, and per rule 5 that makes every Δ against it UNRESOLVED.

**CIs:** mandatory on every Δ. 30-day block bootstrap, n=1000. **No CI ⇒ UNRESOLVED.**
The measured floor at H=7 under the current split is **±0.033** (40 positive-carrying blocks,
σ ≈ 0.108). Under D20's rolling origin, ~±0.024. **Cite the measured floor, not a derived one.**

**Statistic must match the claim (P-02).** Marginal rates do not test conditional claims.
Default-threshold metrics do not test skill — three separate "findings" were artifacts of this
(persistence "beating" RF; the transformer's recall "advantage"; P0-J "confirmed").

**Threshold sensitivity (not a target change).** Report PR-AUC at 100k / 50k / 10k with **100k as
the pre-registered headline** (D2). This is a robustness check and the opposite of
threshold-shopping. Expected finding, already evidenced by E-06: skill collapses below ~100k
because class-1 recall is **0.000** and class-2 is **0.040** — MODIS cannot separate
low-concentration *K. brevis* from background. That is mechanistically the same wall as the
bio-optical negative and the 19× FP concentration: **three independent lines of evidence, one
cause.**

---

## 10. The paper

**Not** "we hit 0.9." The title the evidence supports:

> *Portable satellite-only harmful-algal-bloom forecasting on the West Florida Shelf: the cost of
> dropping the in-situ network, and the event-count ceiling that bounds every model on this shelf.*

Four contributions, in order of strength:

1. **A−B** — the measured cost of portability. Large (removes 20.1% of SHAP mass), therefore
   resolvable at 333 events, therefore claimable.
2. **D14's ceiling** — ~17.5 blooms/yr, 333 events in the satellite era, ±0.03 floor. Nobody has
   stated the limit on this problem in event units. Every future ML paper on this shelf works under
   it and none of them name it.
3. **The GIS risk surface** — whole-shelf, decision-ready, Arm-A-only. With the operating envelope
   stated.
4. **Four bounding negatives** — wind, bio-optical, spatial-lag, cloud-compositing — now
   re-read through D14 as measurements of one instrument limit rather than four failures.

**On the comparator.** Duus, Elshall, Parsons & Ye (2026) *Environments* 13(5):239,
doi:10.3390/environments13050239, ROC-AUC 0.972. **Decline the comparison on portability
grounds and say why:** their features (Peace/Caloosahatchee discharge, TN/TP, in-situ salinity,
lagged cell counts) require a gauge network and a state monitoring programme; the model cannot
leave SW Florida. Their task is a **regional weekly time series** (~87 positive weeks); ours is a
4,743-cell daily spatial forecast. They report **no persistence baseline** for a model whose
dominant predictor is lagged cell counts and whose target is next-week bloom status. **Arm B is the
in-family point of contact** for anyone who wants the comparison anyway.

---

## 11. Open items

1. **✅ RESOLVED (R-PROV, 2026-07-16) — persistence tie-handling.** Root cause: trapezoidal
   row-walk on a binary score, order-dependent and upward-biased. Canonical = Mann-Whitney
   ties-0.5 / average precision. `model_results.csv` patched in place (15 persistence rows, 3
   columns; every other row byte-identical). **Verdict changes:** RF-vs-persistence PR **flips
   NULL → WIN at H=7 (+0.0659 [+0.0211, +0.1090]) and H=3**; the "persistence beats RF at H=1 on
   p@r80" claim in `PROJECT.md §2.2` is an artifact of a degenerate operating point. ROC unchanged
   (Gate 0 was already canonical). **Residual, now M0:** the scorer functions and the
   `bootstrap_cis_pC.csv` PR rows. See D19 — the flip is a win over a binary baseline and is not
   reportable until rich-persistence exists.
2. **⚠️ GEBCO 2026 is NON-COMMERCIAL (GEBCO ToU).** `depth_m` is feature rank 20 in a model being
   submitted to an IEEE venue. `data/metadata/data_sources.md` flags this as a CRITICAL correction
   (an earlier pass had it as CC BY 4.0) and says *"confirm with venue."* **Still unresolved. This
   is a licensing question, not a technical one, and it is the author's call.**
3. **D14(a)'s 333 is rule-dependent.** 9.4 rows/event indicates thin gappy sampling, which
   *inflates* interval-based event counts — so 333 is likely an **over**count. R-POWER owns the
   7/14/30-day sensitivity. Note this affects the **capacity** limit (feature budget, deep-model
   verdict), **not** the resolution floor — those were conflated in the previous revision and are
   now separate.
4. **Unexplained, carried forward:** the OOB-vs-test-SHAP importance disagreement (the
   sampling-regime hypothesis was refuted by P0-J; 2.2 events/feature is a candidate replacement
   but is untested). E-01a′'s random-split positives with a correct advection signature against a
   null temporal split.
5. **Live defects not yet scheduled:** D-05 (stale DRAFT note, `06_build_datacube.R:73-76`),
   D-06 (no ocean currents — **partially addressed by SSH `ugosa`/`vgosa` in Section H**),
   D-12 (`mean_abs_shap` not yet marked diagnostic-only), D-14 (`prec_at_recall80` empty for all
   15 transformer rows — moot under D8), D-25 (register's line reference is stale).
6. **Uncommitted from Gate 0:** `outputs/tables/bootstrap_cis_pC.csv` +25 rows;
   `R/07f_pC_roc_bootstrap.R` untracked. Left for author review.

---

## 12. Execution mode

**ASAP, maximally parallel.** Run every branch with no unmet dependency at once. Credits are not a
constraint.

> **B11 has one carve-out.** Maximal parallelism is a default, not a law. It is what triggered the
> CHIRPS CrowdSec ban — 5,829 requests fired at once *is* a bot signature. Any endpoint that
> rate-limits gets serial access with backoff, and that is not a violation of this section.

**Work lives in git and the filesystem, not in terminal windows** (C1). This survived one memory
balloon, three window closes, and a garbled terminal with zero loss of committed work. Commit
frequently during long runs — a crash between commits loses more the longer the gap. Push;
the remote has drifted 5 commits behind before.

**Long pulls:** `caffeinate -i`, checkpoint by date, resume rather than restart.

**After any interrupted run:** check for orphaned launchers before dispatching fresh work. The
interrupted bio-optical session left a detached watchdog reparented to launchd that survived
session death and kept relaunching the pull, plus zombie R processes causing a 3-way write race.
