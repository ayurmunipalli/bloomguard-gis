# ============================================================
# FILE:       R/07d_pC_predictions.R
# PURPOSE:    P0-C support. Dump per-row TEST predictions on the RE-FROZEN
#             (post-P0-A embargo, post-P0-B buffer) splits, so R can
#             block-bootstrap CIs. Mirrors R/07c_split_repair.R's pipeline
#             (same seed/hyperparameters/splits) and adds:
#               - rf_adopted : the shipped pre-bio RF (bio features excluded)
#               - rf_bio     : bio-inclusive RF (71 bio features added), SAME
#                              repaired splits -> paired bio-optical delta
#               - persistence: HAB at T
#             All three share the repaired test rows (paired bootstrap valid).
# INPUTS:     data/processed/model_dataset.parquet ; config split_repair.*
# OUTPUTS:    outputs/tables/predictions_pC.parquet
#             columns: horizon, split, model, cell_id, date_T, prob, act
# CITATIONS:  same as R/07_modeling.R.
# ============================================================

local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })

SEED <- cfg$random_seed %||% 42; NUM_TREES <- 500L; TRAIN_FRAC <- 0.80
TEMPORAL_CUTOFF_YEAR <- 2016L; CUTOFF_DATE <- as.Date("2016-01-01"); MIN_BLOCK_ROWS <- 5L
HORIZONS <- cfg$forecast$horizons_days; LOG_FEATURES <- c("chlor_a_mean","nflh_mean","Kd_490_mean")
EMBARGO_ON <- isTRUE(cfg$split_repair$temporal_embargo)
BUFFER_M   <- as.numeric(cfg$split_repair$spatial_buffer_m %||% 0)

ALWAYS_EXCLUDE <- c("cell_id","date_T","HAB","HAB_H1","HAB_H3","HAB_H5","HAB_H7","HAB_H14",
  "spatial_block_tiger","max_count","n_samples","IS_PLACEHOLDER_ROW","satellite_missing","cloud_flag",
  "salinity_coarse_flag","feature_filled_any","IS_ABSENCE_UNCERTAIN","sat_IS_PLACEHOLDER","env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER","label_IS_PLACEHOLDER","sat_feature_filled","env_feature_filled","precip_mm","salinity_pss",
  "kbbi_raw","kbbi_invalid","bio_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","bio_chl_missing")
BIO_LEVEL <- c("rbd","kbbi","bbp_551","bbp_morel_550","bbp_ratio_morel","bbp_deficit","nlw_667","nlw_678","cannizzaro_kbrevis")
bio_cols <- function(cols) unique(c(intersect(BIO_LEVEL,cols), grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_",cols,value=TRUE)))

merge_tiny <- function(b,m=MIN_BLOCK_ROWS){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}
impute_with_flag <- function(tr,te,fc){for(col in fc){nc<-paste0(col,"_is_missing");tr[[nc]]<-as.integer(is.na(tr[[col]]));te[[nc]]<-as.integer(is.na(te[[col]]));md<-median(tr[[col]],na.rm=TRUE);if(is.na(md))md<-0;set(tr,which(is.na(tr[[col]])),col,md);set(te,which(is.na(te[[col]])),col,md)};list(train=tr,test=te)}

dt <- as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[["date_T"]] <- as.Date(as.character(dt[["date_T"]])); dt[["year"]] <- as.integer(substr(dt$date_T,1,4))
for(f in LOG_FEATURES) if(f %in% names(dt)){ if(f=="nflh_mean") dt[,(f):=sign(get(f))*log1p(abs(get(f)))] else dt[,(f):=log1p(pmax(get(f),0))] }
cxy <- unique(dt[,.(cell_id,centroid_lon,centroid_lat)])
pxy <- sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]))
cxy[,`:=`(X=pxy[,1],Y=pxy[,2])]; setkey(cxy,cell_id)
cells_within <- function(trc,tec,R){ if(R<=0)return(character(0)); tr<-cxy[.(unique(trc))];te<-cxy[.(unique(tec))]
  if(!nrow(te)||!nrow(tr))return(character(0)); d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1)); tr$cell_id[d] }

