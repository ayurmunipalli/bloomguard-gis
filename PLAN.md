# BloomGuard GIS — Project Plan (`PLAN.md`)

> **This is the operating document for the Claude Code agent team.**
> The team lead and every teammate must read this file in full before taking any action.
> When a decision here conflicts with an instinct, this file wins. When this file is silent, ask the lead — do not improvise on science, data, or tooling.

**Project:** BloomGuard GIS — **forecasting** *Karenia brevis* harmful algal bloom risk _H_ days ahead from the **levels and short-term trends** of satellite/environmental conditions (e.g., a ~10% day-over-day rise in chlorophyll-a), aggregated onto a coastal grid and exported as GIS-ready risk layers. Two modeling stages: **Random Forest first, transformer second.**

**Author context:** Independent high-school research project, mentored by Prof. Jamaal Green (UPenn Weitzman School of Design), targeting an IEEE/URTC-style submission. Realism and honesty matter more than sophistication. A working, well-validated, well-explained grid-based model beats a fragile deep-learning system.

**Scope of the agent team (read this carefully):**
- **The team's root job is three things:** (1) **source** the data, (2) **clean and spatially engineer** it into the datacube, (3) **code and validate the model.** GIS export supports these.
- **The author writes the paper.** No agent drafts abstracts, introductions, related-work, or discussion prose. Agents *produce the material the author writes from* — documented techniques, cited data, tables, and figures — but do not write the manuscript.
- **One dedicated agent (A-DOC) owns citations and technique documentation** across the whole project. See §6.

---

## 0. Agent operating contract (read first)

1. **Follow the milestone gates in §3.** Do not start a milestone until its entry criteria are met. Do not skip ahead because a later task looks interesting.
2. **Write every output to the exact path given in §6.** Paths are contracts between agents. If you change a path, update this file and tell the lead.
3. **Leave a methods trail in every file (mandatory — see §0.1).** The author is writing the paper from your notes. Undocumented work is incomplete work.
4. **Teammates return short summaries to the lead**, not full transcripts: what you did, what file you produced, whether your definition-of-done is met, any blocker.
5. **Never fabricate data or results.** See §1. This is the one rule that ends the project if broken.
6. **When blocked on data access, do not stall silently.** Write exact manual steps to the relevant `manual_downloads.md` and continue with a **clearly-labeled** synthetic placeholder (an `IS_PLACEHOLDER = TRUE` column and a loud README note) so downstream agents can build against the schema.
7. **Definition of "done" is written per agent in §6.** "I wrote some code" is not done. "The output file exists at the specified path, passes its quality checks, notes are written, and the summary reports pass/fail on each check" is done.
8. **Commit at each milestone** via `/commit-push-pr`. Keep secrets, API keys, raw satellite dumps, and model binaries out of git (see `.gitignore` task).

### 0.1 The notes convention (this is how the author writes the paper)

Every script and notebook **must** begin with a header block, and every non-obvious step **must** carry an inline note. A-DOC harvests these into the methods log.

```r
# ============================================================
# FILE: 02_clean_and_grid.R
# PURPOSE: Aggregate HABSOS + feature points onto the coastal grid by date.
# INPUTS:  data/raw/habsos/*.csv, data/processed/study_area_grid.gpkg
# OUTPUTS: data/processed/gridcell_daily.parquet
# TECHNIQUES: sf spatial join (st_contains), Albers EPSG:5070 reprojection,
#             grouped daily aggregation. Ref: Green (2022) RTM gridding.
# CITATIONS: HABSOS (NOAA NCEI); grid method follows mentor's gulf script.
# ============================================================
```

Inline, tag anything the author will need to explain or cite:
```r
# NOTE(paper): 10 km cells chosen to exceed MODIS ~4 km L3 pixel size -> avoids
#              sub-pixel false precision; sits below coarse wind/salinity fields.
# NOTE(cite):  Albers Equal Area (EPSG:5070) used for metric distances.
# NOTE(limitation): HABSOS non-detection != true absence; may be unsampled.
```

Use the same convention in Python/notebooks with `#` comments. A-DOC greps for `NOTE(paper)`, `NOTE(cite)`, and `NOTE(limitation)` — if it isn't tagged, it won't reach the paper.

---

## 1. Non-negotiable guardrails

Hard constraints. Violating any of them invalidates the work.

