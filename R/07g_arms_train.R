# ============================================================
# FILE:       R/07g_arms_train.R
# PURPOSE:    M2a — Arm A (portable) vs Arm B (instrumented) with the EXISTING ranger,
#             identical hyperparameters/seed/folds/scorer to the frozen baseline.
#             ONE change vs the frozen model: the feature set (Rule 1). Plus the two
#             rich-persistence baselines (D19): Arm B on its 5 lags only; Arm A on
#             chlor_a only. Dumps per-row TEST predictions for EVERY model, appends
#             point metrics to model_results.csv, and block-bootstraps the 3 contrasts
#             into bootstrap_cis_pC.csv. Temporal (primary) + random (indicative).
#             SPATIAL SKIPPED (Arm B ring-1 lag needs >=25 km buffer; config is 20 km).
# INPUTS:     data/processed/model_dataset_arm_{a,b}.parquet
# OUTPUTS:    outputs/tables/predictions_arms.parquet   (dump; NOT a results table)
#             outputs/models/arms_rf_temporal.rds        (arm models; best_model.rds untouched)
#             appends: model_results.csv (arm_* rows), bootstrap_cis_pC.csv (d_arm_* rows)
# NOTE(limitation): new temporal test base rate ~9.0% != old 12.1% (double-sampling gone);
#             PR-AUC is base-rate dependent, so arm PR-AUC is NOT comparable to the frozen
#             0.5008. Only within-new-data contrasts (A vs B, arm vs its baseline) are valid.
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger) })

SEED <- 42L; NUM_TREES <- 500L; TRAIN_FRAC <- 0.80
CUTOFF_DATE <- as.Date("2016-01-01"); HORIZONS <- c(1,3,5,7,14)
LOG_FEATURES <- c("chlor_a_mean","nflh_mean","Kd_490_mean")
N_BOOT <- 1000L; BLOCK_L <- 30L; Q <- c(0.025, 0.975)

# ── tie-safe scorer (M0-1) ──
roc_mw <- function(p,a){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a); np<-sum(a==1);nn<-sum(a==0)
  if(np==0||nn==0) return(NA_real_); r<-rank(p); (sum(r[a==1])-np*(np+1)/2)/(np*nn) }
ap_fn <- function(p,a){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a)
  o<-order(p,decreasing=TRUE); pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac)
  keep<-c(which(diff(pp)!=0),length(pp)); prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac)
  sum((rec-c(0,rec[-length(rec)]))*prec) }
p80_fn <- function(p,a,tr=0.80){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a)
  o<-order(p,decreasing=TRUE);pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac)
  keep<-c(which(diff(pp)!=0),length(pp));prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac)
  h<-which(rec>=tr); if(!length(h)) return(NA_real_); prec[h[1]] }

impute_with_flag <- function(tr,te,fc){ for(col in fc){ nc<-paste0(col,"_is_missing")
  tr[[nc]]<-as.integer(is.na(tr[[col]])); te[[nc]]<-as.integer(is.na(te[[col]]))
  md<-median(tr[[col]],na.rm=TRUE); if(is.na(md)) md<-0
  set(tr,which(is.na(tr[[col]])),col,md); set(te,which(is.na(te[[col]])),col,md) }; list(train=tr,test=te) }

fit_predict <- function(h_dt, tr_idx, te_idx, feat_cols, seed_off) {
  na_cols <- feat_cols[vapply(feat_cols,function(cn)anyNA(h_dt[[cn]]),logical(1))]
  tr <- copy(h_dt[tr_idx, c(feat_cols,"label"), with=FALSE]); te <- copy(h_dt[te_idx, c(feat_cols,"label"), with=FALSE])
  im <- impute_with_flag(tr,te,na_cols); tr<-im$train; te<-im$test
  np<-sum(tr$label==1L); nn<-sum(tr$label==0L); if(np==0) return(NULL)
  w <- ifelse(tr$label==1L, nn/np, 1.0); set(tr,j="label",value=factor(tr$label,levels=c(0,1)))
  rf <- ranger(label ~ ., data=tr, num.trees=NUM_TREES, probability=TRUE, case.weights=w,
               num.threads=1L, seed=seed_off)
  list(prob=predict(rf,data=te)$predictions[,"1"], model=rf)
}

