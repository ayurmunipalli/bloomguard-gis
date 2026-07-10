# ============================================================
# FILE: modeling.py
# OWNER: A11 transformer (Stage-2, M3) — split signed off by R-SPLIT
# PURPOSE: Temporal (or spatiotemporal) transformer forecasting HAB at T+H from per-cell
#          sequences of level + trend features. Head-to-head vs. Stage-1 RF.
# INPUTS:  data/processed/datacube.rds -> per-cell ordered sequences (levels+trends through T)
#          + T+H labels; outputs/tables/model_results.csv (RF rows to beat).
# OUTPUTS: outputs/models/transformer.*; transformer rows appended to model_results.csv;
#          attention/attribution figures; head-to-head comparison table.
# TECHNIQUES: sequence transformer; same 3 splits + same horizons as RF; dropout + early
#             stopping + class weighting (NOT naive oversampling).
# CITATIONS: Vaswani et al. (2017) attention; HABNet (prior HAB DL work).
# ============================================================

# NOTE(paper): NO look-ahead in sequence construction — nothing from T+1..T+H in inputs.
# NOTE(paper): same grouped/spatial splits as A7 (R-SPLIT sign-off) so comparison is fair.
# NOTE(paper): honest verdict — if it does NOT beat RF under hard splits, report that plainly.

# Spawns only AFTER M1 (Stage-1 RF) is committed — needs the benchmark to beat.
raise NotImplementedError(
    "TODO(A11 transformer): implement Stage-2 transformer. Spawns after M1 committed. See PLAN.md §6-A11/M3."
)
