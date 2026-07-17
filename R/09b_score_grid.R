# ============================================================
# FILE:       R/09b_score_grid.R
# PURPOSE:    M3-2 — score the FULL grid at H=7 with the M2a Arm A ranger (arm_a_H7 from
#             arms_rf_temporal.rds). Every model to date scored only the 0.24% of cell-days
#             carrying a HABSOS sample; this scores every cell x every clear satellite date.
#             A cloudy cell-date gets NO prediction (not imputed). Reports coverage, land
#             cells (depth_m>0), and the fraction of grid never label-validated (B10).
# INPUTS:     satellite_features.parquet + satellite_features_bio_optical.parquet (27,641,118),
#             era5_checkpoints/*, static_geo.parquet, model_dataset_arm_a.parquet (for the
#             training fold's imputation medians), arms_rf_temporal.rds ($arm_a_H7)
# OUTPUTS:    outputs/gis/risk_surface_H7.parquet (cell_id,date,prob — gitignored)
#             outputs/gis/grid_coverage.csv (small, committed)
# NOTE(limitation): a cell with no HABSOS label in any year still gets a prediction (that is
#   the point of a portable surface) but carries NO validation — B10, non-detection != absence.
# ============================================================
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(ranger) })
CUTOFF<-as.Date("2016-01-01"); delta_lags<-c(1,3,5,7); slope_wins<-c(3,5,7); roll_wins<-c(3,7); eps<-1e-6; SNAP_WIN<-7L
LOG_FEATURES<-c("chlor_a_mean","nflh_mean","Kd_490_mean")

add_trend<-function(dt,cols){for(col in cols){v<-sub("_mean$","",col)
  for(k in unique(c(delta_lags,slope_wins))){lagc<-paste0(v,"__lag",k);dl<-dt[,.(cell_id,jd=date+k,lv=get(col))];dt[dl,on=.(cell_id,date=jd),(lagc):=i.lv];dt[,(paste0(v,"_delta_",k,"d")):=get(col)-get(lagc)];dt[,(lagc):=NULL]}
  for(k in delta_lags){d<-dt[[paste0(v,"_delta_",k,"d")]];set(dt,j=paste0(v,"_pct_chg_",k,"d"),value=d/(abs(dt[[col]]-d)+eps)*100)}
  for(k in slope_wins) set(dt,j=paste0(v,"_slope_",k,"d"),value=dt[[paste0(v,"_delta_",k,"d")]]/k)
  sq<-paste0(v,"__sq");dt[,(sq):=get(col)^2];for(k in roll_wins){mu<-paste0(v,"_rollmean_obs",k);dt[,(mu):=frollmean(get(col),k,na.rm=TRUE,align="right"),by=cell_id];dt[,(paste0(v,"_rollstd_obs",k)):={m2<-frollmean(get(sq),k,na.rm=TRUE,align="right");sqrt(pmax(0,m2-get(mu)^2))},by=cell_id]};dt[,(sq):=NULL]}
  dt}

# ── model + reconstruct M2a preprocessing (training-fold medians) ──
rf <- readRDS("outputs/models/arms_rf_temporal.rds")$arm_a_H7
model_feats <- rf$forest$independent.variable.names
A <- as.data.table(read_parquet("data/processed/model_dataset_arm_a.parquet")); A[,date_T:=as.Date(date_T)]
for(lc in c("rbd_detect","kbbi_kbrevis","cannizzaro_kbrevis")) if(lc%in%names(A)) A[,(lc):=as.integer(get(lc))]
for(f in LOG_FEATURES) if(f%in%names(A)){if(f=="nflh_mean")A[,(f):=sign(get(f))*log1p(abs(get(f)))] else A[,(f):=log1p(pmax(get(f),0))]}
EXCL<-c("cell_id","date_T","horizon","label","label_date","snap_date","kbbi_raw","county_fips","county_name","state_fips","spatial_block_tiger","precip_mm","salinity_pss","chl_missing","bio_cloud_flag","bio_feature_filled","bio_IS_PLACEHOLDER","kbbi_invalid","sat_feature_filled","cloud_flag","sat_IS_PLACEHOLDER","wind_is_placeholder","precip_is_placeholder","salinity_is_placeholder","static_IS_PLACEHOLDER")
feat_a<-setdiff(names(A),EXCL)
trH7<-A[horizon==7 & as.integer(format(date_T,"%Y"))<2016 & label_date<CUTOFF]  # M2a temporal TRAIN fold
med<-sapply(feat_a,function(c) {m<-median(trH7[[c]],na.rm=TRUE); if(is.na(m)) 0 else m})  # medians from TRAIN
na_cols<-feat_a[vapply(feat_a,function(c)anyNA(A[horizon==7][[c]]),logical(1))]  # flags: M2a used FULL horizon-7 data
cat("model feats:",length(model_feats)," base feat_a:",length(feat_a)," na_cols(flagged):",length(na_cols),"\n")