# ── load arms; A-ARM parity (identical rows AND order) BEFORE training ──
B <- as.data.table(read_parquet("data/processed/model_dataset_arm_b.parquet"))
A <- as.data.table(read_parquet("data/processed/model_dataset_arm_a.parquet"))
stopifnot("A-ARM: row order differs between arms (D-16)" =
            identical(A[,.(cell_id,date_T,horizon,label)], B[,.(cell_id,date_T,horizon,label)]))
cat("A-ARM parity: identical (cell_id,date_T,horizon,label) order — PASS (", nrow(B), "rows)\n")
rm(A); B[, date_T := as.Date(date_T)]
for (lc in c("rbd_detect","kbbi_kbrevis","cannizzaro_kbrevis")) if (lc %in% names(B)) B[, (lc) := as.integer(get(lc))]
for (f in LOG_FEATURES) if (f %in% names(B)) { if (f=="nflh_mean") B[,(f):=sign(get(f))*log1p(abs(get(f)))] else B[,(f):=log1p(pmax(get(f),0))] }

LAGS <- c("log10_max_cells_prior_7d","log10_max_cells_prior_14d","days_since_last_positive",
          "max_severity_prior_14d","log10_max_cells_neighbors_prior_7d")
EXCL <- c("cell_id","date_T","horizon","label","label_date","snap_date","kbbi_raw",
          "county_fips","county_name","state_fips","spatial_block_tiger","precip_mm","salinity_pss",
          "chl_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","kbbi_invalid",
          "sat_feature_filled","cloud_flag","sat_IS_PLACEHOLDER","wind_is_placeholder",
          "precip_is_placeholder","salinity_is_placeholder","static_IS_PLACEHOLDER")
feat_a       <- setdiff(names(B), c(EXCL, LAGS))    # Arm A (portable)
feat_b       <- c(feat_a, LAGS)                     # Arm B = Arm A + 5 lags (ONE change)
feat_chlpers <- "chlor_a_mean"                      # Arm A persistence: chlorophyll only
feat_rich    <- LAGS                                # Arm B rich-persistence: the 5 lags only
cat("Arm A features:", length(feat_a), "| Arm B features:", length(feat_b),
    "(diff =", length(feat_b)-length(feat_a), "lags)\n\n")

MODELS <- list(arm_a=feat_a, arm_b=feat_b, arm_a_chlpers=feat_chlpers, arm_b_richpers=feat_rich)
split_idx <- c(random=1L, temporal=2L)
out <- list(); pt <- list(); fitted <- list()
for (H in HORIZONS) {
  d <- B[horizon == H]; d[, yr := as.integer(format(date_T,"%Y"))]
  # temporal split (+ P0-A embargo) and random split (stratified 80/20)
  ttr <- which(d$yr < 2016 & (d$label_date < CUTOFF_DATE)); tte <- which(d$yr >= 2016)
  set.seed(SEED+H); pos<-which(d$label==1L); neg<-which(d$label==0L)
  rtr <- sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))), sample(neg,floor(TRAIN_FRAC*length(neg))))); rte<-setdiff(seq_len(nrow(d)),rtr)
  splits <- list(temporal=list(tr=ttr,te=tte), random=list(tr=rtr,te=rte))
  for (sp in names(splits)) {
    tr_idx<-splits[[sp]]$tr; te_idx<-splits[[sp]]$te
    act <- d$label[te_idx]
    for (mdl in names(MODELS)) {
      so <- SEED + H*100L + split_idx[[sp]]
      res <- fit_predict(d, tr_idx, te_idx, MODELS[[mdl]], so)
      if (is.null(res)) next
      out[[length(out)+1]] <- data.table(horizon=H, split=sp, model=mdl,
        cell_id=d$cell_id[te_idx], date_T=d$date_T[te_idx], prob=res$prob, act=as.integer(act))
      pt[[length(pt)+1]] <- data.table(horizon=H, split=sp, model=mdl,
        pr_auc=round(ap_fn(res$prob,act),4), roc_auc=round(roc_mw(res$prob,act),4),
        prec_at_recall80=round(p80_fn(res$prob,act),4),
        n_test=length(act), n_pos=sum(act==1L), n_train=length(tr_idx),
        pos_rate_test=round(mean(act==1L),4))
      if (sp=="temporal" && mdl %in% c("arm_a","arm_b")) fitted[[paste0(mdl,"_H",H)]] <- res$model
    }
    cat(sprintf("  H=%2d %-9s done (n_test=%d, base=%.4f)\n", H, sp, length(te_idx), mean(act==1L)))
  }
}
preds <- rbindlist(out); ptab <- rbindlist(pt)
write_parquet(preds, "outputs/tables/predictions_arms.parquet")
saveRDS(fitted, "outputs/models/arms_rf_temporal.rds")
cat("\nWrote predictions_arms.parquet (", nrow(preds), "rows) and arms_rf_temporal.rds\n")

