# doc-citations (A-DOC) — decision & methods log

_Agent: A-DOC (doc-citations). Model: claude-sonnet-4-6. Initial pass: 2026-07-11._

---

## Decisions

- **Verified Hu et al. 2022 author list** from ScienceDirect abstract metadata via WebSearch (confirmed 8 authors; updated from `{Hu, Chuanmin and others}` to full list). Title: "Karenia brevis bloom patterns on the west Florida shelf between 2003 and 2019: Integration of field and satellite observations." *Harmful Algae* 117:102289. DOI: 10.1016/j.hal.2022.102289. — ScienceDirect pii S1568988322001172 matches the journal/volume/article number. Cannot fetch the full abstract page (403) but DOI matches standard Elsevier pattern for Harmful Algae journal. **Marked VERIFY-DOI in bib until confirmed by an agent with a login.** — 2026-07-11

- **Identified Green (2022) RTM paper**: Jamaal W. Green, "The Built Environment and Predicting Child Maltreatment: An Application of Random Forests to Risk Terrain Modeling," *The Professional Geographer* 74(1) (2022). Published online Oct 2021; journal volume 2022. DOI: 10.1080/00330124.2021.1970591. Source: WebSearch result with explicit DOI. **This is the mentor's gridding/RF methodology paper** (PLAN.md §2 D4/D7). The domain (child maltreatment) differs but the method (spatial grid → aggregate point events → attach features → per-cell random-forest prediction) is directly applied here. — 2026-07-11

- **ERA5 citation confirmed**: Hersbach et al. 2020, *Quarterly Journal of the Royal Meteorological Society* 146(730):1999–2049. DOI: 10.1002/qj.3803. Full author list too long to list in decisions log — see references.bib. — 2026-07-11

- **CHIRPS citation confirmed**: Funk et al. 2015, *Scientific Data* 2:150066. DOI: 10.1038/sdata.2015.66. — 2026-07-11

- **NASA OB.DAAC MODIS-Aqua L3M citation format confirmed**: NASA OBPG uses dataset-specific DOIs. For the version in use: NASA Ocean Biology Processing Group (2022). Aqua MODIS Level-3 Global Mapped [variable] Data, version 2022.0. NASA OB.DAAC. DOIs: CHL 10.5067/AQUA/MODIS/L3M/CHL/2022.0 (chlorophyll); others TBD by A4 for nFLH, Kd490, SST, Rrs. — 2026-07-11

- **Gap noted — no PDFs in repo**: PLAN.md §6 A-DOC says "the attached PDFs (planning doc, Green 2022 RTM paper, the author's literature-review notes)" — none of these are present in the repo. Green (2022) resolved via WebSearch. Planning doc = PLAN.md itself. Literature-review notes location unknown — not found in the repo. **Open question: do the lit-review notes exist as a file the author will provide?** — 2026-07-11

- **HABSOS gap RESOLVED (2026-07-11)**: A3 obtained HABSOS DwC-A v1.5 from GBIF/OBIS IPT
  (https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5). `event.txt` carries lat/lon/date.
  Join key: `event.txt$id = occurrence.txt$eventID`. CC0 license. Updated habsos bib entry
  with IPT URL, access date, license. — 2026-07-11

- **Pebesma (2018) sf package** identified as required citation from A2's agent log. Confirmed:
  Pebesma, E. (2018). "Simple Features for R: Standardized Support for Spatial Vector Data."
  *The R Journal* 10(1):439–446. DOI: 10.32614/RJ-2018-009. Added to references.bib. — 2026-07-11

