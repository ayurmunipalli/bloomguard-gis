# ============================================================
# FILE: R/diagnostics/P0-J_sampling_regime.R
# PURPOSE: P0-J (PROJECT.md §2.5). Read-only diagnostic. Tests whether the
#          hab_any_prior_7d / hab_any_prior_14d features are sparse in the
#          training era (year < 2016) and dense in the test era (year >= 2016),
#          per forecast horizon, under the temporal split.
#          NO model, feature, or split changes. Metadata read only.
# INPUTS:  data/processed/model_dataset.parquet
# OUTPUTS: reports/results/P0-J_sampling_regime.md (authored separately);
#          prints the per-horizon train/test table to stdout.
# TECHNIQUES: arrow single-thread read, per-horizon modeling-set subsetting
#             (rows where HAB_H{H} is non-missing), temporal-cutoff split.
# CITATIONS: none (diagnostic).
# ============================================================

# NOTE(paper): the temporal split is not only a time split; the HAB-history
#   features are ~1.5-2x denser (fraction == 1) in the 2016+ test era than in
#   the pre-2016 training era, at every horizon. This is the sampling-regime
#   shift of PROJECT.md §2.5 measured directly.
# NOTE(limitation): these features are ZERO-IMPUTED indicators (0 = no prior
#   HAB observation in the window), so non-missing rate is 100% in both eras.
#   The regime effect lives in the value distribution, not in missingness.

source("R/00_config.R")
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(1L)

CUTOFF_YEAR <- 2016L   # train: year < 2016 ; test: year >= 2016
Hs    <- c(1, 3, 5, 7, 14)
feats <- c("hab_any_prior_7d", "hab_any_prior_14d")

cols <- c("date_T", paste0("HAB_H", Hs), feats)
dt <- as.data.table(
  open_dataset(proj_path("data/processed/model_dataset.parquet")) |>
    dplyr::select(dplyr::all_of(cols)) |> dplyr::collect()
)
dt[, yr := as.integer(format(as.Date(date_T), "%Y"))]

out <- data.table()
for (H in Hs) {
  lab <- paste0("HAB_H", H)
  sub <- dt[!is.na(get(lab))]                       # modeling set for horizon H
  sub[, era := ifelse(yr < CUTOFF_YEAR, "train", "test")]
  for (era_i in c("train", "test")) {
    s <- sub[era == era_i]
    for (f in feats) {
      v <- s[[f]]
      out <- rbind(out, data.table(
        H = H, era = era_i, feature = f, n = length(v),
        pct_nonmiss = round(100 * mean(!is.na(v)), 2),
        pct_eq1     = round(100 * sum(v == 1, na.rm = TRUE) / length(v), 2)
      ))
    }
  }
}
setorder(out, feature, H, -era)
print(out, nrow = Inf)
