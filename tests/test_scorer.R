# ============================================================
# FILE:       tests/test_scorer.R
# PURPOSE:    Guard against regeneration of the D-20 scorer bug. The metric helpers
#             in R/07_modeling.R must be tie-safe / order-independent. For a binary
#             score, ROC-AUC must equal (sensitivity + specificity)/2 exactly.
# RUN:        Rscript --vanilla tests/test_scorer.R   (exit 0 = pass)
# ============================================================
# Evaluate ONLY the three metric-helper definitions from R/07_modeling.R — not the
# pipeline. This tests the ACTUAL shipped code, not a copy that could drift.
src <- if (file.exists("R/07_modeling.R")) "R/07_modeling.R" else "../R/07_modeling.R"
exprs <- parse(src)
want  <- c("roc_auc_fn", "pr_auc_fn", "precision_at_recall_fn")
for (e in exprs) {
  if (is.call(e) && identical(e[[1]], as.name("<-")) &&
      is.name(e[[2]]) && as.character(e[[2]]) %in% want) {
    eval(e, envir = globalenv())
  }
}
stopifnot(all(sapply(want, exists)))

fails <- 0L
check <- function(name, cond) {
  if (isTRUE(cond)) { cat(sprintf("  PASS  %s\n", name)) }
  else { cat(sprintf("  FAIL  %s\n", name)); fails <<- fails + 1L }
}

# --- Binary score with an analytically known AUC = (sens+spec)/2 ---
# actual: 4 positives, 6 negatives.  prob = binary predictor {0,1}.
actual <- c(1L,1L,1L,1L, 0L,0L,0L,0L,0L,0L)
prob   <- c(1 ,1 ,1 ,0 , 1 ,0 ,0 ,0 ,0 ,0 )
# confusion @ 0.5: tp=3 fp=1 fn=1 tn=5  -> sens=3/4, spec=5/6
sens <- 0.75; spec <- 5/6
expected <- (sens + spec) / 2            # = 19/24 = 0.7916667
got <- roc_auc_fn(prob, actual)
check("binary ROC-AUC == (sens+spec)/2", abs(got - expected) < 1e-9)
cat(sprintf("        expected=%.10f  got=%.10f\n", expected, got))

# --- Order-independence: any row permutation gives the identical value ---
set.seed(7)
perms_ok <- all(replicate(20, {
  idx <- sample(length(actual))
  abs(roc_auc_fn(prob[idx], actual[idx]) - expected) < 1e-12
}))
check("ROC-AUC is order-independent under 20 shuffles", perms_ok)

# --- PR-AUC (average precision) is also order-independent ---
ap0 <- pr_auc_fn(prob, actual)
ap_ok <- all(replicate(20, { idx <- sample(length(actual));
  abs(pr_auc_fn(prob[idx], actual[idx]) - ap0) < 1e-12 }))
check("PR-AUC (average precision) is order-independent", ap_ok)

# --- p@r80 is order-independent ---
p0 <- precision_at_recall_fn(prob, actual, 0.80)
p_ok <- all(replicate(20, { idx <- sample(length(actual));
  identical(precision_at_recall_fn(prob[idx], actual[idx], 0.80), p0) }))
check("precision@recall80 is order-independent", p_ok)

# --- Continuous no-op: MW ROC == trapezoidal ROC for a tie-free score ---
set.seed(1); pc <- sort(runif(200)); ac <- rbinom(200, 1, pc)
trap <- local({ o <- order(pc, decreasing = TRUE); a <- ac[o]
  tp <- cumsum(a); fp <- cumsum(1L - a); tpr <- tp/sum(a); fpr <- fp/sum(1L-a)
  sum(diff(fpr) * (tpr[-length(tpr)] + tpr[-1]) / 2) })
check("continuous ROC: MW == trapezoidal (no-op)", abs(roc_auc_fn(pc, ac) - trap) < 1e-9)

if (fails > 0L) { cat(sprintf("\n%d test(s) FAILED\n", fails)); quit(status = 1L) }
cat("\nAll scorer tests passed.\n")
