# Decisions log

Records any change to the pinned decisions in `PLAN.md §2` (D0–D12). Only the lead may change
a pinned decision, and only with an explicit written rationale recorded here.

Format: `YYYY-MM-DD — <decision #/topic> — <old value> → <new value> — <rationale> — <author>`

## Changes

- _(none yet — all §2 decisions stand as written in PLAN.md)_

## Lead directives (implementation choices within §2, not changes to it)

- **2026-07-11 — Spatial-split grouping method.** A2's `flag_spatial_clusters()` uses Queen
  contiguity → the whole rectangular grid is one connected component (`n_clusters = 1`), which
  is useless for spatial cross-validation. **Directive:** the spatial split (§9) must use
  **geographic blocking**, not connected components. A6 (datacube) computes a `spatial_block`
  label by either (a) spatial k-means on cell centroids into ~8–12 contiguous blocks, or
  (b) assigning cells to TIGER counties/regions (once A5/A9 pull them). A7/A11 hold out whole
  blocks; **R-SPLIT verifies adjacent cells don't straddle train/test using these blocks.**
  The Queen-contiguity `spatial_cluster` column may stay as an adjacency diagnostic but is NOT
  the split grouping. (grid-clean flagged this; lead decision.)

## Lead directives (cont.)

- **2026-07-11 — Bathymetry licensing for published figures.** A-DOC flagged that **GEBCO
  (`gebco2026`) and MEOW (`spalding2007meow`) are NON-COMMERCIAL** licenses. **Directive:** GEBCO
  `depth_m` and its derived features may be used freely for internal modeling/analysis, but for
  any published map figure A9 must **prefer ETOPO (NOAA, public domain)** as the bathymetry basemap
  unless the target venue explicitly permits non-commercial components. MEOW ecoregion overlays are
  likewise non-commercial — use only if venue permits, else omit. A-DOC has recorded both in
  source_set.md Limitations. (A9 to honor when spawned; A9 is currently gated behind A7.)

- **2026-07-12 — GIS production model = the Stage-2 transformer (author directive).** PLAN M2/M3
  default (§176, A9 §356) was: A9 builds off the **RF first** and swaps to the transformer **only if**
  the transformer wins the hard (temporal/spatial) splits. **Author directive:** the published GIS
  is intended to visualize the **transformer** forecast, not the RF. **Directive:** (1) A9 builds its
  full map + intra-cell drill-down pipeline **now**, model-agnostically, validated against the RF as a
  swappable backend, then **re-runs on the transformer once M3 (A11) lands**. (2) The honesty gate is
  **unchanged** — the RF-vs-transformer head-to-head (same horizons, same three splits) is reported
  plainly per §9; if the transformer does **not** beat RF on temporal/spatial, that null result is
  stated in the results table and limitations regardless of which model the map renders. Choosing to
  map the transformer as the product is a presentation decision, not license to hide a null comparison.
  (author, via lead.)

## Open items flagged during scaffolding (2026-07-11, lead)

- **HABSOS schema gap — RESOLVED (2026-07-11, A3 habsos-label).** The `occurrence.txt` was
  only the *occurrence extension* of a Darwin Core Sampling Event Archive. The full DwC-A
  (v1.5) was downloaded from `https://ipt-obis.gbif.us/archive.do?r=habsos&v=1.5` and
  extracted to `data/raw/habsos/`. The `event.txt` (event core) carries `decimalLatitude`,
  `decimalLongitude`, and `eventDate` for all 190,341 records. Join key:
  `event.txt$id = occurrence.txt$eventID`. Resolution is documented in
  `reports/agent_logs/habsos-label.md`. `habsos_labels.parquet` produced (IS_PLACEHOLDER=FALSE)
  with 94,810 cell-day rows, 7,523 positive (HAB=1, 7.93%). No coordinates or dates fabricated.
