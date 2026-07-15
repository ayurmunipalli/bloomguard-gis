# ============================================================
# FILE:       R/e06_metrics.R
# PURPOSE:    E-06 scoring. Ordinal metrics (QWK, per-class recall/precision,
#             ordinal-PR per cumulative threshold), Bar B (H=7 category accuracy),
#             and the PRIMARY VERDICT: threshold-back-to-binary PR-AUC + p@r80
#             with 30-day block-bootstrap CIs vs the frozen baseline, for BOTH
#             binary derivations (ordered-forest P(class>=3); multiclass P3+P4).
# INPUTS:     outputs/tables/predictions_e06.parquet ; predictions_pC.parquet (baseline)
# OUTPUTS:    outputs/tables/e06_metrics.csv, e06_binary_delta_cis.csv ; prints report.
# ============================================================
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table) })
N_BOOT<-1000L; BLOCK_L<-30L; Q<-c(0.025,0.975)
pr_auc_fn<-function(prob,act){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
p80_fn<-function(prob,act,tr=0.80){if(length(unique(act))<2)return(NA_real_);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);h<-which(rc>=tr);if(!length(h))return(NA_real_);pr[h[1]]}
qwk<-function(actual,pred,K=5){O<-as.matrix(table(factor(actual,0:(K-1)),factor(pred,0:(K-1))));w<-outer(0:(K-1),0:(K-1),function(i,j)(i-j)^2)/(K-1)^2;E<-outer(rowSums(O),colSums(O))/sum(O);1-sum(w*O)/sum(w*E)}

e06<-as.data.table(read_parquet(proj_path("outputs/tables/predictions_e06.parquet")))
base<-as.data.table(read_parquet(proj_path("outputs/tables/predictions_pC.parquet")))[model=="rf_adopted",.(horizon,split,cell_id,date_T,act,p_base=prob)]
for(d in list(e06,base)){d[,date_T:=as.Date(date_T)];d[,cell_id:=as.character(cell_id)]}
w<-merge(e06, base, by=c("horizon","split","cell_id","date_T"))
stopifnot(nrow(w)==nrow(e06), all(w$act==w$act_bin))

# ── ORDINAL METRICS + BINARY POINT ESTIMATES ──────────────────────────────
mrows<-list(); pcrows<-list()
for(k in 1:nrow(unique(w[,.(horizon,split)]))){}
for(sp in unique(w$split)) for(H in sort(unique(w[split==sp]$horizon))){
  d<-w[split==sp&horizon==H]
  qk_ord<-qwk(d$sev,d$pred_class_ord); qk_mc<-qwk(d$sev,d$pred_class_mc)
  cat_acc_ord<-mean(d$pred_class_ord==d$sev); cat_acc_mc<-mean(d$pred_class_mc==d$sev)
  # ordinal PR per cumulative threshold (ordered forest)
  opr<-sapply(1:4,function(kk){col<-paste0("p_ge",kk,"_ord"); pr_auc_fn(d[[col]], as.integer(d$sev>=kk))})
  mrows[[length(mrows)+1]]<-data.table(horizon=H,split=sp,
    qwk_ord=round(qk_ord,4),qwk_mc=round(qk_mc,4),cat_acc_ord=round(cat_acc_ord,4),cat_acc_mc=round(cat_acc_mc,4),
    ordPR_ge1=round(opr[1],3),ordPR_ge2=round(opr[2],3),ordPR_ge3=round(opr[3],3),ordPR_ge4=round(opr[4],3),
    bin_base=round(pr_auc_fn(d$p_base,d$act_bin),4),
    bin_ord=round(pr_auc_fn(d$p_ge3_ord,d$act_bin),4),
    bin_mc=round(pr_auc_fn(d$p_bin_mc,d$act_bin),4),
    p80_base=round(p80_fn(d$p_base,d$act_bin),4),p80_ord=round(p80_fn(d$p_ge3_ord,d$act_bin),4),p80_mc=round(p80_fn(d$p_bin_mc,d$act_bin),4))
  # per-class recall/precision (ordered forest predicted class)
  O<-as.matrix(table(factor(d$sev,0:4),factor(d$pred_class_ord,0:4)))
  for(c in 0:4){ rec<-if(sum(O[c+1,])>0)O[c+1,c+1]/sum(O[c+1,]) else NA; prec<-if(sum(O[,c+1])>0)O[c+1,c+1]/sum(O[,c+1]) else NA
    pcrows[[length(pcrows)+1]]<-data.table(horizon=H,split=sp,class=c,n_actual=sum(O[c+1,]),recall=round(rec,3),precision=round(prec,3)) }
}
mt<-rbindlist(mrows); pc<-rbindlist(pcrows); fwrite(mt,proj_path("outputs/tables/e06_metrics.csv")); fwrite(pc,proj_path("outputs/tables/e06_perclass.csv"))

