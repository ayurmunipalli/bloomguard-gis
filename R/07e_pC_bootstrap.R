# ============================================================
# FILE:       R/07e_pC_bootstrap.R
# PURPOSE:    P0-C. Block-bootstrap 95% CIs on the RE-FROZEN (post-embargo,
#             post-buffer) baseline. Blocks = contiguous calendar-time segments.
#             n=1000. Turns the ~0.01 deltas into verdicts (§7.2).
# INPUTS:     outputs/tables/predictions_pC.parquet (rf_adopted, rf_bio,
#             rf_nowind, persistence — post-repair, per-row)
#             outputs/tables/predictions_transformer.parquet (frozen .pt, per-row)
# OUTPUTS:    outputs/tables/bootstrap_cis_pC.csv
#             reports/results/P0-C_bootstrap_cis.md (written separately)
# TECHNIQUES: non-overlapping block bootstrap over calendar time; paired blocks
#             for deltas; block length justified vs label temporal autocorrelation.
# ============================================================

local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table) })

N_BOOT   <- 1000L
BLOCK_L  <- 30L            # days; justified below vs label autocorrelation
SENS_L   <- c(14L, 60L)    # sensitivity block lengths (H=7 temporal only)
Q        <- c(0.025, 0.975)

pr_auc_fn <- function(prob, act) {
  if (length(unique(act)) < 2) return(NA_real_)
  o <- order(prob, decreasing=TRUE); a <- act[o]
  tp <- cumsum(a); fp <- cumsum(1L-a); pr <- tp/(tp+fp); rc <- tp/sum(a)
  ra <- c(0, rc); pa <- c(pr[1], pr)
  sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2, na.rm=TRUE)
}
p80_fn <- function(prob, act, tr=0.80) {
  if (length(unique(act)) < 2) return(NA_real_)
  o <- order(prob, decreasing=TRUE); a <- act[o]
  tp <- cumsum(a); fp <- cumsum(1L-a); pr <- tp/(tp+fp); rc <- tp/sum(a)
  h <- which(rc >= tr); if (!length(h)) return(NA_real_); pr[h[1]]
}
ci <- function(v) { v <- v[is.finite(v)]; c(lo=unname(quantile(v,Q[1])), hi=unname(quantile(v,Q[2])),
                                            n=length(v)) }

# ── LOAD + PIVOT WIDE ──────────────────────────────────────────────────────
pc <- as.data.table(read_parquet(proj_path("outputs/tables/predictions_pC.parquet")))
tf <- as.data.table(read_parquet(proj_path("outputs/tables/predictions_transformer.parquet")))
tf[, model := "transformer"]
for (d in list(pc, tf)) { d[, date_T := as.Date(date_T)]; d[, cell_id := as.character(cell_id)] }
allp <- rbind(pc, tf, use.names=TRUE)
wide <- dcast(allp, horizon + split + cell_id + date_T + act ~ model, value.var="prob")
setnames(wide, c("rf_adopted","rf_bio","rf_nowind","persistence","transformer"),
         c("p_rf","p_bio","p_nw","p_pers","p_tf"), skip_absent=TRUE)

# ── LABEL TEMPORAL AUTOCORRELATION (block-length justification) ─────────────
# Same-cell consecutive observations: corr(HAB_t, HAB_{t+lag}) by lag bin.
acf_dt <- unique(allp[, .(cell_id, date_T, act, horizon)])[horizon==7]
setorder(acf_dt, cell_id, date_T)
acf_dt[, `:=`(next_act = shift(act, -1, type="shift"),
              gap = as.integer(shift(date_T, -1, type="shift") - date_T)), by=cell_id]
pairs <- acf_dt[!is.na(next_act) & gap > 0 & gap <= 90]
pairs[, lagbin := cut(gap, breaks=c(0,7,14,21,28,42,60,90), labels=c("≤7","8-14","15-21","22-28","29-42","43-60","61-90"))]
acf_tab <- pairs[, .(n=.N, corr=round(cor(act, next_act),3)), by=lagbin][order(lagbin)]
cat("=== Label same-cell autocorrelation vs temporal gap (H=7 labels) ===\n")
print(acf_tab)
cat(sprintf("\nBlock length chosen: L=%d days. Justification: label autocorrelation stays\n", BLOCK_L))
cat("elevated across multi-week gaps (K. brevis blooms persist weeks-months); a 30-day block\n")
cat("spans a full bloom episode so blocks are ~independent. Sensitivity at L=14,60 below.\n\n")