fit_predict <- function(h_dt, tr_idx, te_idx, feat_cols, target_col, seed_off) {
  na_cols <- feat_cols[vapply(feat_cols,function(cn)anyNA(h_dt[[cn]]),logical(1))]
  tr <- copy(h_dt[tr_idx,c(feat_cols,target_col),with=FALSE]); te <- copy(h_dt[te_idx,c(feat_cols,target_col),with=FALSE])
  im <- impute_with_flag(tr,te,na_cols); tr<-im$train; te<-im$test
  np<-sum(tr[[target_col]]==1L); nn<-sum(tr[[target_col]]==0L); if(np==0)return(NULL)
  w <- ifelse(tr[[target_col]]==1L, nn/np, 1.0)
  set(tr,j=target_col,value=factor(tr[[target_col]],levels=c(0,1)))
  rf <- ranger(as.formula(paste(target_col,"~ .")),data=tr,num.trees=NUM_TREES,probability=TRUE,
               case.weights=w,num.threads=1L,seed=seed_off)
  predict(rf,data=te)$predictions[,"1"]
}

out <- list()
for (H in HORIZONS) {
  target_col <- paste0("HAB_H",H); h_dt <- dt[!is.na(get(target_col))]
  h_dt[,block_cv:=merge_tiny(spatial_block_tiger)]
  excl_H <- c(ALWAYS_EXCLUDE, setdiff(paste0("HAB_H",HORIZONS),target_col))
  feat_all <- setdiff(names(h_dt), c(excl_H,target_col,"year","block_cv"))
  feat_adopted <- setdiff(feat_all, bio_cols(feat_all))   # pre-bio (shipped)
  feat_bio     <- feat_all                                # bio-inclusive
  feat_nowind  <- setdiff(feat_adopted, grep("wind", feat_adopted, value=TRUE))  # for ERA5-wind-null CI
  set.seed(SEED+H)
  pos<-which(h_dt[[target_col]]==1L); neg<-which(h_dt[[target_col]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))))
  rte<-setdiff(seq_len(nrow(h_dt)),rtr)
  ttr<-which(h_dt$year<TEMPORAL_CUTOFF_YEAR); tte<-which(h_dt$year>=TEMPORAL_CUTOFF_YEAR)
  if(EMBARGO_ON){ keep<-(h_dt$date_T[ttr]+H)<CUTOFF_DATE; ttr<-ttr[keep] }
  bs<-sort(table(h_dt$block_cv),decreasing=TRUE); cum<-cumsum(bs)/nrow(h_dt); nh<-max(1L,min(which(cum>=0.15)))
  hb<-names(bs)[seq_len(nh)]; ste<-which(h_dt$block_cv%in%hb); str<-setdiff(seq_len(nrow(h_dt)),ste)
  if(BUFFER_M>0){ dc<-cells_within(h_dt$cell_id[str],h_dt$cell_id[ste],BUFFER_M); str<-str[!(h_dt$cell_id[str]%in%dc)] }
  splits <- list(random=list(tr=rtr,te=rte), temporal=list(tr=ttr,te=tte), spatial=list(tr=str,te=ste))
  for (sp in names(splits)) {
    tr_idx<-splits[[sp]]$tr; te_idx<-splits[[sp]]$te
    if(length(tr_idx)<20||length(te_idx)<10) next
    so <- SEED + H*100L + which(names(splits)==sp)
    p_ad  <- fit_predict(h_dt,tr_idx,te_idx,feat_adopted,target_col,so)
    p_bio <- fit_predict(h_dt,tr_idx,te_idx,feat_bio,target_col,so)
    p_nw  <- fit_predict(h_dt,tr_idx,te_idx,feat_nowind,target_col,so)
    act <- h_dt[[target_col]][te_idx]; pers <- as.numeric(h_dt[["HAB"]][te_idx])
    base <- data.table(horizon=H, split=sp, cell_id=h_dt$cell_id[te_idx],
                       date_T=h_dt$date_T[te_idx], act=as.integer(act))
    out[[length(out)+1]] <- copy(base)[, `:=`(model="rf_adopted",  prob=p_ad)]
    out[[length(out)+1]] <- copy(base)[, `:=`(model="rf_bio",      prob=p_bio)]
    out[[length(out)+1]] <- copy(base)[, `:=`(model="rf_nowind",   prob=p_nw)]
    out[[length(out)+1]] <- copy(base)[, `:=`(model="persistence", prob=pers)]
    message("[07d] H=",H," ",sp," done (n_test=",length(te_idx),")")
  }
}
res <- rbindlist(out, use.names=TRUE)
write_parquet(res, proj_path("outputs/tables/predictions_pC.parquet"))
message("[07d] predictions_pC.parquet written: ", nrow(res), " rows, models: ",
        paste(unique(res$model),collapse=","))
# quick PR-AUC check vs model_results.csv
pr_auc_fn <- function(prob,act){o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
chk <- res[model=="rf_adopted", .(pr_auc=round(pr_auc_fn(prob,act),4)), by=.(horizon,split)]
cat("\n=== rf_adopted PR-AUC from dumped preds (should match re-frozen model_results.csv) ===\n"); print(chk[order(split,horizon)])