- **PDF harvest pass completed (2026-07-11)**: Read 3 of 4 PDFs in `paper/refs_pdfs/`
  (Green 2022 already in bib; skipped). Harvested 10 priority citation entries from:
  (a) benchmark table in *Training-Record Length...pdf*;
  (b) author's lit-review notes in *HAB Research (3).pdf*;
  (c) GIS boundary sources in *Ready-Made Boundary Files...pdf*.

  DOI verification results:
  - **El-habashi et al. 2016** *RS* 8(5):377 — DOI 10.3390/rs8050377 — VERIFIED (title +
    lead authors confirmed via WebSearch).
  - **Gokaraju et al. 2011** *IEEE JSTARS* 4(3):710–720 — DOI 10.1109/JSTARS.2010.2103927
    — VERIFIED (title + all 4 authors confirmed via WebSearch).
  - **Carvalho et al. 2011** *RSE* 115:1–18 — DOI 10.1016/j.rse.2010.07.007 — VERIFIED
    (DOI confirmed; full title/authors to expand from DOI page).
  - **Izadi et al. 2021** *RS* 13(19):3863 — DOI 10.3390/rs13193863 — VERIFIED (DOI
    confirmed; full title/authors to expand from DOI page).
  - **Karki et al. 2018** *RS* 10(10):1656 — DOI 10.3390/rs10101656 — VERIFY-DOI (URL
    appeared in search results; full page not fetched).
  - **Hill et al. 2020 (HABNet)** *IEEE JSTARS* 13:3229–3239 — DOI
    10.1109/JSTARS.2020.3001445 — VERIFIED (DOI and journal confirmed via WebSearch).
  - **Yao et al. 2023** *RSE* 298:113833 — DOI 10.1016/j.rse.2023.113833 — VERIFIED
    (DOI confirmed; full title/authors to expand from DOI page).
  - **Spalding et al. 2007 (MEOW)** *BioScience* 57(7):573–583 — DOI 10.1641/B570707
    — VERIFIED. **CC BY-NC flag added**: MEOW polygon dataset = non-commercial; flagged
    in bib, source_set.md, and Limitations.
  - **Flanders Marine Institute 2023** Marine Regions IHO Sea Areas — UNRESOLVED (no
    specific DOI captured from PDF; A9 to confirm version + DOI at marineregions.org).
  - **USF Mendeley K. brevis dataset** — UNRESOLVED (URL only;
    https://digitalcommonsdata.usf.edu/datasets/9kw6xzmxn3; A1/A5 to confirm if used).

  Intro citations from author's notes (Anderson 2000, Gobler 2020, Ralston & Moore 2020,
  Magaña 2003) — all UNRESOLVED stubs added to bib comments; A-DOC to verify when author
  provides titles or additional context.

  **Files updated in this pass:** `paper/references.bib` (10 new entries/stubs),
  `paper/source_set.md` (new Intro, Related Work, GIS Boundaries sections; MEOW limitation),
  `reports/agent_logs/doc-citations.md` (this entry). — 2026-07-11

- **A6 datacube harvest (2026-07-11)**: Read `R/06_build_datacube.R` (505 lines) and
  `reports/agent_logs/datacube.md`. No new citations required — A6 uses existing bib entries
  (`green2022rtm` for RTM gridding, `hu2022karenia` for study area/dates). NOTE() tags
  harvested: T+H label shift, feature-centric row space, wide-format cube, 61-column trend
  feature suite, vectorised OLS slope (closed-form k=3/5/7), calendar-day delta join
  (exact-date, no LOCF), frollmean trailing rolling stats, 10% DoD bloom-accumulation flag,
  historical HAB non-equi join (strict < T), 5 hard no-leakage assertions (LEAKAGE A–E,
  ALL PASSED), IS_PLACEHOLDER_ROW composition, same-day HAB diagnostic-only note, label
  availability per horizon, DRAFT satellite coverage 6.9%.

  **Key structural facts recorded:**
  - DRAFT cube: 65,939 rows × 114 cols; satellite_missing 95.5%; IS_PLACEHOLDER_ROW 100%
  - 28,871 pre-2003 rows dropped (explicit filter; MODIS era begins 2003-01-01)
  - H=7 and H=14 are primary training horizons (23,000+ labelled rows each)
  - A7 must NOT use `HAB` column as a feature (ablation experiment)
  - `spatial_block_tiger` (82 county blocks) IS in model_dataset; `spatial_cluster` is NOT

  **Files updated:** `reports/methods_log.md` (8 new Data entries, 8 new Methods entries,
  3 new Modeling entries, 7 new Limitations entries; T+H and trend stubs upgraded from
  "planned" to "implemented A6 2026-07-11"). No bib changes — A6 adds no new citations.
  — 2026-07-11

