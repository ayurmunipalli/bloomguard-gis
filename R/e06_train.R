# ============================================================
# FILE:       R/e06_train.R
# PURPOSE:    E-06 (Stage 1) — ordinal severity reframe. Trains, per H x split
#             (repaired splits), on the ADOPTED feature set:
#               (A) ORDERED FOREST — 4 cumulative ranger prob. forests on
#                   (sev>=k), k=1..4. Monotone-clamped -> 5 class probs. Ordinal
#                   metrics (QWK, per-class, ordinal-PR) come from this (respects
#                   ordering). Binary derivation = P(class>=3) (the k=3 forest).
#               (B) MULTICLASS ranger (5-class prob.) — binary derivation
#                   P(3)+P(4). This is the ONLY tree mechanism where the denser
#                   target can shift the class-3 boundary, so it is the meaningful
#                   binary verdict. LIMITATION: multiclass does NOT exploit class
#                   ordering (flagged; QWK still scores its ordering).
#             Baseline binary RF = rf_adopted (predictions_pC.parquet), unchanged.
# INPUTS:     data/processed/model_dataset.parquet ; habsos_labels.parquet ; config
# OUTPUTS:    outputs/tables/predictions_e06.parquet
#             cols: horizon,split,cell_id,date_T, sev(actual), act_bin(sev>=3),
#                   p_ge3_ord, p_bin_mc, pred_class_ord, pred_class_mc,
#                   p_ge1_ord..p_ge4_ord  (ordinal-PR thresholds)
# NOTE:       adopted feature set only (NO bio, NO E-01a neighbours). Same repaired
#             splits/seed/hyperparameters as the frozen baseline (feature+config parity).
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })

SEED<-cfg$random_seed%||%42; NUM_TREES<-500L; TRAIN_FRAC<-0.80; CUT_YR<-2016L; CUT_DATE<-as.Date("2016-01-01"); MIN_BLK<-5L
HORIZONS<-cfg$forecast$horizons_days; LOG_FEATURES<-c("chlor_a_mean","nflh_mean","Kd_490_mean")
EMBARGO_ON<-isTRUE(cfg$split_repair$temporal_embargo); BUFFER_M<-as.numeric(cfg$split_repair$spatial_buffer_m%||%0)
fwc<-function(x)as.integer((x>1000)+(x>10000)+(x>100000)+(x>1e6))
ALWAYS_EXCLUDE<-c("cell_id","date_T","HAB","HAB_H1","HAB_H3","HAB_H5","HAB_H7","HAB_H14",
  "spatial_block_tiger","max_count","n_samples","IS_PLACEHOLDER_ROW","satellite_missing","cloud_flag",
  "salinity_coarse_flag","feature_filled_any","IS_ABSENCE_UNCERTAIN","sat_IS_PLACEHOLDER","env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER","label_IS_PLACEHOLDER","sat_feature_filled","env_feature_filled","precip_mm","salinity_pss",
  "kbbi_raw","kbbi_invalid","bio_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","bio_chl_missing")