- **No fabricated data.** If HABSOS, MODIS, ERA5, or CHIRPS can't be pulled, document the blocker and use labeled placeholders. Never present placeholder numbers as real results.
- **No causal claims.** Use "associated with," "predictive of," "correlated with." The model finds patterns; it does not prove mechanism.
- **No "first ever" claims.** Prior work exists (HABNet; NOAA operational HAB forecasting; the mentor's own RTM work). Our contribution is a *reproducible, interpretable, GIS-integrated early-warning workflow on public data* — not a novel model class.
- **No "operationally ready" claims** unless the model survives the hard validation splits in §9. Random-split performance alone ≠ ready.
- **Honest negatives.** A HABSOS non-detection is not proven absence — it can mean nobody sampled. Document this wherever labels are used.
- **Stage order is fixed.** Stage 1 (Random Forest) must be fully working and validated **before** the Stage-2 transformer is trained — the transformer's whole point is to be compared against a solid RF benchmark. The transformer is committed, not optional; only *further* DL variants (e.g., spatiotemporal attention beyond the base transformer) are optional stretch goals.
- **R for the spatial/data layer.** Match the existing codebase and the mentor's toolchain (see §2, D0). Do not silently reintroduce a parallel Python spatial pipeline.

---

## 2. Pinned decisions (do not relitigate)

The lead may change these only with an explicit written rationale logged in `reports/decisions.md`.

| # | Decision | Locked value | Rationale |
|---|----------|--------------|-----------|
| D0 | Primary language for data + spatial work | **R** (`sf`, `sftime`, `stars`, `tmap`, `data.table`, `tidyverse`) | All existing work and the mentor's method are in R. Modeling may use R (`ranger`/`caret`/`tidymodels`) or Python — decided in D7. |
| D1 | Study area | **West Florida Shelf, bounded by 24–31°N, 87–81°W**, defined in code as a bounding box (no hand-drawn polygon needed) | This is the established MODIS *K. brevis* study extent from **Hu et al. (2022)**, *Harmful Algae* 117:102289; matches how the ocean-color community grids the shelf. Optional later refinement: clip to the 200 m isobath if offshore deep-water cells hurt the model. |
| D2 | Positive label threshold | ***K. brevis* > 100,000 cells/L** | Standard bloom-level threshold in prior remote-sensing studies. |
| D3 | Primary target | **Binary** (`HAB = 1` if a cell-day exceeds threshold) | Simplest defensible MVP. Severity/count classes optional later (mentor's RTM paper predicts counts — a stretch goal). |
| D4 | Unit of analysis | **Grid cell × date** (RTM-style), **10 km × 10 km cells**, built from the mentor's gridding method | **Confirmed.** Grid-first matches the mentor's demonstrated workflow and his published paper; 10 km sits just above the ~4 km MODIS L3 pixel (real aggregation, no false precision) and below the coarse wind/salinity fields. |
| D5 | Prediction target & horizon | **Forecast `HAB` at cell _c_, day _T+H_**, using levels + trends observed **through day _T_**. Start with **H = 7 days**; then evaluate H ∈ {1, 3, 5, 7, 14}. | The label is a *future* event → this is genuine forecasting, not nowcasting. See §2.2. |
| D6 | Framing honesty | **"Forecasting" is earned only because the label is future (D5).** Still report skill *as a function of H* and never claim a longer lead than validated. HABSOS sparsity caveat (§1) still holds. | Precision without overclaiming — say the horizon, show the decay. |
| D7 | Modeling progression | **Stage 1 — Random Forest** (`ranger`/`caret`). **Stage 2 — Transformer** (temporal / spatiotemporal). Stage 1 first, Stage 2 always. No separate logistic/GLM modeling tier — the *reference points to beat* (persistence + chlorophyll-only) live in §9. | RF is the mentor's method (Green 2022) and a strong, interpretable anchor; the transformer then tests what modeling temporal sequences/trends adds. |
| D8 | Transformer role | **Committed second modeling stage, not optional.** Operates on per-cell temporal sequences of levels + trend features → future `HAB`. Compared honestly to Stage 1. | The trend-forecasting model; a null result vs. Stage 1 is still a legitimate finding. |
| D9 | Explainability | **SHAP + variable-importance** (Stage 1) and **attention / attribution** (Stage 2, transformer) | Interpretability contribution across both stages; mirrors Green 2022's variable-importance emphasis. |
| D10 | Central data artifact | **Spatiotemporal vector datacube** (`sftime`), cell × date × variables | Serves both stages: flatten to `(cell × date)` rows for Stage 1; slice **per-cell temporal sequences** for the transformer. Mentor's chosen approach (Nov 14). |
| D11 | Trend features are first-class | Every level feature gets companion **rate-of-change features**: absolute deltas, **relative day-over-day % change**, trailing slopes, and **threshold-crossing flags** (e.g., chl-a up >10% DoD for ≥N consecutive days). | The forecasting signal is as much in *movement* as in *level* (author's explicit goal; matches the d/dx(FAI) & chl-ROC notes). See §8. |
| D12 | Intra-cell attention layer | A GIS **drill-down** that, for a flagged 10 km cell, surfaces **where inside the cell the flag-driving conditions concentrate** — down to native ~4 km MODIS pixels, with placement nudged by sub-km static layers (bathymetry, distance-to-coast). **A diagnostic/interpretability overlay, NOT a validated sub-cell forecast.** Built in A9 (M2); must not gate M1. | Coarse cells screen; this narrows *attention* for response/sampling without claiming precision the data lacks. See §2.3 for the honesty rules. |

### 2.1 Study-area and grid decisions (settled)

The unit of analysis is **grid cell × date**, following the mentor's method (in the `gulf` script and in **Green (2022), "The Built Environment and Predicting Child Maltreatment"**): lay a grid over the study area, aggregate point observations into cells, attach features per cell, predict per-cell risk. Both open questions are now resolved:

- **Study area:** the **24–31°N, 87–81°W** bounding box (Hu et al. 2022), defined in code — no QGIS polygon required for the MVP. A2 builds it with `sf::st_bbox()` → `st_as_sfc()`.
- **Cell size:** **10 km × 10 km** (`cellsize = 10000` in Albers EPSG:5070), matching the mentor's script and sitting just above the ~4 km MODIS L3 pixel.

Both are defensible to write up in one sentence: *"Study area defined as the West Florida Shelf (24–31°N, 87–81°W) following Hu et al. (2022), gridded into 10 km cells."* Optional future refinement: intersect the box with the 200 m isobath to drop offshore deep-water cells if they degrade the model.

### 2.2 What "forecasting" means here (the labeling that earns the word)

The target is the bloom status of a cell **_H_ days in the future**, predicted from what we observe **up to and including day _T_**. Concretely, one training example is:

> **Inputs (through day _T_):** feature *levels* at _T_ (chl-a, SST, FAI, Kd490, salinity, wind, …) **and** *trend* features summarizing how each moved over the trailing window (day-over-day % change, 3/5/7-day slope, threshold-crossing flags — see D11/§8).
> **Label:** `HAB` at the same cell on day **_T+H_**.

This is why it is forecasting rather than detection: nothing from day _T+1 … T+H_ is allowed into the features. Two consequences the agents must respect:
- **No look-ahead leakage.** Any feature, rolling mean, or anomaly must be computed from data at or before _T_. A6/A7 must assert this in code.
- **Skill decays with _H_.** Report metrics per horizon; expect the 14-day forecast to be weaker than the 3-day. That decay curve is a *result*, not a failure.

**Levels vs. trends are both predictors, by design.** A cell can be high-risk because chl-a is already elevated (level) *or* because it is climbing fast from a low base (trend). Stage 1 gets both as engineered columns; the transformer (Stage 2) can additionally learn trend structure directly from the input sequence.

### 2.3 Intra-cell attention layer — what it is, and the rules that keep it honest (D12)

The model predicts at the 10 km cell. But once a cell is flagged, we can look *inside* it and show **where the flag-driving conditions concentrate**, to direct response and sampling. This is a real, defensible feature — as long as it is built and labeled as *diagnostic*, not as a finer forecast. The rules:

- **It shows features, not a prediction.** The model earned its skill at the cell level; the drill-down displays the underlying feature field the flag was built from. Label every such view as *"where the flagging conditions concentrate,"* never as a sub-cell risk score. It carries no validated skill below the cell.
- **The floor is ~4 km, not beach-scale.** The finest *bloom-varying* input is the ~4 km MODIS L3 chl-a/FAI pixel (a 10 km cell holds ~4–6 of them). Attention narrows to a hot pixel — a ~16 km² patch, i.e. a stretch of coast — not a specific beach. Do not render below the native pixel; a finer square would be the same pixel value repeated (false precision).
- **Convergence is the signal.** The layer is most trustworthy where **multiple independent inputs agree** on a location — e.g., the elevated ~4 km chl-a pixel sits on the shallow, nearshore corner indicated by the sub-km bathymetry and distance-to-coast layers. Surface that agreement; a lone elevated pixel is weaker evidence than a converging cluster.
- **Static layers bias placement, they are not bloom evidence.** Bathymetry and distance-to-coast are constants — they refine *where within the hot pixel* accumulation is plausible, but they'd point to the same corner with or without a bloom. Use them to nudge attention, not as proof of this event.
- **Levels over trends; short horizon over long.** Prefer sub-cell *level* fields (chl-a, FAI). Pixel-level *trend* fields (day-over-day % change) are noisiest at native resolution (cloud gaps, glint) — the very reason we aggregate to cells — so show them cautiously or not at all. And the drill-down is most meaningful for short horizons / the detection regime; at H=7 the sub-cell field is the *pre-bloom precursor* field, which can drift with wind and current before the bloom lands. State that caveat on long-horizon maps.



## 3. Milestones & gates

### M1 — Stage-1 Random Forest forecasting model (**the paper's core**)
**Entry:** repo scaffolded; `PLAN.md` and `CLAUDE.md` read; study-area polygon available.
**Exit (all required):**
- `data/processed/study_area_grid.gpkg` exists (coastal grid, EPSG:5070, `id_col`).
- `data/processed/habsos_labels.parquet` exists: HABSOS aggregated to cell × date with the binary `HAB` label at horizon _H_ (D5) and a labels summary.
- `data/processed/datacube.*` exists: cell × date × features — **levels *and* trend features (D11)** — joined to the T+H label with **no look-ahead leakage** (§2.2).
- **Random Forest** (`ranger`/`caret`) trained and reported **per forecast horizon** H ∈ {1, 3, 5, 7, 14}, against the **persistence + chlorophyll-only reference baselines** (§9).
- Evaluated under **random, temporal (year), and spatial (held-out counties/regions)** splits, metrics reported for each.
- `outputs/tables/model_results.csv` + confusion matrix / ROC / PR curves + **skill-vs-horizon curve** saved.
- SHAP + variable-importance produced (does level or trend dominate?).
- Every M1 file carries its §0.1 notes; A-DOC has logged the techniques.
**Gate:** the transformer (M3) does not start until M1 exit criteria are met and committed — it needs a benchmark to beat.

### M2 — GIS risk mapping & visualization
**Entry:** a saved, validated Stage-1 model exists (starts off M1; refresh if the transformer later wins).
**Exit:**
- Current best model applied to every grid cell for chosen date(s) → `outputs/gis/hab_risk_grid.gpkg` + `hab_risk_raster.tif`.
- Priority-monitoring-zone layer + coastal-region risk summary.
- Interactive map (`outputs/maps/hab_risk_map.html`) with the layer stack; map states clearly it is a model **forecast** at horizon _H_, not observed blooms.
- **Intra-cell attention drill-down (D12/§2.3):** for flagged cells, a sub-cell overlay showing where the flag-driving features concentrate (native ~4 km pixels + static-layer context), labeled as *diagnostic feature concentration*, not a sub-cell forecast → `outputs/gis/intracell_attention.gpkg` (or a raster/interaction in the HTML map).
- QGIS project file or reproducible `tmap`/`leaflet` script committed.

### M3 — Stage-2 transformer (**committed, not optional**)
**Entry:** M1 complete and committed (validated Stage-1 benchmark exists).
**Exit:**
- Transformer trained on **per-cell temporal sequences** of levels + trend features → forecast `HAB` at T+H.
- Same three splits and same horizons as M1; compared **head-to-head** against baseline + RF in one table.
- Attention/attribution produced for interpretability (D9).
- Honest verdict: if the transformer does **not** beat Random Forest, say so plainly — a null result on this comparison is a legitimate, reportable finding.
- *(Optional stretch:)* spatiotemporal variants (e.g., attention over neighboring cells) only if time remains.
**Gate:** GIS (M2) may be refreshed to use the transformer only if it wins under the *hard* (temporal/spatial) splits, not just random.

---

## 4. Target repository structure

Scaffold this exactly. Empty dirs get a `.gitkeep`. Add a `.gitignore` excluding `data/raw/`, `*.tif`, `*.rds`, `*.pkl`, `.env`, and image-patch dumps.

```text
bloomguard-gis/
  README.md
  PLAN.md              # this file
  CLAUDE.md            # agent behavior rules / repo conventions
  renv.lock            # R dependency lockfile (renv)
  requirements.txt     # only if a Python model/DL step is used
  config.yaml
  .gitignore
  reports/
    decisions.md       # log any change to §2
    methods_log.md     # A-DOC: harvested techniques + citations (feeds the paper)
  data/
    raw/
      habsos/          (+ manual_downloads.md)
      satellite/       (+ manual_downloads.md)
      weather/         (+ manual_downloads.md)
      gis/             (study-area polygon, coastline, bathymetry, counties)
    processed/
      study_area_grid.gpkg
      habsos_labels.parquet
      satellite_features.parquet
      environmental_features.parquet
      datacube.rds            # sftime vector datacube (central artifact)
      model_dataset.parquet   # flattened cell x date table for modeling
      model_dataset.gpkg
    metadata/
      data_sources.md
  R/
    00_config.R
    01_source_data.R          # API pulls where possible
    02_build_grid.R           # study-area polygon -> grid (Green method)
    03_habsos_labels.R
    04_satellite_features.R
    05_environmental_features.R
    06_build_datacube.R       # sftime cube + flatten to model_dataset
    07_modeling.R
    08_explainability.R
    09_gis_export.R
    utils_spatial.R
  python/                     # only if used (DL / any Python model step)
    modeling.py
    dl_patches.py
  outputs/
    models/   figures/   tables/   maps/   gis/
```

> **Why R scripts over notebooks:** the mentor works in scripts; the Nov 15 note (`rbindlist`, parallelizing the water-level-to-csv step) and the `gulf` script are script-based. Notebooks are fine for exploration but the committed pipeline should be sourced `.R` files that run end-to-end.

---

## 5. Data sources (with access reality)

**Every dataset entry in `data/metadata/data_sources.md` must record:** source URL, date accessed, access method, auth required (Y/N), spatial resolution, CRS, temporal coverage, license, and purpose. A-DOC verifies this table is complete before M1 exit. If a pull needs an account or a manual portal, write step-by-step instructions to that folder's `manual_downloads.md` — do **not** block the team.

**Prefer APIs; only download manually when no API exists.** (Author's standing instruction.)

| Dataset | Source | Access | Auth? | Key variables | Resolution | Purpose |
|---|---|---|---|---|---|---|
| HABSOS *K. brevis* cell counts | NOAA NCEI HABSOS | Portal export / API | Manual export likely | lat, lon, date, cell_count, agency, depth | point samples | **Ground-truth labels** |
| MODIS-Aqua Ocean Color L3 | NASA OB.DAAC (`oceandata` API) / GEE | API | **Y** (Earthdata / GEE) | chlor_a, nFLH, Kd490, SST, Rrs bands | ~4.6 km | Satellite features |
| GCOM-C / SGLI L3 SST (V3) | JAXA via GEE catalog | GEE API | **Y** | sea surface temperature | ~4.6 km | SST source (per Sept 23 notes) |
| Sentinel-3 OLCI | Copernicus / GEE | API | **Y** | radiance bands, chl ratios, turbidity | ~300 m | Higher-res satellite (optional) |
| CHIRPS precipitation | UCSB / GEE | API | N–Y | rainfall, rainfall anomaly | ~5 km | Rainfall/runoff proxy |
| Wind (ERA5 or CCMP) | Copernicus CDS (`cdsapi`) / RSS | API | **Y** (CDS key) | wind speed/direction | ~0.25° | Mixing/upwelling, bloom transport |
| SMAP sea-surface salinity | RSS / PODAAC | API | **Y** (Earthdata) | salinity | ~40–70 km | Stratification/river-discharge proxy |
| Bathymetry / coastline | GEBCO / NOAA | download | N | depth, shoreline | grid/vector | Distance-to-shore, depth features |
| County/region boundaries | US Census TIGER | download | N | polygons | vector | GIS zoning + spatial splits |

**Access links (from author's notes):** NOAA NCEI HABSOS landing page; NASA OB.DAAC `oceandata` file-search API + Earthdata login; CHIRPS (UCSB CHC); SMAP salinity (oceansciences.org); JAXA GCOM-C SST (GEE catalog). A-DOC records the exact URLs and access dates.

> **Resolution reality check (add to limitations):** MODIS pixels are ~4.6 km, so a 10 km grid cell spans only a few pixels. Treat cell statistics accordingly and don't imply sub-km precision. Salinity (SMAP) is far coarser — flag it as a broad-context feature, not a fine-scale one.

> **Label/feature cadence mismatch (from Sept 23 notes):** labels (HABSOS) are effectively daily/event-based; some features arrive at coarser cadence. Where a feature is coarser than daily, forward/backward-fill within its valid period and **flag filled rows** (`feature_filled = TRUE`). Never let a fill silently masquerade as an observation.

> **Sandbox note:** these pulls need network egress and may hit blocked domains under the session sandbox. Run heavy downloads in a non-sandboxed pane, then let sandboxed teammates read the local files.

---

## 6. Agent roles (inputs → outputs → done → checks)

Ordered by dependency. Each agent's model is noted. A-DOC runs continuously alongside the others.

### A-DOC · documentation & citations *(model: sonnet-5)* — **runs the whole project**
The single agent responsible for citing all data and documenting all techniques used across the project. **This is the only "writing" agent, and it does not write the paper** — it produces the sourced raw material the author writes from.
- **In:** every file the other agents produce; the attached PDFs (planning doc, Green 2022 RTM paper, the author's literature-review notes); the `NOTE(...)` tags in code.
- **Out:**
  - `data/metadata/data_sources.md` — complete, verified source table (see §5 required fields).
  - `reports/methods_log.md` — running log of every technique used, in plain language, each tied to (a) the file that uses it and (b) a citation (a real paper from the PDFs, or "novel to this project / mentor's method").
  - `paper/references.bib` — every cited source as a resolvable DOI/URL. **No invented citations.**
  - `reports/technique_index.md` — table mapping technique → where used → source paper → `NOTE(paper)` excerpts.
- **Done:** every dataset in `data_sources.md`; every `NOTE(paper)`/`NOTE(cite)` harvested; every technique traceable to a file and a citation; every `.bib` entry resolves.
- **Checks:** no invented citations; no technique in the code missing from `methods_log.md`; flags any claim in code comments that overstates what the data supports.
- **Explicitly not doing:** abstract, introduction, related-work prose, discussion. The author writes those.

### A1 · sourcing — Data Sourcing *(model: sonnet-5)* ← **M1 critical path, do first**
- **In:** §5 dataset table; access links from notes.
- **Out:** raw files under `data/raw/**`; `manual_downloads.md` in each folder for anything not API-pullable; `R/01_source_data.R` (+ `python/` only if a dataset truly needs it).
- **Done:** every dataset either pulled via API or documented with exact manual steps; each pull logged (URL, date, auth) for A-DOC.
- **Checks:** APIs preferred over manual; no credentials committed; placeholder files clearly labeled if a source is blocked.

### A2 · grid+clean — Study Area, Grid & Cleaning *(model: sonnet-5)* ← **the spatial heart**
- **In:** the study-area bounding box **24–31°N, 87–81°W** (defined in code, D1) + raw point data from A1.
- **Out:** `data/processed/study_area_grid.gpkg`; cleaned per-variable spatial tables.
- **Done:** build the box with `sf::st_bbox()` → `st_as_sfc()` (WGS84), reproject to Albers **EPSG:5070**, then grid via the mentor's method (`st_make_grid`, `cellsize = 10000`, `id_col`); points converted from WGS84 (EPSG:4326) and spatially joined to cells; date-time reduced to date; per-cell/per-date aggregation as in the `gulf` script.
- **Checks:** consistent CRS on every join; grid covers the full study area; aggregation counts sane; `NOTE(paper)` on cell-size choice and projection rationale.

### A3 · labels — HABSOS Labeling *(model: sonnet-5)*
- **In:** cleaned HABSOS points + the grid from A2.
- **Out:** `data/processed/habsos_labels.parquet` + a labels summary.
- **Done:** *K. brevis* aggregated to cell × date; binary `HAB` per D2; positive/negative cell-day counts reported.
- **Checks:** label balance reported; the "non-detection ≠ absence" caveat written into the summary and tagged `NOTE(limitation)`.

### A4 · sat-features — Satellite Features *(model: sonnet-5)*
- **In:** grid + label cell-days from A2/A3.
- **Out:** `data/processed/satellite_features.parquet` (+ patches only if M3 later needs them).
- **Done:** per cell × date, satellite features over T−1/3/5/7/14 windows; rolling means; SST anomaly; cloud/quality filtering; **filled rows flagged**.
- **Checks:** CRS consistent; date range documented; cells with no usable imagery flagged, not zero-filled silently.
- **⚠️ Storage — stream-and-discard (mandatory, do NOT bulk-download first):** MODIS L3 is served as **global daily files** with no server-side bbox subsetting, so a naïve "download the whole 2003–2025 archive, then process" run would stage **300–500 GB** and crash a limited disk mid-run. Instead, process **one unit at a time**: (1) download one day's global file → (2) clip to the D1 box (24–31°N, 87–81°W) → (3) aggregate to the 10 km grid → (4) append cell-rows to the feature table → (5) **delete the global file** → next day. Peak disk stays ~one file (~15 MB) + the small growing Parquet, not the full archive. Make the loop **resumable** (checkpoint by date so a re-run skips days already written) and idempotent. For sources that support server-side bbox subsetting (**ERA5** via `area:`, **CHIRPS**), request the Gulf box directly and skip the global-download step entirely. Log peak disk use in the run summary.
- **Note (for D12 drill-down):** the modeling table stays **cell-level** — do *not* bloat the datacube with per-pixel rows. Instead, keep the **native ~4 km feature rasters retrievable** (retain source files or record an exact re-pull recipe) so A9 can re-derive intra-cell pixel values **only for the date(s) being mapped**. (Note this is *selective* retention of a few mapped dates — it does not conflict with stream-and-discard, which governs the full-archive pass.)

### A5 · env-features — Environmental & Geographic Features *(model: sonnet-5)*
- **In:** grid + labels + satellite features.
- **Out:** `data/processed/environmental_features.parquet`.
- **Done:** wind (speed/dir + along/cross-shore), precip history, salinity, distance-to-shore, bathymetry, seasonality (month + day-of-year sin/cos) per cell × date.
- **Checks:** one row per cell-day; missing-data report; coarse features (salinity) flagged as broad-context.

### A6 · datacube — Build the Datacube *(model: opus-4-8)*
- **In:** labels + satellite + environmental features.
- **Out:** `data/processed/datacube.rds` (`sftime` vector cube) **and** the flattened `model_dataset.parquet` / `.gpkg`.
- **Done:** all layers joined **on date via inner/left joins** (not one giant outer join — per Sept 25 mentor guidance), then combined across grids (`rbindlist`-style) into the cube; **trend features (D11/§8-B) computed here** from the per-cell time series; **T+H labels attached** with a leakage assertion (§2.2); flatten produces one clean row per cell × date for Stage 1 **and** exposes **per-cell ordered sequences** for the Stage-2 transformer.
- **Checks:** no join blow-up from many-to-many; row counts reconcile; **no look-ahead** — assert every feature timestamp ≤ _T_ and every label timestamp = _T+H_; **spatial-autocorrelation flag** — mark clusters of adjacent cells so A7/A11 prevent leakage; cube slices back to the grid for mapping.

### A7 · modeling — Stage-1 Random Forest *(model: opus-4-8)* ← **M1 exit owner**
- **In:** `model_dataset.parquet` (levels + trend features + T+H labels).
- **Out:** `outputs/models/best_model.rds`, `outputs/tables/model_results.csv`, confusion/ROC/PR figures, **skill-vs-horizon curve**.
- **Done:** **Random Forest** (`ranger`/`caret`) trained and reported **per forecast horizon** H ∈ {1,3,5,7,14}, against the persistence + chlorophyll-only reference baselines (§9); evaluated under §9's three splits.
- **Checks:** **no look-ahead leakage** (§2.2) *and* no target-defining features; adjacent cells don't straddle train/test (grouped/spatial splits); **prioritize recall + PR-AUC** (a missed bloom > a false alarm); report the performance *drop* under temporal/spatial splits **and** the decay across horizons honestly.

### A8 · explain — Stage-1 Explainability *(model: opus-4-8)*
- **In:** best Stage-1 model + datacube.
- **Out:** `outputs/figures/shap_summary.png`, `outputs/tables/top_features.csv`, `outputs/tables/variable_importance.csv`.
- **Done:** SHAP + variable-importance (à la Green 2022); top predictors described in environmental terms; **explicitly report whether *levels* or *trends* carry more signal** (this is a headline question for the author's forecasting claim). (Transformer attribution lives in A11.)
- **Checks:** "associated with," never "causes"; note if top features are just proxies for chlorophyll.

### A9 · gis — GIS Risk Mapping *(model: sonnet-5)* ← **M2**
- **In:** current best model (Stage-1 first; swap to transformer only if it wins the hard splits) + feature pipeline + **native-resolution feature rasters for the mapped date(s)** (from A4; see note) + static sub-km layers (bathymetry, distance-to-coast).
- **Out:** `hab_risk_grid.gpkg`, `hab_risk_raster.tif`, `priority_monitoring_zones.gpkg`, `outputs/gis/intracell_attention.gpkg`, `outputs/maps/hab_risk_map.html`, QGIS project or `tmap`/`leaflet` script.
- **Done:** model applied per cell for chosen date(s); identical feature pipeline reused; interactive map has the full layer stack. **Intra-cell attention drill-down (D12/§2.3):** for flagged cells, re-derive the native ~4 km feature pixels within the cell for the mapped date, render a sub-cell feature-intensity overlay, and highlight *convergence* (elevated pixel ∩ shallow/nearshore static context). Prefer level fields; show pixel-level trend fields cautiously or omit.
- **Checks:** CRS consistent; legends/titles/probability scale present; map is labeled a **forecast at horizon _H_**, states which model produced it, and makes clear it is model output, not observed blooms. **The drill-down is labeled *"where flagging conditions concentrate" (diagnostic), never a sub-cell risk score*; nothing rendered below the native ~4 km pixel; long-horizon maps carry the precursor-drift caveat (§2.3).**

### A10 · validation — Validation & Error Analysis *(model: opus-4-8)*
- **In:** model outputs + held-out HABSOS cell-days.
- **Out:** `outputs/tables/error_analysis.csv`; a limitations bullet list (facts, not prose) for the author.
- **Done:** false pos/neg characterized by season/geography/data-availability; compared against a **chlorophyll-only baseline**.
- **Checks:** **gate** — if the model doesn't beat chlorophyll-only, say so plainly; limitations captured as `NOTE(limitation)` for A-DOC.

### A11 · transformer — Stage-2 Transformer (**committed, M3**) *(model: fable-5)*
- **In:** the datacube as **per-cell temporal sequences** (levels + trend features through _T_) + the T+H labels; the Stage-1 results table to beat.
- **Out:** `outputs/models/transformer.*`, transformer rows appended to `outputs/tables/model_results.csv`, attention/attribution figures, a head-to-head comparison table.
- **Done:** temporal (or spatiotemporal) transformer trained → forecast `HAB` at T+H; evaluated on the **same horizons and same three splits** as Stage 1; compared directly to baseline + RF.
- **Checks:** **no look-ahead leakage** in sequence construction (§2.2); same grouped/spatial splits as A7 so the comparison is fair; **honest verdict** — if it doesn't beat RF under the hard splits, report that plainly; guard against overfitting (dropout, early stopping, class weighting rather than naive oversampling — cf. the author's ADASYN notes).
- **Spawns after M1 is committed** (needs the Stage-1 benchmark); may run in parallel with A9 GIS.

---

## 7. Execution order (dependency graph)

```
scaffold repo ──> A1 sourcing ──> A2 grid+clean ──> A3 habsos-labels ─┐
                                        │                              │
                                        ├──> A4 sat-features ──────────┤
                                        └──> A5 env-features ──────────┤
                                                                       v
                                              A6 datacube ──> A7 modeling (Stage 1) ──> A8 explain
                                                                   │
                                                                   ├──> A10 validation
                                                                   ├──> A9  gis (M2, off best model)
                                                                   └──> A11 transformer (Stage 2 / M3, committed) ──> refresh A9 if it wins

A-DOC ── runs continuously, consuming every file above and the PDFs ──> methods_log.md + references.bib + data_sources.md
```
**Rule:** A7 cannot begin until `model_dataset.parquet` passes A6's checks. A9 cannot begin until A7 produces a validated best model. A-DOC never blocks anyone but must be current before each milestone commit.

---

## 8. Feature spec (reference for A4/A5/A6)

Features come in two families — **levels** (the value at day _T_) and **trends** (how that value has been moving through _T_). Both are predictors by design (D11, §2.2). Everything below must be computed from data **at or before _T_** — no look-ahead.

**A. Level features (value as of _T_)**
- *Satellite:* chlor_a mean + max; SST mean + monthly anomaly; **nFLH** (fluorescence) and **FAI** (floating-algae index) — *distinct* indices, compute and label each correctly; Kd490 (water clarity); Rrs band ratios; turbidity proxy.
- *Meteorological/ocean:* wind speed, direction, along-shore + cross-shore components; precip over prior 3/7/14 days; heavy-rain indicator; sea-surface salinity (broad-context, coarse).
- *Coastal geography (static):* distance to coast; distance to nearest river mouth; bathymetry; cell centroid lat/lon; county/region.
- *Seasonality:* month encoding; day-of-year sin/cos.

**B. Trend / rate-of-change features (first-class — D11)**
For each continuous level feature _x_ (especially chl-a, FAI, nFLH, SST, Kd490):
- **Absolute deltas:** _x_T − x_{T−k}_ for k ∈ {1, 3, 5, 7}.
- **Relative day-over-day % change:** _(x_T − x_{T−1}) / x_{T−1}_, plus k-day % change — this is the "10% DoD increase in chlorophyll" signal, stated explicitly.
- **Trailing slope:** linear-fit slope over 3/5/7-day windows (robust to single-day noise/cloud gaps).
- **Acceleration (optional):** second difference, to catch blooms that are *speeding up*.
- **Threshold-crossing flags:** binary indicators such as "chl-a rose >X% DoD for ≥N consecutive days" and "FAI slope above τ over a k-day window" — directly interpretable for the author's write-up and for decision-makers.
- **Rolling context:** 3-day & 7-day rolling means and rolling std (volatility).
- **Local spatial gradient:** difference vs. the mean of neighboring cells (is this cell an emerging hotspot?).

**C. Historical / spatial-lag**
- Bloom in an adjacent cell in prior 7 days; nearby positive count in prior 14 days.

> **Guard against divide-by-zero / instability** in % change when _x_{T−1}_ ≈ 0 (common for chl-a in clear water): use a small epsilon or a log-ratio, and flag it in the notes. **Cloud gaps** make raw day-over-day differences noisy — prefer slopes over gappy windows and record how gaps were handled (`NOTE(paper)`).
> **For the transformer (Stage 2):** the raw per-cell sequence of level features is fed directly, so the model can learn trend structure itself; still include the engineered trend columns from B so the two stages are compared on equal footing where useful.

---

## 9. Evaluation protocol

- **Metrics:** accuracy, precision, recall, F1, ROC-AUC, PR-AUC, confusion matrix. **Report recall, PR-AUC, and false-negative rate first** — for early warning, a miss is worse than a false alarm.
- **Report per forecast horizon.** Every metric is reported for each H ∈ {1,3,5,7,14}, and the **skill-vs-horizon curve** is a required figure — it shows how far ahead the forecast stays useful. Expect and document decay.
- **Splits (report all three):** (1) random; (2) temporal — train earlier years, test later; (3) spatial — hold out coastal regions/counties. Use grouped splits so spatially adjacent cell-days don't leak across train/test. For the **temporal** split, this is the honest test of forecasting skill.
- **Two-stage comparison:** reference baselines (persistence, chlorophyll-only) vs. **Random Forest (Stage 1)** vs. **transformer (Stage 2)** reported **in one table**, same horizons, same splits. State plainly whether the transformer's added complexity buys added skill over the RF.
- **Honesty gate:** if a model only works under the random split, state plainly it does not generalize temporally/spatially — do not headline the random-split number.
- **Baseline to beat:** (a) a **persistence/naive baseline** ("no change from _T_") — the first thing any forecast must beat — and (b) a chlorophyll-a-only classifier. If BloomGuard doesn't beat both, that is the finding.
- **Optional (mentor-aligned):** if a count/severity target is pursued later, report RMSE and PAI as in Green (2022) alongside classification metrics.

---

## 10. Deliverables checklist (agent-produced material the author writes *from*)

- [ ] Complete, verified `data_sources.md` — **A-DOC**
- [ ] `methods_log.md` + `technique_index.md` (every technique → file → citation) — **A-DOC**
- [ ] `references.bib`, all entries resolving — **A-DOC**
- [ ] Study-area grid + datacube — **A2/A6**
- [ ] End-to-end R pipeline in `R/` — **A1–A6, A9**
- [ ] Stage-1 results table (RF vs. reference baselines) per horizon + confusion/ROC/PR figures + **skill-vs-horizon curve** — **A7**
- [ ] SHAP + variable-importance; levels-vs-trends finding — **A8**
- [ ] Error analysis + limitations facts — **A10**
- [ ] GIS risk (forecast) layers + interactive map — **A9**
- [ ] Intra-cell attention drill-down overlay (diagnostic; D12/§2.3) — **A9**
- [ ] Transformer + head-to-head comparison table + attention/attribution — **A11**

**Not on this list, by design:** abstract, introduction, related-work, methodology prose, discussion, conclusion. **The author writes the paper.**

---

## 11. Six-week timeline, risks & backups

| Week | Focus | Owner(s) |
|---|---|---|
| 1 | Scaffold; study-area polygon; source data; HABSOS labels; start `data_sources.md` | A1, A2, A3, A-DOC |
| 2 | Grid + satellite feature extraction (MODIS first) | A2, A4 |
| 3 | Environmental + **trend features** + datacube (levels, trends, T+H labels, per-cell sequences) | A5, A6 |
| 4 | **Stage 1:** Random Forest, per-horizon, all-split eval + SHAP → **M1 done** | A7, A8 |
| 5 | GIS forecast layers + interactive map + error analysis → **M2 done** | A9, A10 |
| 6 | **Stage 2:** transformer + head-to-head comparison → **M3 done**; A-DOC final methods pass | A11, A-DOC |

**Risks & backups:** GEE/Copernicus/Earthdata access blocked → downloadable MODIS L3 rasters or shrink study area/time span. **Disk fills during satellite pull** → this is expected if bulk-downloading; A4's stream-and-discard loop is mandatory (process one day, aggregate, delete raw), so peak disk stays tiny; if still tight, point the download dir at external/synced storage. Too few positives → widen the box or lengthen the year range. Feature extraction too slow → MODIS-only, parallelize the per-day pulls (Nov 15 note). Datacube join blows up → revert to inner/left joins on date only, sample points as in the `gulf` script. **Transformer underperforms or stalls** → ship Stage 1 + GIS as the complete result; the transformer comparison stands as a finding either way (Stage 1 is the paper's core, so the project is never blocked on Stage 2). **Too few positives at long horizons** → shorten H; a solid 3-day forecast beats a broken 14-day one.

---

## 12. First tasks (do tonight/tomorrow, in order)

1. **Lead:** scaffold the §4 repo (dirs + `.gitkeep` + `.gitignore` + `renv` init + `config.yaml` + `README.md` + `CLAUDE.md`). Commit.
2. **A1 sourcing:** stand up API pulls for HABSOS + MODIS; for anything not API-pullable, write `manual_downloads.md`. Log every source for A-DOC.
3. **A2 grid+clean:** define the study-area box in code (**24–31°N, 87–81°W**, Hu et al. 2022); build the grid with the mentor's method (`EPSG:5070`, `cellsize = 10000`, `id_col`). No QGIS step; cell size and extent are locked (D1/D4).
4. **A3 labels:** produce `habsos_labels.parquet` with binary labels + summary; report positive/negative cell-day counts.
5. **A-DOC:** open `data_sources.md`, `methods_log.md`, and `references.bib`; seed the citation list from the attached PDFs (Green 2022 + the literature-review notes).
6. **Gate check:** modeling (**A7**) does **not** begin until `model_dataset.parquet` exists and passes A6's checks. Hold the line.

> When each first task is done, report to the lead in the standard format (did / file produced / done-criteria pass-fail / blocker), then `/commit-push-pr`.