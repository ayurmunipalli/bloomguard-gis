# ============================================================
# FILE:       R/07h_arms_gbdt.R
# PURPOSE:    M2b — the capacity bundle (D16), both arms. ONE pre-registered bundle of
#             FOUR coordinated changes (R-POWER-cleared, cannot attribute to a single one):
#               (1) LightGBM (objective=binary, early-stop on average precision;
#                   NO scale_pos_weight/is_unbalance — we measure ranking, rule 11),
#               (2) prune 178->33 features by TRAIN-SIDE ranger OOB permutation importance
#                   (pre-declared cut = 10-events-per-feature; NOT mean_abs_shap, D-12),
#               (3) monotonic constraints on physically-signed features only,
#               (4) native NA handling (no median-impute for the GBDT).
#             Contrasts vs M2a's ranger (predictions_arms.parquet). Rich-persistence
#             REBUILT as LightGBM on the 5 lags (rule 14: baseline matches model class).
# INPUTS:     data/processed/model_dataset_arm_{a,b}.parquet ; predictions_arms.parquet (M2a rf)
# OUTPUTS:    outputs/tables/predictions_arms_gbdt.parquet (dump)
#             outputs/models/arms_gbdt_temporal.rds
#             appends model_results.csv (gbdt_* rows), bootstrap_cis_pC.csv (d_gbdt_*/... rows)
# NOTE(limitation): 33-feature selection is done on the TEMPORAL H=7 training fold and applied
#   to all horizons and to the random split. Temporal (primary) is leakage-clean (selected on
#   years<2016, tested on >=2016). Random (indicative) reuses that ranking, a mild selection
#   reuse — random is indicative only.
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(lightgbm) })

SEED <- 42L; CUTOFF_DATE <- as.Date("2016-01-01"); HORIZONS <- c(1,3,5,7,14); N_KEEP <- 33L
N_BOOT <- 1000L; BLOCK_L <- 30L; Q <- c(0.025,0.975)
roc_mw <- function(p,a){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a); np<-sum(a==1);nn<-sum(a==0)
  if(np==0||nn==0) return(NA_real_); r<-rank(p); (sum(r[a==1])-np*(np+1)/2)/(np*nn) }
ap_fn <- function(p,a){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a); o<-order(p,decreasing=TRUE)
  pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac);keep<-c(which(diff(pp)!=0),length(pp))
  prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac); sum((rec-c(0,rec[-length(rec)]))*prec) }
p80_fn <- function(p,a,tr=0.80){ if(length(unique(a))<2) return(NA_real_); a<-as.integer(a); o<-order(p,decreasing=TRUE)
  pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac);keep<-c(which(diff(pp)!=0),length(pp))
  prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac);h<-which(rec>=tr); if(!length(h)) return(NA_real_); prec[h[1]] }

B <- as.data.table(read_parquet("data/processed/model_dataset_arm_b.parquet"))
A <- as.data.table(read_parquet("data/processed/model_dataset_arm_a.parquet"))
stopifnot("A-ARM: row order differs (D-16)" =
            identical(A[,.(cell_id,date_T,horizon,label)], B[,.(cell_id,date_T,horizon,label)]))
cat("A-ARM parity PASS (", nrow(B), "rows)\n"); rm(A); B[, date_T := as.Date(date_T)]
for (lc in c("rbd_detect","kbbi_kbrevis","cannizzaro_kbrevis")) if (lc %in% names(B)) B[, (lc) := as.integer(get(lc))]

LAGS <- c("log10_max_cells_prior_7d","log10_max_cells_prior_14d","days_since_last_positive",
          "max_severity_prior_14d","log10_max_cells_neighbors_prior_7d")
EXCL <- c("cell_id","date_T","horizon","label","label_date","snap_date","kbbi_raw",
          "county_fips","county_name","state_fips","spatial_block_tiger","precip_mm","salinity_pss",
          "chl_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","kbbi_invalid",
          "sat_feature_filled","cloud_flag","sat_IS_PLACEHOLDER","wind_is_placeholder",
          "precip_is_placeholder","salinity_is_placeholder","static_IS_PLACEHOLDER")
feat_a <- setdiff(names(B), c(EXCL, LAGS)); feat_b <- c(feat_a, LAGS)
MONO_UP <- c("chlor_a_mean","nflh_mean","log10_max_cells_prior_7d","log10_max_cells_prior_14d")