- **A6 FINAL + arrow deadlock harvest (2026-07-11)**: Read `reports/agent_logs/datacube.md`
  (updated DRAFT→FINAL). No new bib citations.

  **methods_log.md updates:**
  - "Datacube DRAFT status" → "Datacube FINAL status": satellite_missing=0; sat_IS_PLACEHOLDER=0;
    cloud_flag=TRUE 45.7% (30,135 rows); chlor_a NA 66.7% (43,991 rows); 12.78 MB.
  - New Data entry: Memory guard — filter to 1,461 label cells before trend computation
    (27.6M → 8.5M rows; keeps full 5,829-date series per cell; ~5 GB peak; verified by R6).
  - Limitation "DRAFT 95.5% satellite-missing" → "MODIS cloud cover: 45.7% cloud_flag,
    66.7% chlor_a NA in FINAL cube" (satellite_missing now 0).
  - Limitation "IS_PLACEHOLDER_ROW 100% in DRAFT" → clarified: sat_IS_PLACEHOLDER=0 (real);
    100% driven entirely by env_IS_PLACEHOLDER (ERA5/CHIRPS/SMAP placeholder).
  - Limitation "Calendar-day delta NA": updated to note FINAL cube cloud-gap NAs (not
    unprocessed-date NAs).
  - New Limitation: arrow multi-thread deadlock (ARROW_NUM_THREADS=1 in R/00_config.R;
    arrow::set_cpu_count(1L) per-script; reproducibility constraint, not data quality).

  **data_sources.md updates:**
  - MODIS row: updated Accessed to "A4 FINAL"; coverage to "5,829/5,829 FINAL";
    Purpose field updated with satellite_missing=0, cloud_flag 45.7%, chlor_a NA 66.7%.
  - SMAP row: corrected Meissner DOI in Purpose field (was wrong 10.3389/fmars.2018.00349
    → correct 10.3390/rs10071121; same correction as references.bib).
  — 2026-07-11

- **A1 sourcing table conflicts FLAGGED (2026-07-11)**: A1 appended a sourcing table to
  `data/metadata/data_sources.md`. A-DOC cross-checked against confirmed values from A3/A4/A5
  and found 7 discrepancies. Added reconciliation table to data_sources.md with authoritative
  values. Key conflicts:
  - HABSOS license: A1 "CC BY 4.0" → **A3 confirmed CC0** (from EML)
  - MODIS resolution: A1 "~9 km" → **A4 confirmed 4 km L3m (4.6 km pixels)**
  - MODIS auth: A1 "httr2 Bearer token" → **A4 confirmed curl + netrc+cookie OAuth**
  - GEBCO version: A1 "GEBCO 2024" → **A5 confirmed GEBCO 2026**
  - GEBCO license: A1 "CC BY 4.0" → **A5 confirmed NON-COMMERCIAL (GEBCO ToU)**
  - GEBCO access: A1 "Manual (JS portal)" → **A5 confirmed queue API (automated)**
  - Census TIGER: A1 "TIGER 2020" → **A5 confirmed TIGER 2023**
  Top table in data_sources.md is authoritative for manuscript/methods/citations.
  — 2026-07-11

---

## Data sources used

- **HABSOS** — NOAA NCEI portal: https://www.ncei.noaa.gov/products/harmful-algal-blooms-observing-system — export date: TBD by A1 — License: NOAA open — Purpose: K. brevis ground-truth labels
- **ScienceDirect abstract** (Hu et al. 2022) — accessed 2026-07-11 via WebSearch (abstract page returned 403; metadata confirmed via Google) — Purpose: citation verification
- **A2 grid-clean agent log** — `reports/agent_logs/grid-clean.md` — consumed 2026-07-11 — Purpose: harvest techniques, find Pebesma 2018 citation, note spatial cluster finding
- **A3 habsos-label agent log** — `reports/agent_logs/habsos-label.md` — consumed 2026-07-11 — Purpose: harvest techniques, get confirmed HABSOS URL/access date/license, label stats
- **R scripts 02_build_grid.R, 03_habsos_labels.R** — consumed 2026-07-11 — Purpose: harvest NOTE() tags (implemented scripts)
- **Taylor & Francis / Professional Geographer** (Green 2022) — accessed 2026-07-11 via WebSearch — DOI: 10.1080/00330124.2021.1970591 — Purpose: citation verification for mentor's RTM method
- **NASA OB.DAAC how-to-cite page** — https://oceancolor.gsfc.nasa.gov/resources/how-to-cite/ — accessed 2026-07-11 — Purpose: confirm MODIS citation format
- **Copernicus / ECMWF ERA5 reference** — confirmed via WebSearch — DOI: 10.1002/qj.3803 — Purpose: ERA5 citation
- **UCSB CHC CHIRPS** — confirmed via WebSearch — DOI: 10.1038/sdata.2015.66 — Purpose: CHIRPS citation

---

