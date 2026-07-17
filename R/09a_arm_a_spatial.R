# ============================================================
# FILE:       R/09a_arm_a_spatial.R
# PURPOSE:    M3-1 — Arm A spatial split (never run). A whole-shelf surface asserts the
#             model generalises to unseen cells; this tests it. Arm A has NO ring-1
#             neighbour features, so the shared 20 km buffer already exceeds the ~14 km
#             cell reach (M1 §2.7) — config NOT bumped. Reports PR/p@r80/ROC with
#             block-bootstrap CIs, spatial vs temporal, carrying the D-09 prevalence
#             confound (the TIGER block holdout isolates Collier County, the hotspot).
# INPUTS:     data/processed/model_dataset_arm_a.parquet ; config split_repair.*
# OUTPUTS:    appends model_results.csv (arm_a_spatial rows), bootstrap_cis_pC.csv,
#             dumps predictions_arm_a_spatial.parquet. best_model.rds untouched.
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })
SEED<-42L; NUM_TREES<-500L; HORIZONS<-c(1,3,5,7,14); MIN_BLOCK_ROWS<-5L
BUFFER_M <- as.numeric(cfg$split_repair$spatial_buffer_m %||% 0)   # 20000, NOT bumped
LOG_FEATURES<-c("chlor_a_mean","nflh_mean","Kd_490_mean"); N_BOOT<-1000L; BLOCK_L<-30L; Q<-c(0.025,0.975)
roc_mw<-function(p,a){if(length(unique(a))<2)return(NA_real_);a<-as.integer(a);np<-sum(a==1);nn<-sum(a==0);if(np==0||nn==0)return(NA_real_);r<-rank(p);(sum(r[a==1])-np*(np+1)/2)/(np*nn)}
ap_fn<-function(p,a){if(length(unique(a))<2)return(NA_real_);a<-as.integer(a);o<-order(p,decreasing=TRUE);pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac);keep<-c(which(diff(pp)!=0),length(pp));prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac);sum((rec-c(0,rec[-length(rec)]))*prec)}
p80_fn<-function(p,a,tr=0.80){if(length(unique(a))<2)return(NA_real_);a<-as.integer(a);o<-order(p,decreasing=TRUE);pp<-p[o];ac<-a[o];tp<-cumsum(ac);fp<-cumsum(1L-ac);keep<-c(which(diff(pp)!=0),length(pp));prec<-tp[keep]/(tp[keep]+fp[keep]);rec<-tp[keep]/sum(ac);h<-which(rec>=tr);if(!length(h))return(NA_real_);prec[h[1]]}
impute_with_flag<-function(tr,te,fc){for(col in fc){nc<-paste0(col,"_is_missing");tr[[nc]]<-as.integer(is.na(tr[[col]]));te[[nc]]<-as.integer(is.na(te[[col]]));md<-median(tr[[col]],na.rm=TRUE);if(is.na(md))md<-0;set(tr,which(is.na(tr[[col]])),col,md);set(te,which(is.na(te[[col]])),col,md)};list(train=tr,test=te)}
merge_tiny<-function(b,m=MIN_BLOCK_ROWS){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}

B<-as.data.table(read_parquet("data/processed/model_dataset_arm_a.parquet")); B[,date_T:=as.Date(date_T)]
for(lc in c("rbd_detect","kbbi_kbrevis","cannizzaro_kbrevis")) if(lc%in%names(B)) B[,(lc):=as.integer(get(lc))]
for(f in LOG_FEATURES) if(f%in%names(B)){if(f=="nflh_mean") B[,(f):=sign(get(f))*log1p(abs(get(f)))] else B[,(f):=log1p(pmax(get(f),0))]}
EXCL<-c("cell_id","date_T","horizon","label","label_date","snap_date","kbbi_raw","county_fips","county_name","state_fips","spatial_block_tiger","precip_mm","salinity_pss","chl_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","kbbi_invalid","sat_feature_filled","cloud_flag","sat_IS_PLACEHOLDER","wind_is_placeholder","precip_is_placeholder","salinity_is_placeholder","static_IS_PLACEHOLDER")
feat_a<-setdiff(names(B),EXCL)