# ── BLOCK BOOTSTRAP ─────────────────────────────────────────────────────────
# Non-overlapping calendar blocks; resample blocks with replacement (paired).
boot_combo <- function(w, L, nboot=N_BOOT, seed=42) {
  set.seed(seed)
  d0 <- min(w$date_T)
  w <- copy(w)[, blk := as.integer(as.integer(date_T - d0) %/% L)]
  setkey(w, blk); blks <- unique(w$blk); nb <- length(blks)
  has_tf <- "p_tf" %in% names(w) && any(is.finite(w$p_tf))
  M <- matrix(NA_real_, nboot, 7,
              dimnames=list(NULL, c("rf_pr","rf_p80","d_rf_pers","d_rf_tf","d_wind_pr","d_bio_pr","d_bio_p80")))
  for (i in seq_len(nboot)) {
    r <- w[.(sample(blks, nb, replace=TRUE)), allow.cartesian=TRUE]
    a <- r$act
    rf <- pr_auc_fn(r$p_rf, a)
    M[i,"rf_pr"]     <- rf
    M[i,"rf_p80"]    <- p80_fn(r$p_rf, a)
    M[i,"d_rf_pers"] <- rf - pr_auc_fn(r$p_pers, a)
    M[i,"d_rf_tf"]   <- if (has_tf) rf - pr_auc_fn(r$p_tf, a) else NA_real_
    M[i,"d_wind_pr"] <- rf - pr_auc_fn(r$p_nw, a)
    M[i,"d_bio_pr"]  <- pr_auc_fn(r$p_bio, a) - rf
    M[i,"d_bio_p80"] <- p80_fn(r$p_bio, a) - p80_fn(r$p_rf, a)
  }
  M
}

combos <- unique(wide[, .(horizon, split)])[order(split, horizon)]
res <- list()
for (k in seq_len(nrow(combos))) {
  H <- combos$horizon[k]; sp <- combos$split[k]
  w <- wide[horizon==H & split==sp]
  M <- boot_combo(w, BLOCK_L)
  # point estimates (full sample)
  a <- w$act
  pt_rf   <- pr_auc_fn(w$p_rf, a); pt_p80 <- p80_fn(w$p_rf, a)
  pt_pers <- pt_rf - pr_auc_fn(w$p_pers, a)
  pt_tf   <- if ("p_tf" %in% names(w) && any(is.finite(w$p_tf))) pt_rf - pr_auc_fn(w$p_tf, a) else NA_real_
  pt_wind <- pt_rf - pr_auc_fn(w$p_nw, a)
  pt_bio  <- pr_auc_fn(w$p_bio, a) - pt_rf
  pt_bio80<- p80_fn(w$p_bio, a) - pt_p80
  for (q in colnames(M)) {
    c95 <- ci(M[,q])
    pt <- switch(q, rf_pr=pt_rf, rf_p80=pt_p80, d_rf_pers=pt_pers, d_rf_tf=pt_tf,
                 d_wind_pr=pt_wind, d_bio_pr=pt_bio, d_bio_p80=pt_bio80)
    res[[length(res)+1]] <- data.table(horizon=H, split=sp, quantity=q,
      point=round(pt,4), ci_lo=round(c95["lo"],4), ci_hi=round(c95["hi"],4),
      excludes_0=ifelse(is.na(pt), NA, (c95["lo"]>0 & c95["hi"]>0) | (c95["lo"]<0 & c95["hi"]<0)),
      block_days=BLOCK_L, n_boot=c95["n"])
  }
}
ci_tab <- rbindlist(res)
fwrite(ci_tab, proj_path("outputs/tables/bootstrap_cis_pC.csv"))

cat("=== 95% block-bootstrap CIs (L=30d, n=1000), post-embargo+buffer baseline ===\n")
print(ci_tab[quantity %in% c("rf_pr","rf_p80")][order(split,horizon)], nrow=Inf)
cat("\n=== Deltas (CI excludes 0 => resolved) ===\n")
print(ci_tab[quantity %in% c("d_rf_pers","d_rf_tf","d_wind_pr","d_bio_pr","d_bio_p80")][order(quantity,split,horizon)], nrow=Inf)

# ── SENSITIVITY: H=7 temporal at L=14,60 ───────────────────────────────────
cat("\n=== Block-length sensitivity: H=7 temporal ===\n")
w7 <- wide[horizon==7 & split=="temporal"]
for (L in c(BLOCK_L, SENS_L)) {
  M <- boot_combo(w7, L)
  for (q in c("rf_pr","d_rf_tf","d_wind_pr","d_bio_p80")) {
    c95 <- ci(M[,q])
    cat(sprintf("  L=%2dd  %-10s  CI [%+.4f, %+.4f]\n", L, q, c95["lo"], c95["hi"]))
  }
}
cat("\n[07e] Done. CIs -> outputs/tables/bootstrap_cis_pC.csv\n")
