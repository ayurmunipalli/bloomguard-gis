# ============================================================
# FILE: 07_modeling.R
# OWNER: A7 modeling (Stage-1 Random Forest) — M1 exit owner; split signed off by R-SPLIT
# PURPOSE: Train + evaluate Random Forest forecasting HAB at T+H, per horizon and per split.
# INPUTS:  data/processed/model_dataset.parquet (levels + trend features + T+H labels).
# OUTPUTS: outputs/models/best_model.rds; outputs/tables/model_results.csv;
#          confusion/ROC/PR figures; skill-vs-horizon curve.
# TECHNIQUES: ranger/caret RF; horizons H in {1,3,5,7,14}; random/temporal/spatial splits;
#             persistence + chlorophyll-only baselines; class weighting.
# CITATIONS: Green (2022) RF/variable-importance; ranger (Wright & Ziegler 2017).
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): prioritize RECALL + PR-AUC + FN-rate — a missed bloom > a false alarm (§9).
# NOTE(paper): report performance DROP under temporal/spatial splits and DECAY across horizons.
# NOTE(limitation): no look-ahead + no target-defining features; adjacent cells must not
#                   straddle train/test (grouped/spatial) — R-SPLIT signs this off before "done".

stop("TODO(A7 modeling): implement RF per horizon/split + baselines. GATE: needs A6+R6 done. §6-A7/§9.")
