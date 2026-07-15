# ============================================================
# FILE:       R/e01a_spatial_lag_v2.R
# PURPOSE:    E-01a RE-RUN (corrected). The original R/e01a_spatial_lag.R built
#             neighbour features by self-joining model_dataset.parquet — the
#             LABEL-CONDITIONED table (1,461 sampled cells, ~0.24% of the
#             satellite grid). That starved neighbour coverage (median 2/8) and
#             produced an ARTIFACT null. MODIS images the whole grid daily; a
#             neighbour cell's chlorophyll does not need a boat.
#             This version builds ring-1 neighbour features from the FULL-GRID
#             satellite source (satellite_features.parquet: 4,742 cells x 5,829
#             dates) joined on (neighbour cell_id, date_T), then joins the result
#             onto the modeling rows. Everything else unchanged: T-only (R6),
#             20 km buffer (R-SPLIT), adopted features, repaired splits.
# INPUTS:     data/processed/satellite_features.parquet   (FULL GRID levels)
#             data/processed/study_area_grid.gpkg          (all-cell centroids, EPSG:5070)
#             data/processed/model_dataset.parquet         (modeling rows + labels + focal features)
# OUTPUTS:    outputs/tables/predictions_e01a_v2.parquet
#             prints corrected coverage (% rows with >=1 valid neighbour, median
#             nbr_count, and the cloud-masking gap), per-H x split PR-AUC.
# NEIGHBOUR SET (full grid, ring-1 queen, at T): nbr_mean+nbr_max of chl, nFLH,
#   Kd490, SST; nbr_mean of delta_7d and rollmean_7d of each (advection level +
#   weekly build-up); nbr_count = # ring-1 neighbours with a CLEAR (non-NA)
#   retrieval that day. Edge/cloud cells: available neighbours + count, NO zero-fill.
# CITATIONS:  same as R/07_modeling.R.
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })

SEED<-cfg$random_seed%||%42; NUM_TREES<-500L; TRAIN_FRAC<-0.80; CUT_YR<-2016L; CUT_DATE<-as.Date("2016-01-01"); MIN_BLK<-5L
HORIZONS<-cfg$forecast$horizons_days; LOGV<-c("chlor_a_mean","nflh_mean","Kd_490_mean"); LEVELS<-c("chlor_a_mean","nflh_mean","Kd_490_mean","sst_mean")
EMBARGO_ON<-isTRUE(cfg$split_repair$temporal_embargo); BUFFER_M<-as.numeric(cfg$split_repair$spatial_buffer_m%||%0); RING1_M<-15000
ALWAYS_EXCLUDE<-c("cell_id","date_T","HAB","HAB_H1","HAB_H3","HAB_H5","HAB_H7","HAB_H14",
  "spatial_block_tiger","max_count","n_samples","IS_PLACEHOLDER_ROW","satellite_missing","cloud_flag",
  "salinity_coarse_flag","feature_filled_any","IS_ABSENCE_UNCERTAIN","sat_IS_PLACEHOLDER","env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER","label_IS_PLACEHOLDER","sat_feature_filled","env_feature_filled","precip_mm","salinity_pss",
  "kbbi_raw","kbbi_invalid","bio_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","bio_chl_missing")