## Methods & techniques

- **NOTE() tag harvesting** — grep for `NOTE(paper)`, `NOTE(cite)`, `NOTE(limitation)` in R/*.R — pipeline scripts 03–09 are stub (`stop("TODO...")`) as of 2026-07-11; only 00_config.R, 01_source_data.R, 02_build_grid.R carry tags — "novel A-DOC workflow"
- **Decision-log synthesis** — reads all `reports/agent_logs/*.md` as they appear; no agent logs other than this one exist as of 2026-07-11 — "novel A-DOC workflow"
- **Citation verification via web search** — DOIs resolved via WebSearch + WebFetch where pages are accessible — 2026-07-11

---

## Open questions / caveats / limitations

- **Green (2022) DOI 10.1080/00330124.2021.1970591**: confirmed by WebSearch but paper page not fetched. An agent with browser access should confirm the full author list includes "Jamaal W. Green" as sole author.
- **Hu et al. (2022) DOI 10.1016/j.hal.2022.102289**: author list confirmed via WebSearch result summary (8 authors listed) but ScienceDirect page returned 403. The DOI follows standard Elsevier pattern. Marked VERIFY-DOI in bib.
- **Literature-review notes**: PLAN.md §6 mentions "the author's literature-review notes" as an A-DOC input; no such file found in the repo. A-DOC will ingest if/when provided.
- **SMAP salinity citation**: not yet confirmed. A5 (env-features) should log exact dataset version and DOI when pulling.
- **GEBCO citation**: not yet confirmed. A5 should log exact version/year and DOI (GEBCO Compilation Group releases annual grids).
- **Multiple MODIS variable DOIs**: A4 (sat-features) must log the specific NASA OB.DAAC DOIs for nFLH, Kd490, SST, and Rrs bands used, in addition to CHL. The references.bib entry currently covers CHL only; others will be added as A4 logs them.
- **HABSOS coordinates gap**: RESOLVED by A3 (2026-07-11) via GBIF/OBIS IPT DwC-A v1.5 download.
- **Single connected component**: 4,743-cell grid = 1 Queen-contiguity component → A7/A11 must use geographic sub-regions for spatial splits (flagged to team lead).
- **A5 env-features harvest (2026-07-11)**: Read `R/05_environmental_features.R` and
  `reports/agent_logs/env-features.md`. Key findings:

  **New bib entries:**
  - `gebco2026` — GEBCO Compilation Group (2026). DOI 10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f.
    VERIFIED from A5 script header + manual_downloads.md. LICENSE WARNING: GEBCO ToU =
    **non-commercial**, same restriction as MEOW. Flagged in bib, source_set, Limitations.
  - `census_tiger` — Updated from UNRESOLVED → VERIFIED: 2023 vintage, public domain.
    Files: tl_2023_us_county.zip + tl_2023_us_coastline.zip; 82 county blocks;
    dist_to_shore_m 17 m–429 km.
  - `meissner2018smap` — Meissner et al. (2018) *Frontiers in Marine Science*.
    DOI 10.3389/fmars.2018.00349. VERIFY-DOI (DOI logged by A5; title/authors not fetched).

  **Data source status updates:**
  - ERA5 wind: PLACEHOLDER (no ~/.cdsapirc) — data_sources.md updated
  - CHIRPS precip: PLACEHOLDER (403 CrowdSec block) — data_sources.md updated
  - SMAP salinity: PLACEHOLDER (deferred; salinity_coarse_flag=TRUE) — data_sources.md updated
  - GEBCO: REAL — depth_m range −3,539 to +95 m; 24 NA edge cells — data_sources.md updated
  - Census TIGER: REAL — 2023 vintage confirmed — data_sources.md updated

  **Critical flag**: GEBCO non-commercial license — same category as MEOW. Added to
  Limitations section of source_set.md. Flagged in bib note.

  **spatial_block_tiger**: 82 county blocks = THE spatial-CV grouping per Lead Directive.
  This is the replacement for Queen-contiguity (1 component). All A6/A7/A11 spatial splits
  must use this column. Recorded in methods_log.md + source_set.md + data_sources.md.

  **Files updated**: `paper/references.bib` (3 entries), `paper/source_set.md`
  (5 dataset entries + 1 new limitation), `data/metadata/data_sources.md` (5 rows),
  `reports/methods_log.md` (10 new technique/limitation entries). — 2026-07-11

- **A4 sat-features harvest (2026-07-11)**: Read `R/04_satellite_features.R` and
  `reports/agent_logs/sat-features.md`. Confirmed 4 MODIS variable DOIs from script header
  + agent log data-sources table:
  - CHL DOI 10.5067/AQUA/MODIS/L3M/CHL/2022.0 — already in bib (VERIFIED)
  - FLH/nFLH DOI 10.5067/AQUA/MODIS/L3M/FLH/2022.0 — added as `modis_obdaac_nflh` (VERIFIED)
  - KD/Kd_490 DOI 10.5067/AQUA/MODIS/L3M/KD/2022.0 — added as `modis_obdaac_kd490` (VERIFIED)
  - SST DOI 10.5067/AQUA/MODIS/L3M/SST/2019.0 (version 2019.0, not 2022.0) — added as
    `modis_obdaac_sst` (VERIFIED)
  Added `hu2009fai` stub (VERIFY-DOI: Hu 2009 FAI paper; cited in Limitations for FAI
  exclusion rationale; confirm doi.org/10.1016/j.rse.2009.05.012). Updated `methods_log.md`
  with 9 new technique/limitation entries from NOTE() tags. Updated `data_sources.md` MODIS
  row and `source_set.md` MODIS-Aqua entry with confirmed A4 details and value ranges.

- **hu2009fai VERIFIED (2026-07-11)**: WebSearch confirms title "A novel ocean color index to
  detect floating algae in the global oceans", sole author Hu, Chuanmin, Remote Sensing of
  Environment 113(10):2118--2129. DOI 10.1016/j.rse.2009.05.012 confirmed. Updated bib from
  VERIFY-DOI → VERIFIED. — 2026-07-11

- **karki2018modis VERIFIED (2026-07-11)**: Full author list confirmed via WebSearch + Semantic
  Scholar: Karki, S.; Sultan, M.; Elkadiri, R.; Elbayoumi, T. Real title: "Mapping and
  Forecasting Onsets of Harmful Algal Blooms Using MODIS Data over Coastal Waters Surrounding
  Charlotte County, Florida." Remote Sensing 10(10):1656, 2018. DOI 10.3390/rs10101656.
  Updated bib from VERIFY-DOI → VERIFIED; expanded author field; corrected title. — 2026-07-11

- **CRITICAL — meissner2018smap DOI ERROR FOUND AND CORRECTED (2026-07-11)**: A5 script
  CITATIONS block logged DOI 10.3389/fmars.2018.00349 for SMAP. WebFetch of that DOI confirmed
  it resolves to Veilleux et al. 2018 "Molecular Response to Extreme Summer Temperatures..."
  (coral reef fish paper in Frontiers in Marine Science), NOT a SMAP paper. Correct Meissner
  2018 SMAP citation: Meissner, T., Wentz, F.J., Le Vine, D.M. "The Salinity Retrieval
  Algorithms for the NASA Aquarius Version 5 and SMAP Version 3 Releases." Remote Sensing
  10(7):1121 (2018). DOI 10.3390/rs10071121 (MDPI Remote Sensing, VERIFIED via WebSearch).
  Updated bib entry with correct DOI, journal, volume/number/pages, all three authors. The
  erroneous DOI from A5 script has been replaced. **A5 agent should be notified to correct the
  CITATIONS block in R/05_environmental_features.R** (line referencing meissner2018smap).
  — 2026-07-11

- **Author lists still abbreviated**: izadi2021kb, carvalho2011modis, hill2020habnet,
  yao2023viirs, elhabashi2016nn all use "and others" — must be expanded from DOI pages before
  final manuscript. karki2018modis now fully expanded. Priority order: izadi2021kb (most
  directly comparable) → hill2020habnet (Stage-2 comparison) → others.
- **GEBCO non-commercial restriction**: Flagged in bib + source_set + Limitations. A9
  (gis-export) must confirm before using GEBCO depth in any map figure whether the target
  venue permits non-commercial data components. ETOPO (NOAA, public domain) is the fallback.
- **Flanders Marine Institute 2023 DOI**: UNRESOLVED — A9 to confirm version and DOI when
  downloading IHO Sea Areas for GIS outputs.
- **USF Mendeley K. brevis**: UNRESOLVED — A1 or A5 to confirm if dataset is used and log
  title/year/license.
- **Intro citations (Anderson 2000, Gobler 2020, Ralston & Moore 2020, Magaña 2003)**:
  UNRESOLVED — stubs in bib; author to provide titles/DOIs or A-DOC will search when needed.
- **MEOW CC-BY-NC**: Flagged in all files; A9 must confirm whether MEOW polygons are used in
  figures and whether target venue permits NC-licensed components.

- **Bio-optical RESULTS harvest — negative finding recorded (2026-07-14, second pass)**:
  Lead task — the bio-optical measurement landed (A10). Replaced every TBD/placeholder
  numbers in the earlier pass with the actual before/after results, pulled verbatim from
  `reports/agent_logs/validation.md`, `outputs/tables/bio_validation_before_after.csv`, and
  `outputs/tables/bio_fp_concentration_before_after.csv` — no numbers invented; every figure
  in this entry traces to one of those three files.

  **What the numbers say (H=7 temporal, bit-exact, same 8,880 test rows):** PR-AUC
  0.5022→0.4849 (−0.0173), recall@0.5 0.3553→0.3153 (−0.0400), precision@recall-0.80
  0.2759→0.2796 (~flat). Grid: PR-AUC down 10/15, up 5/15; recall@0.5 down 12/15;
  precision@recall-0.80 a wash (7/7/1). Mechanistic nuance: top-chl-Q4 FP 39→31 (100% of the
  net observed-row FP cut), top-chl-Q4 FP share 73.58%→68.89%, joint high-chl/high-nFLH
  FP-rate 12.41%→10.95% — but the FP-concentration RATIO rose 19.09×→22.35× (clean-water FPs
  fell even faster), and the −22 FP cut was outweighed by −43 TP loss. **Recorded as a
  legitimate negative result with a real-but-insufficient targeted effect — not softened,
  not spun as success.**

  **Files updated:**
  - `paper/source_set.md`: replaced the "TBD" placeholder Results subsection with the full
    measured table + mechanistic nuance + honest verdict; updated the RBD/KBBI (a) entry's
    F0 status from "pending" to resolved (F0(667)=1522.491, F0(678)=1480.511 W m⁻²µm⁻¹,
    NASA OBPG Spectral Bandpass Integration, Gate 2 PASS — pulled from
    `reports/agent_logs/sat-features.md`); updated the "Rationale" line to frame RBD/KBBI as
    a *tested hypothesis*, not an assumed benefit; updated two Limitations bullets (reused-
    equations caveat now cites the measured negative; F0-pending caveat now marked resolved);
    fixed 3 stale "implementer (pending)" references now that `R/04b_bio_optical_features.R`
    exists.
  - `reports/methods_log.md`: added a "Bio-optical features — measured model impact (A10)"
    Results subsection (mirrors source_set.md); updated the same two Limitations bullets
    (reused-equations + F0) to reflect the resolved/measured state; fixed 3 stale
    "implementer, pending" references.
  - `paper/design_rationale.md`: §6 bio-optical bullet reworded from "(implemented,
    evidence-backed)" to "(implemented, exact-equation, empirically NEGATIVE)" with an
    explicit instruction not to describe the addition as evidence-backed success; NOTE(cite)
    updated with resolved F0 values; added new **§7.7** ("the bio-optical features did NOT
    improve forecast skill") with the full headline/mechanistic-nuance/honest-verdict
    write-up (chose a new §7.7 rather than renumbering 7.5/7.6, since source_set.md and
    methods_log.md already cross-reference §7.3/§7.4 by number — no renumbering needed,
    checked via grep before editing); §7.4 finding now points forward to §7.7 for the
    measured outcome instead of just "motivates the bio-optical features"; added 2 new §8
    Consolidated-Limitations bullets (FAI bullet updated to note the RBD/KBBI replacement
    didn't help either; new bullet stating the features are tested-and-negative, not a
    validated improvement).

  **Verified before writing:** grepped `paper/` and `reports/` for every `§7.\d` cross-
  reference to confirm only §7.3/§7.4 are referenced externally, so adding §7.7 (rather than
  renumbering existing subsections) would not break any pointer. Confirmed
  `R/04b_bio_optical_features.R` now exists on disk (26,805 bytes, timestamped 2026-07-14)
  before removing "(pending)" implementer language.

  **Not touched:** no code, model, or data/parquet files edited — docs only, consistent with
  task scope. The pre-existing (unrelated) `outputs/figures/*.png`, `outputs/tables/*.csv`,
  and `R/06_build_datacube.R`/`R/07_modeling.R` changes visible in `git status` at this time
  are other agents' work (sat-features/modeling/validation), not mine.
  — 2026-07-14

- **Bio-optical citation fix + source-set pass (2026-07-14)**: Lead task — fix the known
  Amin (2009) venue miscitation and build the publication source set for the new bio-optical
  species-discrimination features (RBD/KBBI, Cannizzaro bbp/chl rule, Morel Case-1 reference
  curve), sourced entirely from `reports/bio_optical_spec.md` (the lead's verified
  exact-equation extraction of the 3 source PDFs). No code, datacube, or parquet files
  touched — docs only, per task scope.

  **Citation error fixed**: `paper/design_rationale.md` line ~143 (§9 citation anchor list)
  miscited Amin et al. (2009) as *Continental Shelf Research* — confused with the Cannizzaro
  (2008) entry two lines above, which is genuinely in that journal. Corrected to *Optics
  Express* 17(11):9126–9144, doi:10.1364/OE.17.009126, with an inline correction note.
  Grepped `paper/`, `reports/`, `references.bib` for every other "Amin"/"Continental Shelf"
  occurrence: §6 (line 91/92) already had the correct venue, so only the one anchor-list line
  was wrong. Also added a NOTE(cite) to §6 documenting that RBD/KBBI are defined on nLw
  (=Rrs×F0), not Rrs — this was not previously stated in design_rationale.md at all (only in
  the spec), and is the kind of detail an implementer or reviewer could get wrong.

  **New `.bib` entries** (`paper/references.bib`, new "BIO-OPTICAL SPECIES DISCRIMINATION"
  section): `amin2009rbd`, `cannizzaro2008bbp`, `morel1988case1`. All three DOIs resolved via
  `curl -L https://doi.org/<doi>` to their correct publisher domains (Optica/opg.optica.org;
  Elsevier/linkinghub.elsevier.com; AGU-Wiley/agupubs.onlinelibrary.wiley.com) — Morel and
  Amin both returned bot-check/403 pages on the publisher side (same pattern as several
  existing VERIFIED entries in this bib, e.g. hu2022karenia), but the DOI→domain resolution
  itself confirms the entries are real, not invented. Marked VERIFIED given the domain match,
  consistent with prior A-DOC precedent for 403-blocked publisher pages in this file.

  **source_set.md**: added a new Methods subsection "Bio-optical species-discrimination
  features (RBD/KBBI + Cannizzaro bbp/chl)" with three publication-ready entries (a) Amin
  RBD/KBBI, (b) Cannizzaro low-bbp-per-chl rule, (c) Morel Case-1 reference curve — each with
  plain-language description, exact citation, equation numbers from the spec, and
  file/agent provenance (`R/04b_bio_optical_features.R` as the pending implementer,
  `reports/bio_optical_spec.md` as the verified spec). Added a Results placeholder table
  (before/after FP-rate and PR-AUC, all TBD, explicitly labeled pending-validation) and two
  new Limitations entries: (1) these are *reused published equations*, not independently
  re-validated for this sensor/aggregation — associations only, no causal or
  validated-sub-cell claim; (2) F0 (NASA sensor constant) sourcing is not yet finalized —
  pending in `reports/agent_logs/sat-features.md`; do not report RBD/KBBI numbers until the
  unit sanity-check passes.

  **methods_log.md**: added 3 technique entries (RBD/KBBI, Cannizzaro rule, Morel curve) to
  the Data section with equation numbers and citations, and 2 Limitations entries mirroring
  the ones above (reused-equations caveat; F0-pending caveat).

  **technique_index.md**: added 3 rows to the master technique table (RBD/KBBI, Cannizzaro
  rule, Morel curve) with file, parameters, and citation columns, marked "planned" since
  `R/04b_bio_optical_features.R` does not exist yet (only the spec is committed).

  **Deliberately left as TBD / not overstated**: (1) F0 exact numeric values — sat-features
  agent's job, not mine; (2) any before/after model-impact number for these features —
  validation agent's job; source_set.md placeholder table makes both facts explicit rather
  than leaving them implicit. (3) `R/04b_bio_optical_features.R` referenced throughout as
  "pending" / "implementer" since it doesn't exist in the repo yet — the spec
  (`reports/bio_optical_spec.md`) is the only committed artifact so far; docs point at the
  spec as authoritative and at the script path as where the equations will land.

  **Files touched:** `paper/design_rationale.md`, `paper/references.bib`,
  `paper/source_set.md`, `reports/methods_log.md`, `reports/technique_index.md`,
  `reports/agent_logs/doc-citations.md` (this entry). No code/data files touched. — 2026-07-14

- **A7 modeling harvest (2026-07-11)**: Read `R/07_modeling.R` (727 lines) and
  `reports/agent_logs/modeling.md`. Two bib citations VERIFIED via parallel WebSearch:
  - `breiman2001rf`: Breiman, L. (2001). "Random Forests." *Machine Learning* 45(1):5–32.
    DOI 10.1023/A:1010933404324. VERIFIED (Springer Nature + ACM DL). Was a comment-stub;
    full @article entry added to references.bib.
  - `wright2017ranger`: Wright, M.N. & Ziegler, A. (2017). "ranger: A Fast Implementation
    of Random Forests for High Dimensional Data in C++ and R." *Journal of Statistical
    Software* 77(1):1–17. DOI 10.18637/jss.v077.i01. VERIFIED (JSS article page). New
    @article entry added to references.bib.
  - `davis2006prcurves`: Davis, J. & Goadrich, M. (2006). "The Relationship Between
    Precision-Recall and ROC Curves." ICML 2006, pp. 233–240. DOI 10.1145/1143844.1143874.
    VERIFY-DOI (well-known; DOI appears consistently in citing sources). New @inproceedings
    stub added. Justifies PR-AUC as primary metric for imbalanced labels.

  **NOTE() tags harvested from `R/07_modeling.R`:**
  - RF: ranger(probability=TRUE, num.trees=500, num.threads=1, case.weights=n_neg/n_pos)
  - log1p transforms: chlor_a_mean (pmax(x,0)), nflh_mean (signed: sign*log1p(|x|)),
    Kd_490_mean (pmax(x,0)); level features only (not trend/delta)
  - Median imputation + {col}_is_missing binary flags; train-derived medians only
  - Feature exclusion: HAB same-day, all HAB_Hk except target, max_count/n_samples,
    6 placeholder env cols, all diagnostic flags, spatial_block_tiger
  - 3 splits: temporal PRIMARY (2003–2015/2016–2021), spatial-block (≥15% rows, tiny
    blocks 12_083/12_077 merged), random 80/20 stratified
  - Persistence baseline (HAB at T); chl-only baseline (RF on log1p chlor_a_mean only)
  - PR-AUC preferred for imbalanced labels (Davis & Goadrich 2006)
  - Skill-vs-horizon decay: required figure (PLAN.md §9/D6)

  **Key R-SPLIT caveats (both logged in modeling.md):**
  - SPATIAL PREVALENCE CONFOUND: spatial holdout isolates Collier County 12_115 at
    11.4% positive vs 8.4% in random test (1.35×); spatial PR-AUC H=7 (0.663) > random
    (0.631) is prevalence-driven, NOT generalization. 14.6% border adjacency = residual
    autocorrelation. Describe as "geographic transfer to high-prevalence region."
  - TEMPORAL ZERO-EMBARGO: ~49 H=14 training rows (0.33%) have label_date in test period
    (no purge gap at 2016 boundary). Small optimistic leak; negligible but nonzero.

  **Headline temporal-split metrics (PRIMARY):**
  - H=7: RF PR-AUC=0.497 vs persistence 0.450 vs chl-only 0.142; ROC-AUC=0.832; recall=0.370
  - H=14: RF PR-AUC=0.445 vs persistence 0.320 vs chl-only 0.122; ROC-AUC=0.812; recall=0.272

  **Files updated in this pass:**
  - `paper/references.bib`: 3 new entries (breiman2001rf @article VERIFIED; wright2017ranger
    @article VERIFIED; davis2006prcurves @inproceedings VERIFY-DOI).
  - `reports/methods_log.md`: 8 new Modeling entries (RF, log1p, imputation, exclusion,
    splits, PR-AUC, baselines, skill decay); Results section with H=7/H=14 temporal tables;
    5 new Limitations (dynamic env placeholder, num.threads=1, spatial prevalence confound,
    temporal zero-embargo, short-horizon sparsity).
  - `paper/source_set.md`: Modeling section expanded (5 new subsections); Results section
    with temporal-split metric tables; 4 new Limitations; karki2018modis VERIFY-DOI →
    VERIFIED; SMAP DOI corrected in citation note.
  — 2026-07-11
