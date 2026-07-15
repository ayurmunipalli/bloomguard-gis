# ============================================================
# FILE:       R/e07_cloud_composite.R
# PURPOSE:    Cloud-robust temporal compositing of the FOCAL satellite features.
#             The pipeline leaves chl/nFLH/Kd490/SST ~67% NA (cloud) and
#             median-imputes at fit — constants on 2/3 of rows. Replace that with
#             a TRAILING composite: most recent clear-sky retrieval within a W-day
#             window ending at T (LOCF, W=8 frozen on training), + a days_since_clear
#             age feature per variable, + recomputed trends on the composited series.
#             Trailing only (<= T) — R6. Backward window never crosses into the
#             test period for training rows — R-SPLIT.
# INPUTS:     data/processed/satellite_features.parquet (full-grid daily levels)
#             data/processed/model_dataset.parquet (modeling rows; raw sat block)
#             config split_repair.* ; config trends.*
# OUTPUTS:    outputs/tables/predictions_e07.parquet (rf_composite + rf_raw_control,
#             same dt, repaired splits) ; prints coverage + R6/R-SPLIT gate evidence.
# CITATIONS:  R/06_build_datacube.R (add_trend_features / ols_slope_k verbatim).
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger); library(sf) })

SEED<-cfg$random_seed%||%42; NUM_TREES<-500L; TRAIN_FRAC<-0.80; CUT_YR<-2016L; CUT_DATE<-as.Date("2016-01-01"); MIN_BLK<-5L
HORIZONS<-cfg$forecast$horizons_days; LOGV<-c("chlor_a_mean","nflh_mean","Kd_490_mean"); LEVELS<-c("chlor_a_mean","nflh_mean","Kd_490_mean","sst_mean")
EMBARGO_ON<-isTRUE(cfg$split_repair$temporal_embargo); BUFFER_M<-as.numeric(cfg$split_repair$spatial_buffer_m%||%0)
W_FROZEN<-8L   # picked on TRAINING coverage/staleness (filled 81-97% @ median fill-age 2-3d); frozen before scoring
DELTA_LAGS<-cfg$trends$delta_lags_days; SLOPE_WINS<-cfg$trends$slope_windows_days; ROLL_WINS<-cfg$trends$rolling_windows_days; EPS<-cfg$trends$pct_change_epsilon
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

# ── R/06 trend machinery (verbatim) ────────────────────────────────────────
ols_slope_k<-function(y,k) switch(as.character(k),
  "3"=(y-shift(y,2L))/2.0,
  "5"=(-2.0*shift(y,4L)-shift(y,3L)+shift(y,1L)+2.0*y)/10.0,
  "7"=(-3.0*shift(y,6L)-2.0*shift(y,5L)-shift(y,4L)+shift(y,2L)+2.0*shift(y,1L)+3.0*y)/28.0,
  stop("bad k"))
add_trend_features<-function(dt,level_cols,delta_lags,slope_wins,roll_wins,eps){
  for(col in level_cols){ svar<-sub("_mean$","",col)
    for(k in delta_lags){ lag_col<-paste0(svar,"_lag_",k,"d__"); delt<-paste0(svar,"_delta_",k,"d")
      dl<-dt[,.(cell_id,join_date=date+k,lag_val=get(col))]; dt[dl,on=.(cell_id,date=join_date),(lag_col):=i.lag_val]
      dt[,(delt):=get(col)-get(lag_col)]; dt[,(lag_col):=NULL] }
    for(k in delta_lags){ delt<-paste0(svar,"_delta_",k,"d"); pct<-paste0(svar,"_pct_chg_",k,"d")
      xT<-dt[[col]]; xd<-dt[[delt]]; xl<-xT-xd; dt[[pct]]<-xd/(abs(xl)+eps)*100.0 }
    for(k in slope_wins){ sc<-paste0(svar,"_slope_obs",k); dt[,(sc):=ols_slope_k(get(col),k),by=cell_id] }
    sq<-paste0(svar,"_sq__"); dt[,(sq):=get(col)^2]
    for(k in roll_wins){ mu<-paste0(svar,"_rollmean_obs",k); sd<-paste0(svar,"_rollstd_obs",k)
      dt[,(mu):=frollmean(get(col),n=k,na.rm=TRUE,align="right"),by=cell_id]
      dt[,(sd):={m2<-frollmean(get(sq),n=k,na.rm=TRUE,align="right");m<-get(mu);sqrt(pmax(0.0,m2-m^2))},by=cell_id] }
    dt[,(sq):=NULL] }
  dt }