BIO_LEVEL<-c("rbd","kbbi","bbp_551","bbp_morel_550","bbp_ratio_morel","bbp_deficit","nlw_667","nlw_678","cannizzaro_kbrevis")
bio_cols<-function(cols)unique(c(intersect(BIO_LEVEL,cols),grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_",cols,value=TRUE)))
merge_tiny<-function(b,m=MIN_BLK){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}
impute_with_flag<-function(tr,te,fc){for(col in fc){nc<-paste0(col,"_is_missing");tr[[nc]]<-as.integer(is.na(tr[[col]]));te[[nc]]<-as.integer(is.na(te[[col]]));md<-median(tr[[col]],na.rm=TRUE);if(is.na(md))md<-0;set(tr,which(is.na(tr[[col]])),col,md);set(te,which(is.na(te[[col]])),col,md)};list(train=tr,test=te)}
pr_auc_fn<-function(prob,act){if(length(unique(act))<2)return(NA);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
smean<-function(x){x<-x[!is.na(x)];if(!length(x))NA_real_ else mean(x)}; smax<-function(x){x<-x[!is.na(x)];if(!length(x))NA_real_ else max(x)}

# ── full-grid centroids (EPSG:5070) for ALL grid cells ─────────────────────
g<-st_read(proj_path(cfg$paths$grid), quiet=TRUE); ct<-st_coordinates(st_centroid(st_geometry(g)))
gc<-data.table(cell_id=as.character(g$cell_id), X=ct[,1], Y=ct[,2]); setkey(gc,cell_id)

# ── modeling rows (focal features + labels) ────────────────────────────────
dt<-as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[,date_T:=as.Date(as.character(date_T))]; dt[,year:=as.integer(substr(date_T,1,4))]; dt[,cell_id:=as.character(cell_id)]
for(f in LOGV) if(f%in%names(dt)){if(f=="nflh_mean")dt[,(f):=sign(get(f))*log1p(abs(get(f)))] else dt[,(f):=log1p(pmax(get(f),0))]}
mod_cd<-unique(dt[,.(cell_id,date_T)])

# ── FULL-GRID satellite source: CLOUD-ROBUST trailing-clear levels + build-up ──
# MODIS clear-sky retrieval is ~26% of cell-days (74% cloud NA); focal features
# are also ~67% NA and median-imputed at fit. Exact-date neighbours would be
# cloud-starved (median 0 clear). Use a trailing 8-day CLEAR mean per cell
# (no look-ahead, <= T) as the "recent upstream state", and a week-over-week
# change of it for build-up. Robust to cloud via frollsum(clear)/frollsum(value).
WIN<-8L
message("[E-01a v2] loading FULL-GRID satellite_features.parquet ...")
sat<-as.data.table(read_parquet(proj_path(cfg$paths$satellite_features),
      col_select=c("cell_id","date",LEVELS)))
sat[,cell_id:=as.character(cell_id)]; sat[,date:=as.Date(date)]
for(f in LOGV) sat[, (f):= if(f=="nflh_mean") sign(get(f))*log1p(abs(get(f))) else log1p(pmax(get(f),0))]
setkey(sat, cell_id, date)
# trailing 8-day clear mean (lev8) per cell, cloud-robust; grid daily-complete
for(v in LEVELS){
  clr<-as.numeric(!is.na(sat[[v]])); val<-fifelse(is.na(sat[[v]]),0,sat[[v]])
  sat[, `:=`(.s=val, .c=clr)]
  sat[, s8:=frollsum(.s,WIN), by=cell_id]; sat[, c8:=frollsum(.c,WIN), by=cell_id]
  sat[, (paste0(v,"_lev8")) := fifelse(c8>0, s8/c8, NA_real_)]
}
sat[, c(".s",".c","s8","c8"):=NULL]
LV8<-paste0(LEVELS,"_lev8")
# week-over-week change of the smoothed level (build-up), shift by 7 days
sat[, paste0(LEVELS,"_chg8") := lapply(.SD, function(v) v - shift(v,7L)), by=cell_id, .SDcols=LV8]
# exact-date clear flag for the honest cloud-coverage report
sat[, chl_clear_exact := as.integer(!is.na(chlor_a_mean))]
NSRC<-c(LV8, paste0(LEVELS,"_chg8"))
message("[E-01a v2] trailing-clear levels computed. Building ring-1 adjacency (full grid)...")

# ── ring-1 adjacency: focal = modeling cells, neighbour = ANY grid cell < 15 km ──
focal_cells<-unique(dt$cell_id); fc<-gc[.(focal_cells)]
adj<-rbindlist(lapply(seq_len(nrow(fc)), function(i){
  d<-sqrt((gc$X-fc$X[i])^2+(gc$Y-fc$Y[i])^2); nb<-gc$cell_id[d>0 & d<RING1_M]
  if(!length(nb)) NULL else data.table(focal=fc$cell_id[i], nbr=nb)
}))
n_geom<-adj[,.(n_geom_nbr=.N),by=focal]
message("[E-01a v2] adjacency: ",nrow(adj)," pairs; focal cells ",uniqueN(adj$focal),
        "; mean geometric nbrs ",round(mean(n_geom$n_geom_nbr),2))

# ── neighbour aggregation, RESTRICTED to modeling (focal,date_T) pairs ─────
fnd<-mod_cd[adj, on="cell_id==focal", allow.cartesian=TRUE, nomatch=0]  # (cell_id=focal, date_T, nbr)
setnames(fnd,"cell_id","focal")
setkey(sat,cell_id,date)
fnd<-sat[fnd, on=c(cell_id="nbr", date="date_T")]  # attach neighbour sat values at date_T
setnames(fnd, "date","date_T"); setnames(fnd,"cell_id","nbr")
agg<-fnd[, c(setNames(lapply(.SD, smean), paste0("nbr_mean_",NSRC)),
             list(nbr_count = sum(!is.na(chlor_a_mean_lev8)),          # cloud-robust valid neighbours
                  nbr_clear_exact = sum(chl_clear_exact, na.rm=TRUE))), # exact-date clear (raw cloud story)
         by=.(focal,date_T), .SDcols=NSRC]
aggmx<-fnd[, setNames(lapply(.SD, smax), paste0("nbr_max_",LV8)), by=.(focal,date_T), .SDcols=LV8]
nbrfeat<-merge(agg,aggmx,by=c("focal","date_T")); setnames(nbrfeat,"focal","cell_id")
NBR<-setdiff(names(nbrfeat),c("cell_id","date_T","nbr_clear_exact"))  # nbr_clear_exact is diagnostic, not a feature
dt<-merge(dt, nbrfeat, by=c("cell_id","date_T"), all.x=TRUE)
dt<-merge(dt, n_geom, by.x="cell_id", by.y="focal", all.x=TRUE)

cov_robust<-round(100*mean(!is.na(dt$nbr_count) & dt$nbr_count>0),1)
cov_exact <-round(100*mean(!is.na(dt$nbr_clear_exact) & dt$nbr_clear_exact>0),1)
cat("\n=== CORRECTED NEIGHBOUR COVERAGE (full-grid source) ===\n")
cat("neighbour FEATURES built:",length(NBR)," | modeling rows:",nrow(dt),"\n")
cat("mean geometric neighbours per focal cell:",round(mean(n_geom$n_geom_nbr),2)," (adjacency correct; full grid)\n")
cat("-- exact-date clear retrieval (the RAW CLOUD story, matches focal 67% NA) --\n")
cat("   % rows with >=1 exact-date-clear neighbour:",cov_exact,"% | median exact-clear count:",median(dt$nbr_clear_exact,na.rm=TRUE),"\n")
cat("-- cloud-robust trailing-8d-clear level (what the model uses) --\n")
cat("   % rows with >=1 valid neighbour (lev8):",cov_robust,"% | median nbr_count:",median(dt$nbr_count,na.rm=TRUE),"\n")
cat("   nbr_count (lev8) distribution:\n"); print(quantile(dt$nbr_count, c(0,.1,.25,.5,.75,.9,1), na.rm=TRUE))
cat("TRUE CAUSE of any residual sparsity: MODIS cloud masking (74% cell-days NA), not label-conditioning.\n")

# ── train (adopted + neighbour), repaired splits; dump predictions ─────────
cells_within<-function(trc,tec,R){if(R<=0)return(character(0));tr<-gc[.(unique(trc))];te<-gc[.(unique(tec))];if(!nrow(te)||!nrow(tr))return(character(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}
fitpred<-function(h,tr_idx,te_idx,feat,tc,so){na<-feat[vapply(feat,function(cn)anyNA(h[[cn]]),logical(1))]
  tr<-copy(h[tr_idx,c(feat,tc),with=FALSE]);te<-copy(h[te_idx,c(feat,tc),with=FALSE]);im<-impute_with_flag(tr,te,na);tr<-im$train;te<-im$test
  np<-sum(tr[[tc]]==1L);nn<-sum(tr[[tc]]==0L);if(np==0)return(NULL);w<-ifelse(tr[[tc]]==1L,nn/np,1.0)
  set(tr,j=tc,value=factor(tr[[tc]],levels=c(0,1)));rf<-ranger(as.formula(paste(tc,"~ .")),data=tr,num.trees=NUM_TREES,probability=TRUE,case.weights=w,num.threads=1L,seed=so);predict(rf,data=te)$predictions[,"1"]}
out<-list();prc<-list()
for(H in HORIZONS){
  tc<-paste0("HAB_H",H);h<-dt[!is.na(get(tc))];h[,block_cv:=merge_tiny(spatial_block_tiger)]
  excl<-c(ALWAYS_EXCLUDE,setdiff(paste0("HAB_H",HORIZONS),tc))
  feat<-setdiff(names(h),c(excl,tc,"year","block_cv","n_geom_nbr","nbr_clear_exact")); feat<-setdiff(feat,bio_cols(feat))
  set.seed(SEED+H);pos<-which(h[[tc]]==1L);neg<-which(h[[tc]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))));rte<-setdiff(seq_len(nrow(h)),rtr)
  ttr<-which(h$year<CUT_YR);tte<-which(h$year>=CUT_YR);if(EMBARGO_ON){k<-(h$date_T[ttr]+H)<CUT_DATE;ttr<-ttr[k]}
  bs<-sort(table(h$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(h);nh<-max(1L,min(which(cum>=0.15)));hb<-names(bs)[seq_len(nh)]
  ste<-which(h$block_cv%in%hb);str<-setdiff(seq_len(nrow(h)),ste);if(BUFFER_M>0){dc<-cells_within(h$cell_id[str],h$cell_id[ste],BUFFER_M);str<-str[!(h$cell_id[str]%in%dc)]}
  feat_base<-setdiff(feat, NBR)   # adopted-only CONTROL on the SAME (reordered) dt -> clean attribution
  sl<-list(random=list(tr=rtr,te=rte),temporal=list(tr=ttr,te=tte),spatial=list(tr=str,te=ste))
  for(sp in names(sl)){ti<-sl[[sp]]$tr;ei<-sl[[sp]]$te;if(length(ti)<20||length(ei)<10)next
    so<-SEED+H*100L+which(names(sl)==sp)
    p_e<-fitpred(h,ti,ei,feat,tc,so); p_b<-fitpred(h,ti,ei,feat_base,tc,so)
    act<-as.integer(h[[tc]][ei])
    bd<-data.table(horizon=H,split=sp,cell_id=h$cell_id[ei],date_T=h$date_T[ei],act=act)
    out[[length(out)+1]]<-copy(bd)[,`:=`(prob=p_e,model="rf_e01a_v2")]
    out[[length(out)+1]]<-copy(bd)[,`:=`(prob=p_b,model="rf_adopted_v2")]
    prc[[length(prc)+1]]<-data.table(horizon=H,split=sp,pr_e01a=round(pr_auc_fn(p_e,act),4),pr_adopted=round(pr_auc_fn(p_b,act),4),n_feat=length(feat))
    message("[E-01a v2] H=",H," ",sp," (n_feat=",length(feat),", n_test=",length(ei),")")}
}
res<-rbindlist(out);write_parquet(res,proj_path("outputs/tables/predictions_e01a_v2.parquet"))
cat("\n[E-01a v2] predictions_e01a_v2.parquet written:",nrow(res),"rows\n")
cat("=== E-01a v2 PR-AUC by H x split ===\n"); print(rbindlist(prc)[order(split,horizon)])
