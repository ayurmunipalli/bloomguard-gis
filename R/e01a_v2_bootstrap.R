# E-01a v2 scoring — paired ΔPR-AUC (adopted+ring1 vs adopted-only CONTROL, same dt),
# 30-day block bootstrap n=1000. Clean attribution: both arms share row order/splits,
# so Δ isolates the full-grid ring-1 neighbour features. Also reports the control's
# drift vs the frozen baseline (row-order effect of the neighbour merge).
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table) })
N_BOOT<-1000L; BLOCK_L<-30L; Q<-c(0.025,0.975)
pr_auc_fn<-function(prob,act){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
e<-as.data.table(read_parquet(proj_path("outputs/tables/predictions_e01a_v2.parquet")))
e[,date_T:=as.Date(date_T)]; e[,cell_id:=as.character(cell_id)]
ev<-e[model=="rf_e01a_v2"]; av<-e[model=="rf_adopted_v2"]
setnames(ev,"prob","p_e"); setnames(av,"prob","p_a")
w<-merge(ev[,.(horizon,split,cell_id,date_T,act,p_e)], av[,.(horizon,split,cell_id,date_T,p_a)], by=c("horizon","split","cell_id","date_T"))
frozen<-fread(proj_path("outputs/tables/model_results.csv"))[model=="rf",.(horizon,split,frozen_pr=pr_auc)]
boot<-function(wc,L=BLOCK_L,nb=N_BOOT,seed=42){set.seed(seed);d0<-min(wc$date_T);wc<-copy(wc)[,blk:=as.integer(as.integer(date_T-d0)%/%L)];setkey(wc,blk);bk<-unique(wc$blk);n<-length(bk);v<-numeric(nb)
  for(i in seq_len(nb)){r<-wc[.(sample(bk,n,replace=TRUE)),allow.cartesian=TRUE];v[i]<-pr_auc_fn(r$p_e,r$act)-pr_auc_fn(r$p_a,r$act)};v}
combos<-unique(w[,.(horizon,split)])[order(split,horizon)];res<-list()
for(k in seq_len(nrow(combos))){H<-combos$horizon[k];sp<-combos$split[k];wc<-w[horizon==H&split==sp]
  a_pr<-pr_auc_fn(wc$p_a,wc$act);e_pr<-pr_auc_fn(wc$p_e,wc$act);v<-boot(wc);v<-v[is.finite(v)];ci<-quantile(v,Q)
  res[[length(res)+1]]<-data.table(horizon=H,split=sp,adopted_v2=round(a_pr,4),e01a_v2=round(e_pr,4),
    d_pr_auc=round(e_pr-a_pr,4),ci_lo=round(unname(ci[1]),4),ci_hi=round(unname(ci[2]),4),
    excludes_0=(ci[1]>0&ci[2]>0)|(ci[1]<0&ci[2]<0),suspect=abs(e_pr-a_pr)>0.05)}
ci<-rbindlist(res); ci<-merge(ci,frozen,by=c("horizon","split"),all.x=TRUE); fwrite(ci,proj_path("outputs/tables/e01a_v2_delta_cis.csv"))
cat("=== CONTROL check: adopted_v2 vs frozen baseline (row-order drift from the neighbour merge) ===\n")
print(ci[split=="temporal",.(horizon,frozen_pr,adopted_v2,drift=round(adopted_v2-frozen_pr,4))][order(horizon)])
cat("\n=== E-01a v2 ΔPR-AUC (adopted+ring1 − adopted-only, SAME dt; clean attribution) ===\n")
print(ci[,.(horizon,split,adopted_v2,e01a_v2,d_pr_auc,ci_lo,ci_hi,excludes_0)][order(split,horizon)],nrow=Inf)
cat("\n=== TEMPORAL headline ===\n"); print(ci[split=="temporal",.(horizon,d_pr_auc,ci_lo,ci_hi,excludes_0)][order(horizon)])
cat("\nSUSPECT (|Δ|>0.05)?",any(ci$suspect)," | Mechanistic temporal Δ H1/3/5/7/14 =",paste(ci[split=="temporal"][order(horizon)]$d_pr_auc,collapse=" / "),"\n")
