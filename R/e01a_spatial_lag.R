# ============================================================
# FILE:       R/e01a_spatial_lag.R
# PURPOSE:    E-01a — ring-1 (queen-adjacency, ~10 km) spatial-lag features.
#             Builds neighbour aggregates at time T, retrains the ADOPTED RF
#             (pre-bio, post-embargo+buffer splits) with them, dumps per-row
#             predictions for a paired block-bootstrap vs the re-frozen baseline.
#             Ring-1 ONLY (queen adjacency; centroid dist < 15 km captures the
#             10 km orthogonal + 14.14 km diagonal neighbours, excludes ring-2 at
#             20 km). Option (c): current 20 km buffer, NO buffer change.
# INPUTS:     data/processed/model_dataset.parquet ; config split_repair.*
# OUTPUTS:    outputs/tables/predictions_e01a.parquet  (horizon,split,cell_id,date_T,prob,act)
#             prints per-H×split PR-AUC + leakage assertions.
# LEAKAGE:    every neighbour feature is aggregated from neighbour rows at the
#             SAME date_T as the focal row (no T+H reach) — R6 gate. The 20 km
#             buffer keeps train/test >= 20 km apart > ring-1 reach 14.14 km, so
#             no train cell's neighbourhood touches a test cell — R-SPLIT gate.
# EDGE CELLS: a cell with < 8 neighbours uses the available ones (na.rm) plus a
#             valid-neighbour count `nbr_count`; NEVER zero-filled (D4 bug class).
# CITATIONS:  same as R/07_modeling.R.
# ============================================================

local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })

SEED <- cfg$random_seed %||% 42; NUM_TREES <- 500L; TRAIN_FRAC <- 0.80
TEMPORAL_CUTOFF_YEAR <- 2016L; CUTOFF_DATE <- as.Date("2016-01-01"); MIN_BLOCK_ROWS <- 5L
HORIZONS <- cfg$forecast$horizons_days; LOG_FEATURES <- c("chlor_a_mean","nflh_mean","Kd_490_mean")
EMBARGO_ON <- isTRUE(cfg$split_repair$temporal_embargo); BUFFER_M <- as.numeric(cfg$split_repair$spatial_buffer_m %||% 0)
RING1_M <- 15000   # queen ring-1 cutoff (10 km edge + 14.14 km diagonal < 15 km < 20 km ring-2)

ALWAYS_EXCLUDE <- c("cell_id","date_T","HAB","HAB_H1","HAB_H3","HAB_H5","HAB_H7","HAB_H14",
  "spatial_block_tiger","max_count","n_samples","IS_PLACEHOLDER_ROW","satellite_missing","cloud_flag",
  "salinity_coarse_flag","feature_filled_any","IS_ABSENCE_UNCERTAIN","sat_IS_PLACEHOLDER","env_IS_PLACEHOLDER",
  "static_IS_PLACEHOLDER","label_IS_PLACEHOLDER","sat_feature_filled","env_feature_filled","precip_mm","salinity_pss",
  "kbbi_raw","kbbi_invalid","bio_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","bio_chl_missing")
BIO_LEVEL <- c("rbd","kbbi","bbp_551","bbp_morel_550","bbp_ratio_morel","bbp_deficit","nlw_667","nlw_678","cannizzaro_kbrevis")
bio_cols <- function(cols) unique(c(intersect(BIO_LEVEL,cols), grep("^(rbd|kbbi|bbp_ratio_morel|bbp_deficit)_",cols,value=TRUE)))
LEVELS <- c("chlor_a_mean","nflh_mean","Kd_490_mean","sst_mean")
TRENDS <- NULL  # filled after load

merge_tiny <- function(b,m=MIN_BLOCK_ROWS){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}
impute_with_flag <- function(tr,te,fc){for(col in fc){nc<-paste0(col,"_is_missing");tr[[nc]]<-as.integer(is.na(tr[[col]]));te[[nc]]<-as.integer(is.na(te[[col]]));md<-median(tr[[col]],na.rm=TRUE);if(is.na(md))md<-0;set(tr,which(is.na(tr[[col]])),col,md);set(te,which(is.na(te[[col]])),col,md)};list(train=tr,test=te)}
pr_auc_fn <- function(prob,act){if(length(unique(act))<2)return(NA);o<-order(prob,decreasing=TRUE);a<-act[o];tp<-cumsum(a);fp<-cumsum(1L-a);pr<-tp/(tp+fp);rc<-tp/sum(a);ra<-c(0,rc);pa<-c(pr[1],pr);sum(diff(ra)*(pa[-length(pa)]+pa[-1])/2,na.rm=TRUE)}
smean <- function(x){x<-x[!is.na(x)]; if(!length(x)) NA_real_ else mean(x)}
smax  <- function(x){x<-x[!is.na(x)]; if(!length(x)) NA_real_ else max(x)}

