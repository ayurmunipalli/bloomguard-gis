# ============================================================
# FILE: 08_explainability.R
# OWNER: A8 explain (opus-4-8)
# PURPOSE: SHAP + variable importance for the Stage-1 RF; report whether LEVELS or TRENDS
#          carry more signal (headline question for the forecasting claim).
# INPUTS:  outputs/models/best_model.rds + datacube/model_dataset.
# OUTPUTS: outputs/figures/shap_summary.png; outputs/tables/top_features.csv;
#          outputs/tables/variable_importance.csv.
# TECHNIQUES: fastshap/treeshap SHAP; ranger importance; level-vs-trend attribution grouping.
# CITATIONS: Lundberg & Lee (2017) SHAP; Green (2022) variable-importance emphasis.
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): "associated with", never "causes". Note if top features are chlorophyll proxies.

stop("TODO(A8 explain): implement SHAP + importance + levels-vs-trends finding. See PLAN.md §6-A8/D9.")