# split builder (identical to M2a)
splits_for <- function(d,H){ d[, yr := as.integer(format(date_T,"%Y"))]
  ttr <- which(d$yr < 2016 & (d$label_date < CUTOFF_DATE)); tte <- which(d$yr >= 2016)
  set.seed(SEED+H); pos<-which(d$label==1L); neg<-which(d$label==0L)
  rtr <- sort(c(sample(pos,floor(0.8*length(pos))), sample(neg,floor(0.8*length(neg))))); rte<-setdiff(seq_len(nrow(d)),rtr)
  list(temporal=list(tr=ttr,te=tte), random=list(tr=rtr,te=rte)) }

# ── (2) TRAIN-SIDE OOB permutation importance -> top 33, per arm, on TEMPORAL H=7 train ──
select33 <- function(feat, arm){
  d7 <- B[horizon==7]; sp <- splits_for(d7,7L); tr <- sp$temporal$tr
  X <- copy(d7[tr, c(feat,"label"), with=FALSE])
  for (f in intersect(c("chlor_a_mean","nflh_mean","Kd_490_mean"), feat))
    if (f=="nflh_mean") X[,(f):=sign(get(f))*log1p(abs(get(f)))] else X[,(f):=log1p(pmax(get(f),0))]
  for (col in feat) { md<-median(X[[col]],na.rm=TRUE); if(is.na(md))md<-0; set(X,which(is.na(X[[col]])),col,md) }
  set(X,j="label",value=factor(X$label,levels=c(0,1)))
  rf <- ranger(label ~ ., data=X, num.trees=300L, importance="permutation", probability=TRUE,
               num.threads=1L, seed=SEED)
  imp <- sort(rf$variable.importance, decreasing=TRUE)
  keep <- names(imp)[seq_len(min(N_KEEP,length(imp)))]
  cat(sprintf("\n[%s] top %d train-side OOB features:\n", arm, length(keep)))
  print(data.table(rank=seq_along(keep), feature=keep, oob_imp=round(imp[keep],6)))
  keep
}
top_a <- select33(feat_a,"arm_a"); top_b <- select33(feat_b,"arm_b")

# ── LightGBM fit: native NA, monotone constraints, early-stop on average_precision ──
fit_lgb <- function(d, tr_idx, te_idx, feats, seed_off) {
  Xtr <- as.matrix(d[tr_idx, ..feats]); ytr <- d$label[tr_idx]
  Xte <- as.matrix(d[te_idx, ..feats])
  set.seed(seed_off); vi <- sample(seq_along(ytr), floor(0.2*length(ytr)))  # early-stop validation from TRAIN
  ti <- setdiff(seq_along(ytr), vi)
  mono <- as.integer(feats %in% MONO_UP)   # +1 up, 0 none
  dtr <- lgb.Dataset(Xtr[ti,,drop=FALSE], label=ytr[ti])
  dva <- lgb.Dataset.create.valid(dtr, Xtr[vi,,drop=FALSE], label=ytr[vi])
  m <- lgb.train(params=list(objective="binary", metric="average_precision", learning_rate=0.05,
                   num_leaves=31L, min_data_in_leaf=20L, monotone_constraints=mono,
                   num_threads=1L, seed=seed_off, deterministic=TRUE, verbosity=-1L),
                 data=dtr, nrounds=1000L, valids=list(valid=dva),
                 early_stopping_rounds=50L, verbose=-1L)
  list(prob=predict(m, Xte), model=m, nrounds=m$best_iter)
}

split_idx <- c(random=1L, temporal=2L)
MODELS <- list(gbdt_arm_a=list(feats=top_a), gbdt_arm_b=list(feats=top_b),
               gbdt_b_richpers=list(feats=LAGS))