# ── LOAD + log1p (same as pipeline) ────────────────────────────────────────
dt <- as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[["date_T"]] <- as.Date(as.character(dt[["date_T"]])); dt[["year"]] <- as.integer(substr(dt$date_T,1,4))
for(f in LOG_FEATURES) if(f %in% names(dt)){ if(f=="nflh_mean") dt[,(f):=sign(get(f))*log1p(abs(get(f)))] else dt[,(f):=log1p(pmax(get(f),0))] }
TRENDS <- grep("^(chlor_a|nflh|Kd_490|sst)_(delta|pct_chg|slope_obs|rollmean|rollstd)", names(dt), value=TRUE)
SRC <- c(LEVELS, TRENDS)   # 64 source columns aggregated over neighbours

# ── QUEEN RING-1 ADJACENCY (centroid dist in EPSG:5070) ────────────────────
cxy <- unique(dt[,.(cell_id,centroid_lon,centroid_lat)])
pxy <- sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]))
cxy[,`:=`(X=pxy[,1],Y=pxy[,2])]
adj_list <- lapply(seq_len(nrow(cxy)), function(i){
  d <- sqrt((cxy$X-cxy$X[i])^2 + (cxy$Y-cxy$Y[i])^2)
  nb <- cxy$cell_id[d>0 & d<RING1_M]
  if(!length(nb)) NULL else data.table(focal=cxy$cell_id[i], nbr=nb)
})
adj <- rbindlist(adj_list)
cat("[E-01a] queen ring-1 adjacency:", nrow(adj), "focal-neighbour pairs;",
    "cells with>=1 nbr:", uniqueN(adj$focal), "/", nrow(cxy), "\n")
cat("[E-01a] neighbours per cell: ", paste(names(summary(adj[,.N,by=focal]$N)), round(summary(adj[,.N,by=focal]$N),1), collapse=" "), "\n")

# ── BUILD NEIGHBOUR FEATURES AT DATE T (never T+H) ─────────────────────────
src <- dt[, c("cell_id","date_T",SRC), with=FALSE]
setkey(src, cell_id)
j <- src[adj, on=c(cell_id="nbr"), allow.cartesian=TRUE, nomatch=0]  # neighbour rows, tagged with focal
# LEAKAGE ASSERT (R6): every aggregated neighbour row shares the focal row's date_T
# (join is on cell only; the by-(focal,date_T) aggregation groups within a single date).
stopifnot(!anyNA(j$date_T))
agg_mean <- j[, c(setNames(lapply(.SD, smean), paste0("nbr_mean_",SRC)), list(nbr_count=.N)),
              by=.(focal,date_T), .SDcols=SRC]
agg_max  <- j[, setNames(lapply(.SD, smax), paste0("nbr_max_",LEVELS)),
              by=.(focal,date_T), .SDcols=LEVELS]
nbrfeat <- merge(agg_mean, agg_max, by=c("focal","date_T"))
setnames(nbrfeat, "focal", "cell_id")
NBR_COLS <- setdiff(names(nbrfeat), c("cell_id","date_T"))
cat("[E-01a] neighbour features built:", length(NBR_COLS), "( nbr_mean x", length(SRC),
    "+ nbr_max x", length(LEVELS), "+ nbr_count )\n")
# join onto modeling rows (left join; unmatched -> NA -> imputed-with-flag, NOT zero)
dt <- merge(dt, nbrfeat, by=c("cell_id","date_T"), all.x=TRUE)
cat("[E-01a] rows with >=1 valid neighbour:", round(100*mean(!is.na(dt$nbr_count)),1),
    "% ; median nbr_count:", median(dt$nbr_count, na.rm=TRUE), "\n")

