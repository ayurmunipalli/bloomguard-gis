# Technique index (A-DOC)

Master index: technique → where used → source. A-DOC keeps this current as agents land work.
Every technique must trace to a real source or be honestly marked "novel / mentor's method".

_Last updated: 2026-07-11 (A-DOC initial seeding pass). Rows marked "planned" = technique
is specified in PLAN.md but script not yet implemented._

| Technique | Where used (file/function) | Parameters | Source / citation |
|---|---|---|---|
| Config-driven constants (YAML) | `R/00_config.R` / `config.yaml` | study bbox, cellsize, label threshold, horizons, windows, seed | Project design (PLAN.md D0–D12); no external citation |
| API-first data sourcing | `R/01_source_data.R` (planned) | `httr2`/`download.file()`; no wget | Project rule (author's standing instruction) |
| Bounding-box study-area definition | `R/02_build_grid.R` (planned) | `sf::st_bbox()` → `st_as_sfc()`; 24–31°N 87–81°W | Hu et al. (2022), *Harmful Algae* 117:102289 |
| Albers Equal Area reprojection | `R/02_build_grid.R` (planned) | EPSG:5070 | USGS standard CONUS Albers |
| Regular grid over study area | `R/02_build_grid.R` → `utils_spatial.R::build_study_grid()` | `sf::st_make_grid(cellsize=10000, what="polygons", square=TRUE)`; 4,743 cells; `cell_id` | Green (2022), *The Professional Geographer* 74(1); DOI 10.1080/00330124.2021.1970591; Pebesma (2018) |
| Queen contiguity spatial cluster labeling | `R/utils_spatial.R::flag_spatial_clusters()` | DE-9IM `"****1****"`; union-find BFS; result: 1 component → sub-region grouping for splits | Novel / mentor's method; Pebesma (2018) |
| Darwin Core Archive join | `R/03_habsos_labels.R` | `data.table::merge(event.txt, occurrence.txt, by="eventID")` inner join; 2 corrupt rows dropped | DwC-A standard (TDWG); HABSOS v1.5 |
| Point-to-cell spatial join (HABSOS) | `R/03_habsos_labels.R` | `sf::st_join(st_within, left=FALSE)`; EPSG:4326 → EPSG:5070 | Pebesma (2018); Green (2022) |
| Binary bloom label (threshold) | `R/03_habsos_labels.R` | *K. brevis* max > 100,000 cells/L per (cell_id × date) → `HAB = 1`; `IS_ABSENCE_UNCERTAIN=TRUE` all rows | Hu et al. (2022); PLAN.md D2/D3 |
| MODIS stream-and-discard loop | `R/04_satellite_features.R` (planned) | Per-day: download → clip bbox → aggregate → Parquet → `unlink()`; date checkpoint for resumability | PLAN.md §6 A4 / CLAUDE.md (project requirement) |
| Feature forward/backward fill | `R/04_satellite_features.R`, `R/05_environmental_features.R` (planned) | Fill coarser-cadence features within valid period; flag `feature_filled = TRUE` | PLAN.md §5 |
| ERA5 server-side bbox pull | `R/05_environmental_features.R` (planned) | `area: [31, -87, 24, -81]` in CDS API request | Hersbach et al. (2020), *QJRMS* 146:1999–2049; DOI 10.1002/qj.3803 |
| CHIRPS server-side bbox pull | `R/05_environmental_features.R` (planned) | Gulf box; daily v2.0 | Funk et al. (2015), *Scientific Data* 2:150066; DOI 10.1038/sdata.2015.66 |
| T+H forecasting label shift | `R/06_build_datacube.R` (planned) | Label timestamp = T+H; feature timestamps ≤ T; hard assertion | PLAN.md D5/§2.2 |
| Trend features (D11) | `R/06_build_datacube.R` (planned) | Absolute delta (k={1,3,5,7}); day-over-day %; trailing slope (3/5/7d); crossing flags; rolling mean/std (3d,7d) | PLAN.md D11/§8-B |
| Spatial-autocorrelation cluster flag | `R/06_build_datacube.R` (planned) | Mark clusters of adjacent cells for grouped splits in A7/A11 | PLAN.md §6 A6 checks |
| Random Forest (Stage 1) | `R/07_modeling.R` (planned) | `ranger`/`caret`/`tidymodels`; H ∈ {1,3,5,7,14}; 3 splits; recall + PR-AUC primary | Green (2022) — mentor's RF method; Breiman (2001) [A7 to confirm citation] |
| Skill-vs-horizon evaluation | `R/07_modeling.R` (planned) | Per-horizon metrics; temporal + spatial splits; skill decay curve | PLAN.md §9 |
| SHAP explainability | `R/08_explainability.R` (planned) | SHAP values + variable importance; level vs. trend signal | Lundberg & Lee (2017) [A8 to confirm citation] |
| GIS risk layer export | `R/09_gis_export.R` (planned) | `hab_risk_grid.gpkg` + `hab_risk_raster.tif`; `tmap`/`leaflet` interactive map | Green (2022) — mentor's GIS workflow |
| Intra-cell attention drill-down (D12) | `R/09_gis_export.R` (planned) | Re-derive native ~4 km pixels for mapped dates; convergence overlay; labeled as diagnostic | PLAN.md §2.3/D12 |
| Transformer (Stage 2) | `python/modeling.py` (planned) | Per-cell temporal sequences of level + trend features → T+H HAB; same splits as RF | PLAN.md D7/D8; A11 to cite specific architecture |
| Attention/attribution (transformer) | `python/modeling.py` (planned) | Attention maps over temporal sequences; compared to SHAP | PLAN.md D9; A11 to cite |
| RBD / KBBI (red-band species discrimination) | `R/04b_bio_optical_features.R` / `reports/bio_optical_spec.md` §1 | RBD=nLw(678)−nLw(667); KBBI=RBD/(nLw(678)+nLw(667)); nLw=Rrs×F0 (MODIS bands 13/14); thresholds RBD>0.15, KBBI>0.3·RBD | Amin et al. (2009), *Optics Express* 17(11):9126–9144; DOI 10.1364/OE.17.009126 |
| Cannizzaro low-bbp-per-chl K. brevis rule | `R/04b_bio_optical_features.R` / `reports/bio_optical_spec.md` §3 | Chl>1.5 mg m⁻³ AND bbp(550)<bbp_Morel(550;Chl); bbp(551)=bbp_443·(443/551)^bbp_s | Cannizzaro et al. (2008), *Continental Shelf Research* 28(1):137–158; DOI 10.1016/j.csr.2004.04.007 |
| Morel (1988) Case-1 bbp(550) reference curve | `R/04b_bio_optical_features.R` / `reports/bio_optical_spec.md` §2 | bbp_Morel(550;C)=0.30·C^0.62·[0.002+0.02·(0.5−0.25·log₁₀C)]; underlies the Cannizzaro rule above | Morel (1988), *J. Geophys. Res.* 93(C9):10749–10768; DOI 10.1029/JC093iC09p10749 |