BIO_LEVEL<-c("rbd","kbbi","bbp_551","bbp_morel_550","bbp_ratio_morel","bbp_deficit","nlw_667","nlw_678","cannizzaro_kbrevis")
bio_cols<-function(cols)unique(c(intersect(BIO_LEVEL,cols),grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_",cols,value=TRUE)))
merge_tiny<-function(b,m=MIN_BLK){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}
impute_with_flag<-function(tr,te,fc){for(col in fc){nc<-paste0(col,"_is_missing");tr[[nc]]<-as.integer(is.na(tr[[col]]));te[[nc]]<-as.integer(is.na(te[[col]]));md<-median(tr[[col]],na.rm=TRUE);if(is.na(md))md<-0;set(tr,which(is.na(tr[[col]])),col,md);set(te,which(is.na(te[[col]])),col,md)};list(train=tr,test=te)}

dt<-as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[["date_T"]]<-as.Date(as.character(dt[["date_T"]]));dt[["year"]]<-as.integer(substr(dt$date_T,1,4))
for(f in LOG_FEATURES) if(f%in%names(dt)){if(f=="nflh_mean")dt[,(f):=sign(get(f))*log1p(abs(get(f)))] else dt[,(f):=log1p(pmax(get(f),0))]}
lab<-as.data.table(read_parquet(proj_path(cfg$paths$habsos_labels)));lab[,sample_date:=as.Date(sample_date)]
ref<-lab[sample_date>=as.Date("2003-01-01"),.(cell_id,sample_date,max_count)]
cxy<-unique(dt[,.(cell_id,centroid_lon,centroid_lat)]);pxy<-sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]))
cxy[,`:=`(X=pxy[,1],Y=pxy[,2])];setkey(cxy,cell_id)
cells_within<-function(trc,tec,R){if(R<=0)return(character(0));tr<-cxy[.(unique(trc))];te<-cxy[.(unique(tec))];if(!nrow(te)||!nrow(tr))return(character(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}

cumforest<-function(tr,te,fc,tgt,seed_off){ # binary prob forest on tgt(0/1); returns test P(tgt=1)
  d<-copy(tr[,fc,with=FALSE]); d[,y:=factor(tgt,levels=c(0,1))]
  np<-sum(tgt==1);nn<-sum(tgt==0); if(np==0||nn==0) return(rep(mean(tgt),nrow(te)))
  w<-ifelse(tgt==1,nn/np,1.0)
  rf<-ranger(y~.,data=d,num.trees=NUM_TREES,probability=TRUE,case.weights=w,num.threads=1L,seed=seed_off)
  predict(rf,data=te[,fc,with=FALSE])$predictions[,"1"]
}

out<-list()
for(H in HORIZONS){
  tc<-paste0("HAB_H",H); h<-dt[!is.na(get(tc))]; h[,block_cv:=merge_tiny(spatial_block_tiger)]
  sh<-ref[,.(cell_id,date_T=sample_date-H,mc=max_count)]; h<-merge(h,sh,by=c("cell_id","date_T"),all.x=TRUE); h[,sev:=fwc(mc)]
  stopifnot(h[!is.na(get(tc)),all((sev>=3L)==(get(tc)==1L))])
  excl_H<-c(ALWAYS_EXCLUDE,setdiff(paste0("HAB_H",HORIZONS),tc))
  feat<-setdiff(names(h),c(excl_H,tc,"year","block_cv","mc","sev"))
  feat<-setdiff(feat,bio_cols(feat))   # adopted, no bio, no neighbours
  set.seed(SEED+H); pos<-which(h[[tc]]==1L);neg<-which(h[[tc]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))));rte<-setdiff(seq_len(nrow(h)),rtr)
  ttr<-which(h$year<CUT_YR);tte<-which(h$year>=CUT_YR);if(EMBARGO_ON){k<-(h$date_T[ttr]+H)<CUT_DATE;ttr<-ttr[k]}
  bs<-sort(table(h$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(h);nh<-max(1L,min(which(cum>=0.15)));hb<-names(bs)[seq_len(nh)]
  ste<-which(h$block_cv%in%hb);str<-setdiff(seq_len(nrow(h)),ste);if(BUFFER_M>0){dc<-cells_within(h$cell_id[str],h$cell_id[ste],BUFFER_M);str<-str[!(h$cell_id[str]%in%dc)]}
  splits<-list(random=list(tr=rtr,te=rte),temporal=list(tr=ttr,te=tte),spatial=list(tr=str,te=ste))
  na_cols<-feat[vapply(feat,function(cn)anyNA(h[[cn]]),logical(1))]
  for(sp in names(splits)){
    tr_idx<-splits[[sp]]$tr;te_idx<-splits[[sp]]$te;if(length(tr_idx)<20||length(te_idx)<10)next
    so<-SEED+H*100L+which(names(splits)==sp)
    tr<-copy(h[tr_idx,c(feat,"sev"),with=FALSE]);te<-copy(h[te_idx,c(feat,"sev"),with=FALSE])
    im<-impute_with_flag(tr,te,na_cols);tr<-im$train;te<-im$test; fc<-setdiff(names(tr),"sev")
    sev_tr<-tr$sev
    # (A) ordered forest: cumulative P(sev>=k)
    pk<-sapply(1:4,function(k) cumforest(tr,te,fc,as.integer(sev_tr>=k),so+k))
    colnames(pk)<-paste0("p_ge",1:4)
    pm<-pk; for(k in 2:4) pm[,k]<-pmin(pm[,k],pm[,k-1])         # monotone clamp for class probs
    cp<-cbind(1-pm[,1], pm[,1]-pm[,2], pm[,2]-pm[,3], pm[,3]-pm[,4], pm[,4]); cp[cp<0]<-0; cp<-cp/rowSums(cp)
    pred_ord<-max.col(cp)-1L
    # (B) multiclass ranger
    trm<-copy(tr); trm[,sev:=factor(sev,levels=0:4)]
    cw<-as.numeric(1/table(factor(sev_tr,levels=0:4))[as.character(sev_tr)]); cw[!is.finite(cw)]<-0
    rfm<-ranger(sev~.,data=trm,num.trees=NUM_TREES,probability=TRUE,case.weights=cw,num.threads=1L,seed=so)
    prm<-predict(rfm,data=te[,fc,with=FALSE])$predictions
    for(cl in as.character(0:4)) if(!cl%in%colnames(prm)) prm<-cbind(prm,setNames(data.frame(rep(0,nrow(prm))),cl))
    prm<-prm[,as.character(0:4)]
    pred_mc<-max.col(prm)-1L; p_bin_mc<-prm[,"3"]+prm[,"4"]
    out[[length(out)+1]]<-data.table(horizon=H,split=sp,cell_id=h$cell_id[te_idx],date_T=h$date_T[te_idx],
      sev=te$sev, act_bin=as.integer(te$sev>=3L),
      p_ge3_ord=pk[,"p_ge3"], p_bin_mc=p_bin_mc, pred_class_ord=pred_ord, pred_class_mc=pred_mc,
      p_ge1_ord=pk[,"p_ge1"], p_ge2_ord=pk[,"p_ge2"], p_ge4_ord=pk[,"p_ge4"])
    message("[E-06] H=",H," ",sp," trained (ordered-forest 4x + multiclass; n_test=",length(te_idx),")")
  }
}
res<-rbindlist(out); write_parquet(res, proj_path("outputs/tables/predictions_e06.parquet"))
cat("\n[E-06] predictions_e06.parquet written:",nrow(res),"rows\n")