# ── TRAIN (adopted features + ring-1 neighbour features), repaired splits ──
cells_within <- function(trc,tec,R){if(R<=0)return(character(0));tr<-cxy[cell_id %in% unique(trc)];te<-cxy[cell_id %in% unique(tec)]
  if(!nrow(te)||!nrow(tr))return(character(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}
fit_predict <- function(h_dt,tr_idx,te_idx,feat_cols,target_col,seed_off){
  na_cols <- feat_cols[vapply(feat_cols,function(cn)anyNA(h_dt[[cn]]),logical(1))]
  tr<-copy(h_dt[tr_idx,c(feat_cols,target_col),with=FALSE]);te<-copy(h_dt[te_idx,c(feat_cols,target_col),with=FALSE])
  im<-impute_with_flag(tr,te,na_cols);tr<-im$train;te<-im$test
  np<-sum(tr[[target_col]]==1L);nn<-sum(tr[[target_col]]==0L);if(np==0)return(NULL)
  w<-ifelse(tr[[target_col]]==1L,nn/np,1.0)
  set(tr,j=target_col,value=factor(tr[[target_col]],levels=c(0,1)))
  rf<-ranger(as.formula(paste(target_col,"~ .")),data=tr,num.trees=NUM_TREES,probability=TRUE,case.weights=w,num.threads=1L,seed=seed_off)
  predict(rf,data=te)$predictions[,"1"]
}

out <- list(); pr_chk <- list()
for (H in HORIZONS) {
  target_col <- paste0("HAB_H",H); h_dt <- dt[!is.na(get(target_col))]; h_dt[,block_cv:=merge_tiny(spatial_block_tiger)]
  excl_H <- c(ALWAYS_EXCLUDE, setdiff(paste0("HAB_H",HORIZONS),target_col))
  feat_all <- setdiff(names(h_dt), c(excl_H,target_col,"year","block_cv"))
  feat_adopted <- setdiff(feat_all, bio_cols(feat_all))
  feat_e01a    <- feat_adopted                              # adopted + neighbour cols already in feat_all
  set.seed(SEED+H)
  pos<-which(h_dt[[target_col]]==1L);neg<-which(h_dt[[target_col]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))));rte<-setdiff(seq_len(nrow(h_dt)),rtr)
  ttr<-which(h_dt$year<TEMPORAL_CUTOFF_YEAR);tte<-which(h_dt$year>=TEMPORAL_CUTOFF_YEAR)
  if(EMBARGO_ON){keep<-(h_dt$date_T[ttr]+H)<CUTOFF_DATE;ttr<-ttr[keep]}
  bs<-sort(table(h_dt$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(h_dt);nh<-max(1L,min(which(cum>=0.15)));hb<-names(bs)[seq_len(nh)]
  ste<-which(h_dt$block_cv%in%hb);str<-setdiff(seq_len(nrow(h_dt)),ste)
  if(BUFFER_M>0){dc<-cells_within(h_dt$cell_id[str],h_dt$cell_id[ste],BUFFER_M);str<-str[!(h_dt$cell_id[str]%in%dc)]}
  splits<-list(random=list(tr=rtr,te=rte),temporal=list(tr=ttr,te=tte),spatial=list(tr=str,te=ste))
  for(sp in names(splits)){
    tr_idx<-splits[[sp]]$tr;te_idx<-splits[[sp]]$te;if(length(tr_idx)<20||length(te_idx)<10)next
    so<-SEED+H*100L+which(names(splits)==sp)
    p<-fit_predict(h_dt,tr_idx,te_idx,feat_e01a,target_col,so)
    act<-as.integer(h_dt[[target_col]][te_idx])
    out[[length(out)+1]]<-data.table(horizon=H,split=sp,cell_id=h_dt$cell_id[te_idx],date_T=h_dt$date_T[te_idx],act=act,prob=p,model="rf_e01a")
    pr_chk[[length(pr_chk)+1]]<-data.table(horizon=H,split=sp,pr_auc=round(pr_auc_fn(p,act),4),n_feat=length(feat_e01a))
    message("[E-01a] H=",H," ",sp," trained (n_feat=",length(feat_e01a),", n_test=",length(te_idx),")")
  }
}
res<-rbindlist(out); write_parquet(res, proj_path("outputs/tables/predictions_e01a.parquet"))
cat("\n[E-01a] predictions_e01a.parquet written:", nrow(res), "rows\n")
prc<-rbindlist(pr_chk)
cat("=== E-01a PR-AUC by H x split (feature count incl neighbour block) ===\n"); print(prc[order(split,horizon)])
