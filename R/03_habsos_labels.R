# ============================================================
# FILE: 03_habsos_labels.R
# OWNER: A3 habsos-label (reviewer R3, sonnet-5)
# PURPOSE: Aggregate HABSOS K. brevis to cell x date; assign binary HAB label (>100k cells/L).
# INPUTS:  cleaned HABSOS points + grid from A2.
# OUTPUTS: data/processed/habsos_labels.parquet + a labels summary (pos/neg cell-day counts).
# TECHNIQUES: spatial join to cells; daily aggregation (max cell_count per cell-day);
#             threshold at 100,000 cells/L (D2).
# CITATIONS: HABSOS (NOAA NCEI); threshold from prior remote-sensing studies (D2).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(limitation): HABSOS non-detection != proven absence (may be unsampled) — state in summary.
# NOTE(paper): positive label = K. brevis > 100,000 cells/L aggregated to cell x date (D2/D3).

stop("TODO(A3 habsos-label): implement labeling. See PLAN.md §6-A3. NOTE: resolve missing lat/lon/date in occurrence.txt first (reports/decisions.md).")