# ── append point metrics to model_results.csv (arm_* rows, distinguishable by model name) ──
mr <- fread("outputs/tables/model_results.csv")
addcols <- setdiff(names(mr), names(ptab)); for(c in addcols) ptab[, (c) := NA]
ptab <- ptab[, names(mr), with=FALSE]
fwrite(rbind(mr, ptab), "outputs/tables/model_results.csv")
cat("Appended", nrow(ptab), "arm rows to model_results.csv\n")

# ── block-bootstrap the 3 contrasts (temporal, primary), paired, seed 42 ──
wide <- dcast(preds[split=="temporal"], horizon+cell_id+date_T+act ~ model, value.var="prob")
ci <- function(v){v<-v[is.finite(v)];c(lo=unname(quantile(v,Q[1])),hi=unname(quantile(v,Q[2])),n=length(v))}
excl0 <- function(c) as.logical((c["lo"]>0&c["hi"]>0)|(c["lo"]<0&c["hi"]<0))
contrasts <- list(
  d_arm_a_vs_arm_b   = list(x="arm_a",       y="arm_b"),          # A - B  (cost of portability)
  d_arm_b_vs_richpers= list(x="arm_b",       y="arm_b_richpers"), # satellite over boat data
  d_arm_a_vs_chlpers = list(x="arm_a",       y="arm_a_chlpers"))  # satellite stack over chlorophyll
boot_rows <- list()
for (H in HORIZONS) {
  w <- wide[horizon==H]; d0<-min(w$date_T); w[,blk:=as.integer(as.integer(date_T-d0)%/%BLOCK_L)]
  setkey(w,blk); blks<-unique(w$blk); nb<-length(blks)
  for (cn in names(contrasts)) {
    x<-contrasts[[cn]]$x; y<-contrasts[[cn]]$y
    for (metric in c("pr","roc","p80")) {
      fn <- switch(metric, pr=ap_fn, roc=roc_mw, p80=p80_fn)
      set.seed(SEED)
      dv <- numeric(N_BOOT)
      for (i in seq_len(N_BOOT)) { r<-w[.(sample(blks,nb,replace=TRUE)),allow.cartesian=TRUE]; a<-r$act
        dv[i] <- fn(r[[x]],a) - fn(r[[y]],a) }
      pt_delta <- fn(w[[x]],w$act) - fn(w[[y]],w$act); c95<-ci(dv)
      boot_rows[[length(boot_rows)+1]] <- data.table(horizon=H, split="temporal",
        quantity=paste0(cn,"_",metric), point=round(pt_delta,4),
        ci_lo=round(c95["lo"],4), ci_hi=round(c95["hi"],4), excludes_0=excl0(c95),
        block_days=BLOCK_L, n_boot=c95["n"])
    }
  }
  cat("  bootstrapped contrasts H=",H,"\n")
}
bt <- rbindlist(boot_rows)
bc <- fread("outputs/tables/bootstrap_cis_pC.csv")
fwrite(rbind(bc, bt[, names(bc), with=FALSE]), "outputs/tables/bootstrap_cis_pC.csv")
cat("Appended", nrow(bt), "contrast rows to bootstrap_cis_pC.csv\n")
cat("\n=== 07g_arms_train.R DONE ===\n")