out<-list(); pt<-list(); fitted<-list()
for (H in HORIZONS) {
  d <- B[horizon==H]; sp <- splits_for(d,H)
  for (spn in names(sp)) {
    tr_idx<-sp[[spn]]$tr; te_idx<-sp[[spn]]$te; act<-d$label[te_idx]
    for (mdl in names(MODELS)) {
      so <- SEED + H*100L + split_idx[[spn]]
      r <- fit_lgb(d, tr_idx, te_idx, MODELS[[mdl]]$feats, so)
      out[[length(out)+1]] <- data.table(horizon=H, split=spn, model=mdl,
        cell_id=d$cell_id[te_idx], date_T=d$date_T[te_idx], prob=r$prob, act=as.integer(act))
      pt[[length(pt)+1]] <- data.table(horizon=H, split=spn, model=mdl,
        pr_auc=round(ap_fn(r$prob,act),4), roc_auc=round(roc_mw(r$prob,act),4),
        prec_at_recall80=round(p80_fn(r$prob,act),4), n_test=length(act), n_pos=sum(act==1L),
        n_train=length(tr_idx))
      if (spn=="temporal") fitted[[paste0(mdl,"_H",H)]] <- r$model
    }
    cat(sprintf("  H=%2d %-9s done\n", H, spn))
  }
}
preds <- rbindlist(out); ptab <- rbindlist(pt)
write_parquet(preds, "outputs/tables/predictions_arms_gbdt.parquet")
saveRDS(fitted, "outputs/models/arms_gbdt_temporal.rds")

mr <- fread("outputs/tables/model_results.csv")
for(c in setdiff(names(mr),names(ptab))) ptab[,(c):=NA]; ptab<-ptab[,names(mr),with=FALSE]
fwrite(rbind(mr,ptab),"outputs/tables/model_results.csv")
cat("Appended",nrow(ptab),"gbdt rows to model_results.csv\n")

# ── contrasts vs M2a ranger (predictions_arms.parquet) — paired block bootstrap ──
rf <- as.data.table(read_parquet("outputs/tables/predictions_arms.parquet"))
rf[, date_T := as.Date(date_T)]; preds[, date_T := as.Date(date_T)]
allp <- rbind(rf[split=="temporal", .(horizon,cell_id,date_T,act,model,prob)],
              preds[split=="temporal", .(horizon,cell_id,date_T,act,model,prob)])
wide <- dcast(allp, horizon+cell_id+date_T+act ~ model, value.var="prob")
ci <- function(v){v<-v[is.finite(v)];c(lo=unname(quantile(v,Q[1])),hi=unname(quantile(v,Q[2])),n=length(v))}
excl0 <- function(c) as.logical((c["lo"]>0&c["hi"]>0)|(c["lo"]<0&c["hi"]<0))
contr <- list(d_gbdt_vs_rf_arm_a=c("gbdt_arm_a","arm_a"), d_gbdt_vs_rf_arm_b=c("gbdt_arm_b","arm_b"),
              d_arm_a_vs_arm_b_gbdt=c("gbdt_arm_a","gbdt_arm_b"),
              d_arm_b_vs_richpers_gbdt=c("gbdt_arm_b","gbdt_b_richpers"))
br<-list()
for (H in HORIZONS){ w<-wide[horizon==H]; d0<-min(w$date_T); w[,blk:=as.integer(as.integer(date_T-d0)%/%BLOCK_L)]
  setkey(w,blk); blks<-unique(w$blk); nb<-length(blks)
  for (cn in names(contr)){ x<-contr[[cn]][1]; y<-contr[[cn]][2]
    for (met in c("pr","roc","p80")){ fn<-switch(met,pr=ap_fn,roc=roc_mw,p80=p80_fn); set.seed(SEED)
      dv<-numeric(N_BOOT); for(i in seq_len(N_BOOT)){r<-w[.(sample(blks,nb,replace=TRUE)),allow.cartesian=TRUE];a<-r$act
        dv[i]<-fn(r[[x]],a)-fn(r[[y]],a)}
      c95<-ci(dv); br[[length(br)+1]]<-data.table(horizon=H,split="temporal",quantity=paste0(cn,"_",met),
        point=round(fn(w[[x]],w$act)-fn(w[[y]],w$act),4),ci_lo=round(c95["lo"],4),ci_hi=round(c95["hi"],4),
        excludes_0=excl0(c95),block_days=BLOCK_L,n_boot=c95["n"]) } }
  cat("  bootstrapped H=",H,"\n") }
bt<-rbindlist(br); bc<-fread("outputs/tables/bootstrap_cis_pC.csv")
fwrite(rbind(bc,bt[,names(bc),with=FALSE]),"outputs/tables/bootstrap_cis_pC.csv")
cat("Appended",nrow(bt),"contrast rows\n=== 07h DONE ===\n")