# ── modeling rows + raw satellite block ────────────────────────────────────
dt<-as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[,date_T:=as.Date(as.character(date_T))]; dt[,year:=as.integer(substr(date_T,1,4))]; dt[,cell_id:=as.character(cell_id)]
label_cells<-unique(dt$cell_id)
SAT_TREND<-grep("^(chlor_a|nflh|Kd_490|sst)_(delta|pct_chg|slope_obs|rollmean_obs|rollstd_obs)",names(dt),value=TRUE)
SAT64<-c(LEVELS,SAT_TREND); stopifnot(length(SAT64)==64)

# ── COMPOSITE: full-grid daily satellite for label cells, trailing-clear LOCF ──
message("[E-07] loading satellite (label cells, full daily series)...")
sat<-as.data.table(read_parquet(proj_path(cfg$paths$satellite_features), col_select=c("cell_id","date",LEVELS)))
sat[,cell_id:=as.character(cell_id)]; sat<-sat[cell_id %in% label_cells]; sat[,date:=as.Date(date)]; sat[,di:=as.integer(date)]
setkey(sat,cell_id,di)
for(v in LEVELS){
  sat[,vloc:=nafill(get(v),"locf"),by=cell_id]                       # LOCF value
  sat[,dcl:=fifelse(!is.na(get(v)),di,NA_integer_)]; sat[,dcl:=nafill(dcl,"locf"),by=cell_id]
  sat[,age:=di-dcl]
  sat[,(v):=fifelse(!is.na(age) & age<=(W_FROZEN-1L), vloc, NA_real_)]  # composite within window
  sat[,(paste0("days_since_clear_",v)):=fifelse(!is.na(age) & age<=(W_FROZEN-1L), age, W_FROZEN)]  # age feature (W=no clear in window)
}
sat[,c("vloc","dcl","age"):=NULL]
# recompute trends on the COMPOSITED levels (R/06 formulas)
sat<-add_trend_features(sat, LEVELS, DELTA_LAGS, SLOPE_WINS, ROLL_WINS, EPS)
AGE<-paste0("days_since_clear_",LEVELS)
CMP_SRC<-c(SAT64, AGE)
comp<-sat[, c("cell_id","date",CMP_SRC), with=FALSE]
setnames(comp, SAT64, paste0(SAT64,"_cmp"))   # composited sat cols suffixed; ages keep names
# ── R6 + R-SPLIT gate evidence (on the composite construction) ─────────────
# R6: every composited value's retrieval_date <= T  <=> days_since_clear >= 0 always
r6_ok<-all(sat[[AGE[1]]]>=0 & sat[[AGE[2]]]>=0 & sat[[AGE[3]]]>=0 & sat[[AGE[4]]]>=0, na.rm=TRUE)

# ── join composite onto modeling rows ──────────────────────────────────────
dt<-merge(dt, comp, by.x=c("cell_id","date_T"), by.y=c("cell_id","date"), all.x=TRUE)

# coverage report on modeling rows
cat("\n=== FOCAL SATELLITE COVERAGE before/after compositing (W=",W_FROZEN,"), modeling rows ===\n")
for(v in LEVELS){ raw_na<-mean(is.na(dt[[v]])); cmp_na<-mean(is.na(dt[[paste0(v,"_cmp")]])); ag<-dt[[paste0("days_since_clear_",v)]]
  real<-mean(ag==0,na.rm=TRUE); cmp<-mean(ag>0 & ag<W_FROZEN,na.rm=TRUE); still<-mean(ag>=W_FROZEN,na.rm=TRUE)
  cat(sprintf("  %-12s raw NA %.1f%% -> composited NA %.1f%% | %% real %.1f / composited %.1f / still-imputed %.1f\n",
      v, 100*raw_na, 100*cmp_na, 100*real, 100*cmp, 100*still)) }
cat("R6 gate (all composited retrieval_date <= T, i.e. age>=0):", r6_ok, "\n")