# EPSG:5070 centroids for the buffer (identical to 07d/07c)
cxy<-unique(B[,.(cell_id,centroid_lon,centroid_lat)])
pxy<-sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]))
cxy[,`:=`(X=pxy[,1],Y=pxy[,2])]; setkey(cxy,cell_id)
cells_within<-function(trc,tec,R){if(R<=0)return(integer(0));tr<-cxy[.(unique(trc))];te<-cxy[.(unique(tec))];if(!nrow(te)||!nrow(tr))return(integer(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}

fitp<-function(d,tr_idx,te_idx,so){na<-feat_a[vapply(feat_a,function(cn)anyNA(d[[cn]]),logical(1))]
  tr<-copy(d[tr_idx,c(feat_a,"label"),with=FALSE]);te<-copy(d[te_idx,c(feat_a,"label"),with=FALSE])
  im<-impute_with_flag(tr,te,na);tr<-im$train;te<-im$test
  np<-sum(tr$label==1L);nn<-sum(tr$label==0L);w<-ifelse(tr$label==1L,nn/np,1.0);set(tr,j="label",value=factor(tr$label,levels=c(0,1)))
  rf<-ranger(label~.,data=tr,num.trees=NUM_TREES,probability=TRUE,case.weights=w,num.threads=1L,seed=so)
  predict(rf,data=te)$predictions[,"1"]}

out<-list();pt<-list()
for(H in HORIZONS){ d<-B[horizon==H]; d[,block_cv:=merge_tiny(spatial_block_tiger)]
  bs<-sort(table(d$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(d);nh<-max(1L,min(which(cum>=0.15)))
  hb<-names(bs)[seq_len(nh)]; ste<-which(d$block_cv%in%hb); str<-setdiff(seq_len(nrow(d)),ste)
  if(BUFFER_M>0){dc<-cells_within(d$cell_id[str],d$cell_id[ste],BUFFER_M); str<-str[!(d$cell_id[str]%in%dc)]}
  # residual test cells within buffer of train (must be 0 by construction for the report)
  resid<-length(intersect(cells_within(d$cell_id[ste],d$cell_id[str],BUFFER_M),d$cell_id[ste]))
  so<-SEED+H*100L+3L  # spatial split index
  prob<-fitp(d,str,ste,so); act<-d$label[ste]
  out[[length(out)+1]]<-data.table(horizon=H,split="spatial",model="arm_a_spatial",cell_id=d$cell_id[ste],date_T=d$date_T[ste],prob=prob,act=as.integer(act))
  pt[[length(pt)+1]]<-data.table(horizon=H,split="spatial",model="arm_a_spatial",pr_auc=round(ap_fn(prob,act),4),roc_auc=round(roc_mw(prob,act),4),prec_at_recall80=round(p80_fn(prob,act),4),n_test=length(act),n_pos=sum(act==1L),n_train=length(str))
  cat(sprintf("H=%2d spatial: n_train=%d n_test=%d test_base=%.4f (train_base=%.4f) resid_buffer_cells=%d held_blocks=%d\n",
      H,length(str),length(ste),mean(act==1L),mean(d$label[str]==1L),resid,nh))
}
preds<-rbindlist(out);ptab<-rbindlist(pt)
write_parquet(preds,"outputs/tables/predictions_arm_a_spatial.parquet")
mr<-fread("outputs/tables/model_results.csv");for(c in setdiff(names(mr),names(ptab)))ptab[,(c):=NA];ptab<-ptab[,names(mr),with=FALSE]
fwrite(rbind(mr,ptab),"outputs/tables/model_results.csv");cat("appended",nrow(ptab),"spatial rows to model_results.csv\n")

# block-bootstrap level CIs on the spatial test set (per H) for PR/ROC/p80
ci<-function(v){v<-v[is.finite(v)];c(lo=unname(quantile(v,Q[1])),hi=unname(quantile(v,Q[2])),n=length(v))}
br<-list()
for(H in HORIZONS){w<-preds[horizon==H];d0<-min(w$date_T);w[,blk:=as.integer(as.integer(date_T-d0)%/%BLOCK_L)];setkey(w,blk);blks<-unique(w$blk);nb<-length(blks)
  for(met in c("pr","roc","p80")){fn<-switch(met,pr=ap_fn,roc=roc_mw,p80=p80_fn);set.seed(SEED);v<-numeric(N_BOOT)
    for(i in seq_len(N_BOOT)){r<-w[.(sample(blks,nb,replace=TRUE)),allow.cartesian=TRUE];v[i]<-fn(r$prob,r$act)}
    c95<-ci(v);br[[length(br)+1]]<-data.table(horizon=H,split="spatial",quantity=paste0("arm_a_spatial_",met),point=round(fn(w$prob,w$act),4),ci_lo=round(c95["lo"],4),ci_hi=round(c95["hi"],4),excludes_0=TRUE,block_days=BLOCK_L,n_boot=c95["n"])}}
bt<-rbindlist(br);bc<-fread("outputs/tables/bootstrap_cis_pC.csv");fwrite(rbind(bc,bt[,names(bc),with=FALSE]),"outputs/tables/bootstrap_cis_pC.csv")
cat("appended",nrow(bt),"spatial CI rows\n=== 09a DONE ===\n")
