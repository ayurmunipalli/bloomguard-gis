# ============================================================
# FILE:       R/e01a_bootstrap.R
# PURPOSE:    E-01a scoring. Paired block-bootstrap ΔPR-AUC (E-01a − re-frozen
#             baseline) with the P0-C protocol (30-day blocks, n=1000, 95% CI).
#             Baseline = rf_adopted (predictions_pC.parquet); E-01a =
#             predictions_e01a.parquet. Same repaired test rows (paired).
# OUTPUTS:    outputs/tables/e01a_delta_cis.csv ; prints verdict inputs.
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table) })
N_BOOT<-1000L; BLOCK_L<-30L; Q<-c(0.025,0.975)
pr_auc_fn<-function(prob,act){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}

base <- as.data.table(read_parquet(proj_path("outputs/tables/predictions_pC.parquet")))[model=="rf_adopted"]
e01a <- as.data.table(read_parquet(proj_path("outputs/tables/predictions_e01a.parquet")))
for(d in list(base,e01a)){ d[,date_T:=as.Date(date_T)]; d[,cell_id:=as.character(cell_id)] }
setnames(base,"prob","p_base"); setnames(e01a,"prob","p_e01a")
w <- merge(base[,.(horizon,split,cell_id,date_T,act,p_base)],
           e01a[,.(horizon,split,cell_id,date_T,p_e01a)],
           by=c("horizon","split","cell_id","date_T"))
cat("[E-01a boot] paired rows:", nrow(w), "| per combo:\n"); print(w[,.N,by=.(split,horizon)][order(split,horizon)])

boot_delta <- function(wc,L=BLOCK_L,nb=N_BOOT,seed=42){
  set.seed(seed); d0<-min(wc$date_T); wc<-copy(wc)[,blk:=as.integer(as.integer(date_T-d0)%/%L)]
  setkey(wc,blk); blks<-unique(wc$blk); nblk<-length(blks); v<-numeric(nb)
  for(i in seq_len(nb)){ r<-wc[.(sample(blks,nblk,replace=TRUE)),allow.cartesian=TRUE]
    v[i]<-pr_auc_fn(r$p_e01a,r$act)-pr_auc_fn(r$p_base,r$act) }
  v
}
combos<-unique(w[,.(horizon,split)])[order(split,horizon)]; res<-list()
for(k in seq_len(nrow(combos))){
  H<-combos$horizon[k];sp<-combos$split[k];wc<-w[horizon==H&split==sp]
  base_pr<-pr_auc_fn(wc$p_base,wc$act); e_pr<-pr_auc_fn(wc$p_e01a,wc$act)
  v<-boot_delta(wc); v<-v[is.finite(v)]
  ci<-quantile(v,Q)
  res[[length(res)+1]]<-data.table(horizon=H,split=sp,base_pr_auc=round(base_pr,4),e01a_pr_auc=round(e_pr,4),
    d_pr_auc=round(e_pr-base_pr,4),ci_lo=round(unname(ci[1]),4),ci_hi=round(unname(ci[2]),4),
    excludes_0=(ci[1]>0&ci[2]>0)|(ci[1]<0&ci[2]<0),
    suspect=abs(e_pr-base_pr)>0.05, block_days=BLOCK_L)
}
ci<-rbindlist(res); fwrite(ci, proj_path("outputs/tables/e01a_delta_cis.csv"))
cat("\n=== E-01a ΔPR-AUC vs re-frozen baseline (30-day block bootstrap, n=1000) ===\n")
print(ci[order(split,horizon)],nrow=Inf)
cat("\n=== TEMPORAL (headline) ===\n"); print(ci[split=="temporal"][order(horizon)])
cat("\nSUSPECT (|Δ|>0.05 any horizon)?", any(ci$suspect), "\n")
cat("Mechanistic: Δ by temporal horizon H1/3/5/7/14 =",
    paste(ci[split=="temporal"][order(horizon)]$d_pr_auc, collapse=" / "), "\n")
