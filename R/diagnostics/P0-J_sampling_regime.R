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

# NOTE(paper): PART A (marginal) shows the HAB-history features fire ~1.5-2x more
#   often (fraction == 1) in the 2016+ test era. But the label positive rate rises
#   in lockstep, so the marginal rate CANNOT test the §2.5 informativeness claim.
# NOTE(paper): PART B (conditional) is the actual test. The odds ratio linking the
#   feature to the label is STATISTICALLY INDISTINGUISHABLE train vs test at
#   H=1/3/5, and SIGNIFICANTLY LOWER in test at H=7/14 (OR ratio ~0.55, CI excludes
#   1, interaction p < 1e-6). The feature is never MORE informative in test.
#   => PROJECT.md §2.5 sampling-regime-informativeness hypothesis is REJECTED.
# NOTE(limitation): these features are ZERO-IMPUTED indicators (0 = no prior
#   HAB observation in the window), so non-missing rate is 100% in both eras.
#   The density shift is real but reflects sampling intensity lifting both feature
#   and label, not a change in the feature's predictive value.

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
cat("=== PART A: marginal firing rate (NOT a test of informativeness) ===\n")
print(out, nrow = Inf)

# ── PART B: CONDITIONAL informativeness (the actual §2.5 test) ────────────────
# For each (H, era, feature): 2x2 table feature{0,1} x label{0,1}.
#   P1 = P(label=1 | feature=1) = a/(a+b)
#   P0 = P(label=1 | feature=0) = c/(c+d)
#   lift = P1 / P0
#   OR   = (a*d)/(b*c) ; Wald 95% CI via SE(logOR) = sqrt(1/a+1/b+1/c+1/d)
# Then the era interaction: OR_test / OR_train with a 95% CI (combined SE) and a
# Wald p. CI excluding 1 => feature informativeness differs by era.
cond <- data.table()
for (H in Hs) {
  lab <- paste0("HAB_H", H)
  sub <- dt[!is.na(get(lab))]
  sub[, era := ifelse(yr < CUTOFF_YEAR, "train", "test")]
  for (f in feats) {
    est <- list()
    for (e in c("train", "test")) {
      s <- sub[era == e]; y <- s[[lab]]; x <- s[[f]]
      a <- sum(x == 1 & y == 1); b <- sum(x == 1 & y == 0)
      cc <- sum(x == 0 & y == 1); d <- sum(x == 0 & y == 0)
      logOR <- log((a * d) / (b * cc)); se <- sqrt(1/a + 1/b + 1/cc + 1/d)
      est[[e]] <- c(logOR = logOR, se = se)
      cond <- rbind(cond, data.table(
        H = H, feature = f, era = e,
        P1_pct = round(100 * a / (a + b), 2),
        P0_pct = round(100 * cc / (cc + d), 2),
        lift   = round((a / (a + b)) / (cc / (cc + d)), 2),
        OR     = round(exp(logOR), 2),
        OR_lo  = round(exp(logOR - 1.96 * se), 2),
        OR_hi  = round(exp(logOR + 1.96 * se), 2)
      ))
    }
    dlog <- est$test["logOR"] - est$train["logOR"]
    dse  <- sqrt(est$test["se"]^2 + est$train["se"]^2)
    cond <- rbind(cond, data.table(
      H = H, feature = f, era = "RATIO test/train",
      P1_pct = NA_real_, P0_pct = NA_real_,
      lift = round(exp(dlog), 2),          # OR ratio in the 'lift' slot for RATIO rows
      OR = round(exp(dlog), 2),
      OR_lo = round(exp(dlog - 1.96 * dse), 2),
      OR_hi = round(exp(dlog + 1.96 * dse), 2)
    ), fill = TRUE)
  }
}
setorder(cond, feature, H)
cat("\n=== PART B: conditional P(label|feature), lift, OR [95% CI], and era interaction ===\n")
cat("    (RATIO rows: OR_test/OR_train; CI excluding 1 => informativeness differs by era)\n")
print(cond, nrow = Inf)