# ── BINARY-DELTA BLOCK BOOTSTRAP (ord vs base, mc vs base) ─────────────────
boot<-function(d,which_p,L=BLOCK_L,nb=N_BOOT,seed=42){set.seed(seed);d0<-min(d$date_T);d<-copy(d)[,blk:=as.integer(as.integer(date_T-d0)%/%L)];setkey(d,blk);bk<-unique(d$blk);nbk<-length(bk)
  m<-matrix(NA_real_,nb,2,dimnames=list(NULL,c("d_pr","d_p80")))
  for(i in seq_len(nb)){r<-d[.(sample(bk,nbk,replace=TRUE)),allow.cartesian=TRUE];bp<-pr_auc_fn(r$p_base,r$act_bin);b8<-p80_fn(r$p_base,r$act_bin)
    m[i,"d_pr"]<-pr_auc_fn(r[[which_p]],r$act_bin)-bp; m[i,"d_p80"]<-p80_fn(r[[which_p]],r$act_bin)-b8}
  m}
brows<-list()
for(sp in unique(w$split)) for(H in sort(unique(w[split==sp]$horizon))){
  d<-w[split==sp&horizon==H]
  for(deriv in c("p_ge3_ord","p_bin_mc")){ M<-boot(d,deriv)
    dpr<-pr_auc_fn(d[[deriv]],d$act_bin)-pr_auc_fn(d$p_base,d$act_bin)
    d8<-p80_fn(d[[deriv]],d$act_bin)-p80_fn(d$p_base,d$act_bin)
    cipr<-quantile(M[,"d_pr"],Q,na.rm=TRUE); ci8<-quantile(M[,"d_p80"],Q,na.rm=TRUE)
    brows[[length(brows)+1]]<-data.table(horizon=H,split=sp,derivation=ifelse(deriv=="p_ge3_ord","ordered_P>=3","multiclass_P3+P4"),
      d_pr_auc=round(dpr,4),pr_lo=round(unname(cipr[1]),4),pr_hi=round(unname(cipr[2]),4),pr_excl0=(cipr[1]>0&cipr[2]>0)|(cipr[1]<0&cipr[2]<0),
      d_p80=round(d8,4),p80_lo=round(unname(ci8[1]),4),p80_hi=round(unname(ci8[2]),4),suspect=abs(dpr)>0.05)
  }
}
bd<-rbindlist(brows); fwrite(bd,proj_path("outputs/tables/e06_binary_delta_cis.csv"))

cat("=== ORDINAL METRICS (QWK, category accuracy, ordinal-PR) — temporal ===\n")
print(mt[split=="temporal",.(horizon,qwk_ord,qwk_mc,cat_acc_ord,cat_acc_mc,ordPR_ge3,ordPR_ge4)][order(horizon)])
cat("\n=== PER-CLASS recall/precision (ordered forest) — H=7 temporal (THIN class 4 caveat) ===\n")
print(pc[split=="temporal"&horizon==7][order(class)])
cat("\n=== BINARY VERDICT: ΔPR-AUC vs frozen baseline (30-day block bootstrap, n=1000) — temporal ===\n")
print(bd[split=="temporal",.(horizon,derivation,d_pr_auc,pr_lo,pr_hi,pr_excl0,d_p80,suspect)][order(derivation,horizon)])
cat("\n=== Binary PR-AUC point: base vs ordered vs multiclass (temporal) ===\n")
print(mt[split=="temporal",.(horizon,bin_base,bin_ord,bin_mc,p80_base,p80_ord,p80_mc)][order(horizon)])
cat("\n=== BAR B: H=7 weekly-max category accuracy (5 FWC classes) — comparable target, different splits/region ===\n")
print(mt[horizon==7,.(split,cat_acc_ord,cat_acc_mc)][order(split)])
cat("\nSUSPECT (|Δ|>0.05 any combo)?", any(bd$suspect), "\n")