# ── static + wind + coverage denominators ──
static<-as.data.table(read_parquet("data/processed/static_geo.parquet")); setnames(static,"IS_PLACEHOLDER","static_IS_PLACEHOLDER")
land_cells<-static[depth_m>0,cell_id]; cat("land cells (depth_m>0):",length(land_cells),"\n")
hab<-as.data.table(read_parquet("data/processed/habsos_labels.parquet",col_select=c("cell_id"))); labeled_cells<-unique(hab$cell_id)
wind<-rbindlist(lapply(list.files("data/raw/weather/era5_checkpoints",pattern="\\.parquet$",full.names=TRUE),function(f)as.data.table(read_parquet(f))))
wind[,date:=as.Date(date)]; setkey(wind,cell_id,date)
wind_cols<-intersect(c("wind_u_ms","wind_v_ms","wind_speed_ms","wind_dir_deg","wind_along_ms","wind_cross_ms"),names(wind))

score_cells<-function(cids){
  s<-as.data.table(read_parquet("data/processed/satellite_features.parquet")); s<-s[cell_id%in%cids]; s[,date:=as.Date(date)]; setorder(s,cell_id,date)
  b<-as.data.table(read_parquet("data/processed/satellite_features_bio_optical.parquet")); b[,cell_id:=as.integer(cell_id)]; b<-b[cell_id%in%cids]; b[,date:=as.Date(date)]; setorder(b,cell_id,date)
  b[,kbbi_raw:=kbbi]; b[!is.na(kbbi)&abs(kbbi)>1,kbbi:=NA_real_]
  b[,c("Rrs_667_mean","Rrs_667_n_valid","Rrs_678_mean","Rrs_678_n_valid","bbp_443_mean","bbp_443_n_valid","bbp_s_mean","bbp_s_n_valid","chlor_a_mean"):=NULL]
  for(lc in c("rbd_detect","kbbi_kbrevis","cannizzaro_kbrevis")) if(lc%in%names(b)) b[,(lc):=as.integer(get(lc))]
  s<-add_trend(s,c("chlor_a_mean","sst_mean","nflh_mean","Kd_490_mean")); b<-add_trend(b,c("rbd","kbbi","bbp_ratio_morel","bbp_deficit"))
  m<-merge(s,b,by=c("cell_id","date"),all.x=TRUE)          # bio at same date
  m<-m[!is.na(chlor_a_mean)]                                # clear-chlor rows = scorable (T = obs date)
  if(!nrow(m)) return(NULL)
  m<-merge(m,wind[,c("cell_id","date",wind_cols),with=FALSE],by=c("cell_id","date"),all.x=TRUE)
  m[,month:=as.integer(format(date,"%m"))][,doy:=as.integer(format(date,"%j"))][,doy_sin:=sin(2*pi*doy/365.25)][,doy_cos:=cos(2*pi*doy/365.25)]
  m<-merge(m,static,by="cell_id",all.x=TRUE)
  for(f in LOG_FEATURES) if(f%in%names(m)){if(f=="nflh_mean")m[,(f):=sign(get(f))*log1p(abs(get(f)))] else m[,(f):=log1p(pmax(get(f),0))]}
  X<-m[,feat_a,with=FALSE]
  for(c in na_cols) X[,(paste0(c,"_is_missing")):=as.integer(is.na(get(c)))]
  for(c in feat_a){ i<-which(is.na(X[[c]])); if(length(i)) set(X,i,c,med[[c]]) }
  X<-X[,model_feats,with=FALSE]                            # exact column set/order
  data.table(cell_id=m$cell_id,date=m$date,prob=predict(rf,data=X,num.threads=4L)$predictions[,"1"])
}

allc<-sort(static$cell_id); batches<-split(allc,ceiling(seq_along(allc)/500))
res<-list()
for(i in seq_along(batches)){ r<-score_cells(batches[[i]]); if(!is.null(r)) res[[length(res)+1]]<-r; cat("batch",i,"/",length(batches),"scored rows so far:",sum(sapply(res,nrow)),"\n") }
surf<-rbindlist(res)
dir.create("outputs/gis",showWarnings=FALSE,recursive=TRUE)
write_parquet(surf,"outputs/gis/risk_surface_H7.parquet")

# ── coverage report ──
tot<-27641118L; ncells<-length(allc); ndates<-uniqueN(surf$date)
cov<-data.table(
  metric=c("grid_cells","land_cells_depth_gt0","cells_ever_labeled","cells_never_labeled",
           "frac_grid_never_labeled","cell_dates_available","cell_dates_scored_clear","frac_scored",
           "dates_covered","median_daily_cloud_free_cells","median_daily_cloud_rate"),
  value=c(ncells, length(land_cells), length(labeled_cells), ncells-length(labeled_cells),
          round((ncells-length(labeled_cells))/ncells,4), tot, nrow(surf), round(nrow(surf)/tot,4),
          ndates, round(median(surf[,.N,by=date]$N),1), round(1-median(surf[,.N,by=date]$N)/ncells,4)))
fwrite(cov,"outputs/gis/grid_coverage.csv"); print(cov)
cat("=== 09b DONE: risk_surface_H7.parquet rows=",nrow(surf)," ===\n")
