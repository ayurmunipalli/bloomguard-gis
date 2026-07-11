# gis (A9) -- decision & methods log

**Agent:** A9 gis (M2 GIS risk mapping)
**Date:** 2026-07-12
**Status:** COMPLETE (RF backend). Transformer re-run pending M3.

---

## Decisions

- **Model-agnostic design (author directive, decisions.md 2026-07-12)**: predict_risk(backend, newdata) is the sole model-specific function. All map/export code is model-blind. Swapping RF -> transformer = update MODEL_PATH + predict() call inside predict_risk(). No other changes. -- 2026-07-12
- **MAP_DATE = 2016-10-24**: test-set date (year >= 2016, temporal split), 13/25 cells HAB_H7=1 (52%), 72% cloud-free MODIS coverage. Active West Florida Shelf bloom period. Avoids 2018 top-positive dates that had zero satellite coverage. -- 2026-07-12
- **RISK_THRESHOLD = 0.40**: P(HAB=1) threshold for priority zones. Prioritizes recall per PLAN sec. 9. Yields 13 flagged cells on MAP_DATE. -- 2026-07-12
- **Feature pipeline IDENTICAL to A7**: same LOG_FEATURES, ALWAYS_EXCLUDE, train-median imputation from backend$train_medians. Enforced via apply_feature_pipeline() using the backend object. Any mismatch silently corrupts predictions. -- 2026-07-12
- **ETOPO preference (decisions.md 2026-07-11)**: GEBCO is non-commercial. CartoDB.Positron used for leaflet tiles (non-commercial safe). Published static figures must use ETOPO 2022 (NOAA NCEI, public domain). Documented in script and map attribution. -- 2026-07-12
- **Intra-cell attention (D12/sec. 2.3)**: MODIS repull attempted for MAP_DATE. SUCCESS -- native ~4km pixels extracted for 13 flagged cells. Convergence: chl-a >= 75th pctile within cell AND depth > -30m AND dist_to_shore < 25km. LEVEL field only (no pixel-level trend fields per sec. 2.3). -- 2026-07-12
- **D12 honesty labels**: every drill-down view labeled 'FEATURE CONCENTRATION (DIAGNOSTIC)'. Nothing rendered below native ~4km MODIS pixel. H=7 precursor-drift caveat in popup and HTML panel. -- 2026-07-12
- **Transformer re-run pending**: author directive (decisions.md 2026-07-12) -- published GIS will use Stage-2 transformer. RF is validated swappable placeholder until M3. Re-run = change MODEL_PATH, source 09_gis_export.R. -- 2026-07-12

## Data sources used

| Dataset | Access | Used for |
|---|---|---|
| best_model.rds (A7) | local file | RF backend |
| model_dataset.parquet (A6) | local file | Features for MAP_DATE |
| study_area_grid.gpkg (A2) | local file | Grid geometry |
| static_geo.parquet (A5) | local file | depth_m, dist_to_shore for convergence |
| MODIS-Aqua L3m CHL (NASA OB.DAAC) | stream-and-discard repull | D12 native pixels | DOI: 10.5067/AQUA/MODIS/L3M/CHL/2022.0 |
| CartoDB.Positron | leaflet tiles | Basemap |
| ETOPO 2022 (NOAA NCEI) | preferred for published figures | Basemap |

## Methods & techniques

- **Model-agnostic predict_risk()**: ranger predict() inside; swap = change MODEL_PATH + inner call. -- R/09_gis_export.R sec. 1
- **apply_feature_pipeline()**: log1p(chl-a, Kd490), signed-log1p(nFLH), median imputation + _is_missing flags. Identical to A7. -- R/09_gis_export.R sec. 1
- **terra::rasterize()**: risk probabilities -> GeoTIFF at 10 km (EPSG:5070). -- sec. 6
- **Priority zones**: filter P(HAB=1) > 0.40. -- sec. 7
- **MODIS repull (D12)**: OB.DAAC API -> curl download -> terra::crop + project -> terra::extract per flagged cell -> unlink() (stream-and-discard). Convergence: elevated pixel AND shallow/nearshore static context. -- sec. 8
- **leaflet map**: CartoDB.Positron base; choropleth + zone + attention layers; EPSG:4326 display; honesty panels. -- sec. 9

## Open questions / caveats / limitations

- NOTE(limitation): Transformer (A11) not yet available. RF-backed map is validated placeholder until M3 completes.
- NOTE(limitation): Dynamic env features (wind, precip, salinity) are all-NA placeholder. Adding ERA5/CHIRPS/SMAP will change predictions.
- NOTE(limitation): HABSOS non-detection != proven absence. Negative predictions in unsampled regions should be interpreted cautiously.
- NOTE(limitation): At H=7, intra-cell pixel patterns are pre-bloom precursor conditions. May drift before bloom lands (sec. 2.3 precursor-drift caveat).
- NOTE(limitation): Pixel-level trend fields omitted from D12 drill-down per sec. 2.3 (noisiest at native resolution due to cloud gaps).
- NOTE(paper): GEBCO depth_m used in modeling/analysis freely (internal use). Published map figures use ETOPO 2022 (NOAA, public domain) per decisions.md.
- NOTE(paper): Backend model named in every output layer and HTML map title so transformer swap is traceable in all exports.

## Done-criteria (PLAN.md sec. 6 A9 / M2) -- pass/fail

| Criterion | Status |
|---|---|
| hab_risk_grid.gpkg exists | PASS |
| hab_risk_raster.tif exists | PASS |
| priority_monitoring_zones.gpkg exists | PASS |
| intracell_attention.gpkg exists | PASS |
| hab_risk_map.html exists | PASS |
| CRS = EPSG:5070 for analysis | PASS |
| predicted_risk_H7 col present | PASS |
| honesty_label col present | PASS |
| backend_model col present | PASS |
| is_model_output col present | PASS |
| HAB_H7 excluded from pred features | PASS |
| n flagged cells > 0 | PASS |
| HTML map > 10KB | PASS |
| IS_PLACEHOLDER col in attention | PASS |

## Swappable backend confirmation

Backend swap RF -> transformer: (1) Update MODEL_PATH (line ~60) to transformer checkpoint. (2) Replace `predict(backend$rf, ...)$predictions[, "1"]` inside predict_risk() with the transformer's inference call. (3) Ensure load_backend() accepts transformer format. (4) ALL map/export code below predict_risk() is unchanged.