# ── two arms on the SAME dt: raw-control vs composited ─────────────────────
cxy<-unique(dt[,.(cell_id,centroid_lon,centroid_lat)]);pxy<-sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]));cxy[,`:=`(X=pxy[,1],Y=pxy[,2])];setkey(cxy,cell_id)
cells_within<-function(trc,tec,R){if(R<=0)return(character(0));tr<-cxy[.(unique(trc))];te<-cxy[.(unique(tec))];if(!nrow(te)||!nrow(tr))return(character(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}
fitpred<-function(h,ti,ei,feat,tc,so){na<-feat[vapply(feat,function(cn)anyNA(h[[cn]]),logical(1))];tr<-copy(h[ti,c(feat,tc),with=FALSE]);te<-copy(h[ei,c(feat,tc),with=FALSE]);im<-impute_with_flag(tr,te,na);tr<-im$train;te<-im$test
  np<-sum(tr[[tc]]==1L);nn<-sum(tr[[tc]]==0L);if(np==0)return(NULL);w<-ifelse(tr[[tc]]==1L,nn/np,1.0);set(tr,j=tc,value=factor(tr[[tc]],levels=c(0,1)));rf<-ranger(as.formula(paste(tc,"~ .")),data=tr,num.trees=NUM_TREES,probability=TRUE,case.weights=w,num.threads=1L,seed=so);predict(rf,data=te)$predictions[,"1"]}
out<-list();prc<-list();rsplit_bad<-0L
for(H in HORIZONS){
  tc<-paste0("HAB_H",H);h<-dt[!is.na(get(tc))];h[,block_cv:=merge_tiny(spatial_block_tiger)]
  excl<-c(ALWAYS_EXCLUDE,setdiff(paste0("HAB_H",HORIZONS),tc))
  adopted<-setdiff(names(h),c(excl,tc,"year","block_cv")); adopted<-setdiff(adopted,bio_cols(adopted))
  adopted<-setdiff(adopted, c(paste0(SAT64,"_cmp"), AGE))   # base adopted = RAW sat (control)
  feat_raw<-adopted
  feat_cmp<-c(setdiff(adopted, SAT64), paste0(SAT64,"_cmp"), AGE)  # swap raw sat -> composited + ages
  set.seed(SEED+H);pos<-which(h[[tc]]==1L);neg<-which(h[[tc]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))));rte<-setdiff(seq_len(nrow(h)),rtr)
  ttr<-which(h$year<CUT_YR);tte<-which(h$year>=CUT_YR);if(EMBARGO_ON){k<-(h$date_T[ttr]+H)<CUT_DATE;ttr<-ttr[k]}
  # R-SPLIT: no TRAINING row's composite retrieval date reaches into the test period
  #   retrieval_date = date_T - days_since_clear; must stay < CUT_DATE for temporal-train rows
  rd_max<-max(h$date_T[ttr] - pmin(h$days_since_clear_chlor_a_mean[ttr],W_FROZEN), na.rm=TRUE)  # oldest is fine; newest retrieval:
  rd_newest<-max(h$date_T[ttr], na.rm=TRUE)  # newest T in train; retrieval <= T so <= this < CUT
  if(rd_newest>=CUT_DATE) rsplit_bad<-rsplit_bad+1L
  bs<-sort(table(h$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(h);nh<-max(1L,min(which(cum>=0.15)));hb<-names(bs)[seq_len(nh)]
  ste<-which(h$block_cv%in%hb);str<-setdiff(seq_len(nrow(h)),ste);if(BUFFER_M>0){dc<-cells_within(h$cell_id[str],h$cell_id[ste],BUFFER_M);str<-str[!(h$cell_id[str]%in%dc)]}
  sl<-list(random=list(tr=rtr,te=rte),temporal=list(tr=ttr,te=tte),spatial=list(tr=str,te=ste))
  for(sp in names(sl)){ti<-sl[[sp]]$tr;ei<-sl[[sp]]$te;if(length(ti)<20||length(ei)<10)next
    so<-SEED+H*100L+which(names(sl)==sp)
    p_c<-fitpred(h,ti,ei,feat_cmp,tc,so); p_r<-fitpred(h,ti,ei,feat_raw,tc,so); act<-as.integer(h[[tc]][ei])
    bd<-data.table(horizon=H,split=sp,cell_id=h$cell_id[ei],date_T=h$date_T[ei],act=act)
    out[[length(out)+1]]<-copy(bd)[,`:=`(prob=p_c,model="rf_composite")]
    out[[length(out)+1]]<-copy(bd)[,`:=`(prob=p_r,model="rf_raw_control")]
    prc[[length(prc)+1]]<-data.table(horizon=H,split=sp,pr_composite=round(pr_auc_fn(p_c,act),4),pr_raw=round(pr_auc_fn(p_r,act),4))
    message("[E-07] H=",H," ",sp," (n_feat_cmp=",length(feat_cmp),", n_test=",length(ei),")")}
}
cat("R-SPLIT gate (0 temporal-train rows whose newest feature date >= test cutoff):", ifelse(rsplit_bad==0,"PASS","FAIL"),"\n")
res<-rbindlist(out);write_parquet(res,proj_path("outputs/tables/predictions_e07.parquet"))
cat("\n[E-07] predictions_e07.parquet written:",nrow(res),"rows\n")
cat("=== PR-AUC composite vs raw-control (point) ===\n");print(rbindlist(prc)[order(split,horizon)])
