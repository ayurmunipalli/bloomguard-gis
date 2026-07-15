# E-07 scoring: paired ΔPR-AUC + Δp@r80 (composite − raw-control, same dt), 30-day block bootstrap n=1000.
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table) })
NB<-1000L; L<-30L; Q<-c(0.025,0.975)
pr<-function(prob,act){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);p<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(p[1],p);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
p80<-function(prob,act,t=0.80){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pc<-tp/(tp+fp);rc<-tp/sum(a);h<-which(rc>=t);if(!length(h))return(NA_real_);pc[h[1]]}
e<-as.data.table(read_parquet(proj_path("outputs/tables/predictions_e07.parquet")));e[,date_T:=as.Date(date_T)];e[,cell_id:=as.character(cell_id)]
cm<-e[model=="rf_composite"];rw<-e[model=="rf_raw_control"];setnames(cm,"prob","pc");setnames(rw,"prob","pr0")
w<-merge(cm[,.(horizon,split,cell_id,date_T,act,pc)],rw[,.(horizon,split,cell_id,date_T,pr0)],by=c("horizon","split","cell_id","date_T"))
fr<-fread(proj_path("outputs/tables/model_results.csv"))[model=="rf",.(horizon,split,frozen=pr_auc)]
boot<-function(wc){set.seed(42);d0<-min(wc$date_T);wc<-copy(wc)[,b:=as.integer(as.integer(date_T-d0)%/%L)];setkey(wc,b);bk<-unique(wc$b);n<-length(bk);m<-matrix(NA_real_,NB,2)
  for(i in 1:NB){r<-wc[.(sample(bk,n,replace=TRUE)),allow.cartesian=TRUE];m[i,1]<-pr(r$pc,r$act)-pr(r$pr0,r$act);m[i,2]<-p80(r$pc,r$act)-p80(r$pr0,r$act)};m}
cb<-unique(w[,.(horizon,split)])[order(split,horizon)];res<-list()
for(k in 1:nrow(cb)){H<-cb$horizon[k];sp<-cb$split[k];wc<-w[horizon==H&split==sp]
  dpr<-pr(wc$pc,wc$act)-pr(wc$pr0,wc$act);d8<-p80(wc$pc,wc$act)-p80(wc$pr0,wc$act);M<-boot(wc);ci<-quantile(M[,1],Q,na.rm=TRUE);ci8<-quantile(M[,2],Q,na.rm=TRUE)
  res[[k]]<-data.table(horizon=H,split=sp,raw=round(pr(wc$pr0,wc$act),4),composite=round(pr(wc$pc,wc$act),4),d_pr=round(dpr,4),lo=round(unname(ci[1]),4),hi=round(unname(ci[2]),4),excl0=(ci[1]>0&ci[2]>0)|(ci[1]<0&ci[2]<0),d_p80=round(d8,4),suspect=abs(dpr)>0.05)}
ci<-rbindlist(res);ci<-merge(ci,fr,by=c("horizon","split"),all.x=TRUE);fwrite(ci,proj_path("outputs/tables/e07_delta_cis.csv"))
cat("=== control check: raw vs frozen (temporal) ===\n");print(ci[split=="temporal",.(horizon,frozen,raw,drift=round(raw-frozen,4))][order(horizon)])
cat("\n=== E-07 ΔPR-AUC composite − raw-control (30d block bootstrap n=1000) ===\n");print(ci[,.(horizon,split,raw,composite,d_pr,lo,hi,excl0,d_p80)][order(split,horizon)],nrow=Inf)
cat("\nSUSPECT(|Δ|>0.05)?",any(ci$suspect)," | temporal Δ H1/3/5/7/14 =",paste(ci[split=="temporal"][order(horizon)]$d_pr,collapse=" / "),"\n")
