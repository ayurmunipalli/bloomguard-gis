# BloomGuard GIS

Forecasting *Karenia brevis* harmful algal bloom (HAB) risk **H days ahead** on the West
Florida Shelf, from the **levels and short-term trends** of satellite/environmental
conditions aggregated onto a 10 km coastal grid and exported as GIS-ready risk layers.

Two modeling stages: **Stage 1 Random Forest** (the paper's core), then **Stage 2
Transformer** compared head-to-head. This is genuine *forecasting* — the label is the bloom
status of a cell at day **T+H**, predicted from features observed **through day T** (no
look-ahead leakage).

> > **Governing documents — three files, three functions:**
> [`CLAUDE.md`](CLAUDE.md) — *how* we operate (auto-loaded by Claude Code).
> [`PLAN.md`](PLAN.md) — *the spec*: pinned decisions, feature spec, evaluation protocol.
> [`PROJECT.md`](PROJECT.md) — *the program*: current queue, scoreboard, pivot triggers.
> Read all three. Precedence: CLAUDE.md on operating questions, PROJECT.md on what to build
> next, PLAN.md on what was decided and why.
## Key decisions (PLAN.md §2)

| Item | Value |
|---|---|
| Study area | West Florida Shelf, 24–31°N / 87–81°W (Hu et al. 2022), in code |
| Grid | 10 km cells, Albers EPSG:5070, `cell_id` |
| Label | binary `HAB = 1` if *K. brevis* > 100,000 cells/L (cell × date) |
| Target | forecast `HAB` at T+H; H ∈ {1, 3, 5, 7, 14}, primary H = 7 |
| Stage 1 | Random Forest (`ranger`/`caret`) — first, fully validated |
| Stage 2 | Transformer (committed) — compared honestly to RF |
| Splits | random, temporal (year), spatial (held-out regions) |

## Pipeline (R-first)

Sourced `.R` scripts run end-to-end (not notebooks). Python only for the Stage-2 transformer.

```
R/00_config.R            # load config.yaml, paths, constants
R/01_source_data.R       # API pulls (HABSOS, MODIS, ERA5, CHIRPS)
R/02_build_grid.R        # bbox -> 10 km grid (EPSG:5070)
R/03_habsos_labels.R     # cell x date binary HAB labels
R/04_satellite_features.R  # MODIS features, stream-and-discard
R/05_environmental_features.R  # wind, precip, salinity, static geo
R/06_build_datacube.R    # sftime cube + trend features + T+H labels + flatten
R/07_modeling.R          # Stage-1 Random Forest
R/08_explainability.R    # SHAP + variable importance
R/09_gis_export.R        # risk maps + intra-cell attention drill-down
R/utils_spatial.R        # shared spatial helpers
python/modeling.py       # Stage-2 transformer
python/dl_patches.py     # sequence/patch construction
```

## Environment

- **R-first** with `renv` (commit `renv.lock`): `sf`, `sftime`, `stars`, `tmap`,
  `data.table`, `ranger`/`caret`, `arrow`, `httr2`.
- **Python** (Stage-2 only): see `requirements.txt`.
- **Credentials (never committed):** NASA Earthdata → `~/.netrc`; Copernicus CDS → `~/.cdsapirc`.
- **wget is not installed.** Use R `download.file()`/`httr2` or `curl`.

## Data

Real public sources (HABSOS, MODIS-Aqua L3, ERA5, CHIRPS). See
[`data/metadata/data_sources.md`](data/metadata/data_sources.md). Raw data is **not**
committed (`.gitignore`); blocked pulls get exact steps in the relevant
`data/raw/<source>/manual_downloads.md`. **Never fabricate data** — placeholders are always
clearly labeled (`IS_PLACEHOLDER = TRUE`).

MODIS L3 is global-file-only: features use a **stream-and-discard** loop (download one day →
clip to box → aggregate to grid → delete raw), resumable by date.

## Caveats (honesty guardrails)

- HABSOS non-detection ≠ proven absence (may be unsampled).
- "Associated with," never "causes."
- The intra-cell attention drill-down shows **where flagging conditions concentrate**
  (diagnostic), **not** a validated sub-cell forecast.
- No "operationally ready" claim unless the model survives the temporal/spatial splits.

## Status

**M1–M3 complete.** Stage-1 RF validated across random/temporal/spatial splits vs persistence and
chlorophyll-only baselines (`outputs/tables/model_results.csv`); GIS risk maps and intra-cell
drill-down exported; Stage-2 transformer trained and compared head-to-head.

Three reportable negative results: the transformer does not beat the RF on PR-AUC; ERA5 wind
barely moves metrics; published bio-optical discrimination features do not net-improve skill.

**Current work:** tree-side improvement program — see [`PROJECT.md`](PROJECT.md). Note `PROJECT.md`
§2 records four corrections to how the results above should be read; do not cite the numbers
without it.