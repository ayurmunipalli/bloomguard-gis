# ============================================================
# FILE:       R/e06_stop1_distribution.R
# PURPOSE:    E-06 STOP #1 (before any training). Build the 5-class FWC ordinal
#             severity label at each horizon (from raw HABSOS max_count at T+H,
#             the same shift-join R/06 used for HAB_H), validate that the derived
#             binary (class>=3) reproduces HAB_H exactly, and report the class
#             distribution per split per horizon (n and %). Flags class 4 < 30 in
#             any TRAINING split. NO model trained. Read-only.
# INPUTS:     data/processed/model_dataset.parquet ; habsos_labels.parquet
#             config split_repair.* (repaired splits: embargo + 20km buffer)
# OUTPUTS:    outputs/tables/e06_class_distribution.csv ; prints STOP#1 report.
# FWC classes (reproduce HAB via strict > at 100k, matching R/03:143):
#   0:<=1,000  1:(1k,10k]  2:(10k,100k]  3:(100k,1e6]  4:>1e6   (binary = class>=3)
# ============================================================
local({ d <- getwd(); while (!file.exists(file.path(d,"config.yaml")) && dirname(d)!=d) d <- dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); arrow::set_cpu_count(1L); library(data.table); library(sf) })

SEED<-cfg$random_seed%||%42; TRAIN_FRAC<-0.80; CUT_YR<-2016L; CUT_DATE<-as.Date("2016-01-01"); MIN_BLK<-5L
HORIZONS<-cfg$forecast$horizons_days
EMBARGO_ON<-isTRUE(cfg$split_repair$temporal_embargo); BUFFER_M<-as.numeric(cfg$split_repair$spatial_buffer_m%||%0)
fwc_class <- function(x) as.integer((x>1000)+(x>10000)+(x>100000)+(x>1e6))  # 0..4; class>=3 == x>1e5 == HAB

dt <- as.data.table(read_parquet(proj_path("data/processed/model_dataset.parquet")))
dt[["date_T"]]<-as.Date(as.character(dt[["date_T"]])); dt[["year"]]<-as.integer(substr(dt$date_T,1,4))
lab <- as.data.table(read_parquet(proj_path(cfg$paths$habsos_labels)))
lab[, sample_date := as.Date(sample_date)]
SAT_ERA_START <- as.Date("2003-01-01")
ref <- lab[sample_date>=SAT_ERA_START, .(cell_id, sample_date, max_count)]

# ordinal severity class at horizon H: max_count at T+H via the R/06 shift-join
build_ord <- function(H){
  sh <- ref[, .(cell_id, date_T = sample_date - H, mc_H = max_count)]
  m <- merge(dt[, .(cell_id, date_T)], sh, by=c("cell_id","date_T"), all.x=TRUE)
  m[, sev := fwc_class(mc_H)]
  m  # cell_id,date_T,mc_H,sev  (sev NA where mc_H NA)
}

merge_tiny<-function(b,m=MIN_BLK){cn<-table(b);ti<-names(cn)[cn<m];if(!length(ti))return(b);b[b%in%ti]<-names(cn)[which.max(cn)];b}
cxy<-unique(dt[,.(cell_id,centroid_lon,centroid_lat)]);pxy<-sf::sf_project("EPSG:4326","EPSG:5070",as.matrix(cxy[,.(centroid_lon,centroid_lat)]))
cxy[,`:=`(X=pxy[,1],Y=pxy[,2])];setkey(cxy,cell_id)
cells_within<-function(trc,tec,R){if(R<=0)return(character(0));tr<-cxy[.(unique(trc))];te<-cxy[.(unique(tec))]
  if(!nrow(te)||!nrow(tr))return(character(0));d<-vapply(seq_len(nrow(tr)),function(i)sqrt(min((te$X-tr$X[i])^2+(te$Y-tr$Y[i])^2))<R,logical(1));tr$cell_id[d]}

val <- data.table(); dist <- data.table()
for (H in HORIZONS) {
  tc<-paste0("HAB_H",H); h<-dt[!is.na(get(tc))]; h[,block_cv:=merge_tiny(spatial_block_tiger)]
  ord<-build_ord(H); h<-merge(h, ord[,.(cell_id,date_T,sev)], by=c("cell_id","date_T"), all.x=TRUE)
  # VALIDATE: derived binary (sev>=3) reproduces HAB_H exactly on non-NA
  ok <- h[!is.na(get(tc)), all((sev>=3L)== (get(tc)==1L))]
  n_sev_na <- h[!is.na(get(tc)), sum(is.na(sev))]
  val<-rbind(val, data.table(H=H, binary_reproduced=ok, n_label=nrow(h), n_sev_na=n_sev_na))
  # repaired splits
  set.seed(SEED+H); pos<-which(h[[tc]]==1L);neg<-which(h[[tc]]==0L)
  rtr<-sort(c(sample(pos,floor(TRAIN_FRAC*length(pos))),sample(neg,floor(TRAIN_FRAC*length(neg)))));rte<-setdiff(seq_len(nrow(h)),rtr)
  ttr<-which(h$year<CUT_YR);tte<-which(h$year>=CUT_YR); if(EMBARGO_ON){k<-(h$date_T[ttr]+H)<CUT_DATE;ttr<-ttr[k]}
  bs<-sort(table(h$block_cv),decreasing=TRUE);cum<-cumsum(bs)/nrow(h);nh<-max(1L,min(which(cum>=0.15)));hb<-names(bs)[seq_len(nh)]
  ste<-which(h$block_cv%in%hb);str<-setdiff(seq_len(nrow(h)),ste)
  if(BUFFER_M>0){dc<-cells_within(h$cell_id[str],h$cell_id[ste],BUFFER_M);str<-str[!(h$cell_id[str]%in%dc)]}
  sp_list<-list(random=list(tr=rtr,te=rte),temporal=list(tr=ttr,te=tte),spatial=list(tr=str,te=ste))
  for(sp in names(sp_list)) for(part in c("train","test")){
    idx<-sp_list[[sp]][[if(part=="train")"tr" else "te"]]; s<-h$sev[idx]
    cnt<-sapply(0:4, function(k) sum(s==k, na.rm=TRUE)); ntot<-length(idx)
    dist<-rbind(dist, data.table(H=H, split=sp, part=part, n=ntot,
      n0=cnt[1],n1=cnt[2],n2=cnt[3],n3=cnt[4],n4=cnt[5],
      pct0=round(100*cnt[1]/ntot,2),pct1=round(100*cnt[2]/ntot,2),pct2=round(100*cnt[3]/ntot,2),
      pct3=round(100*cnt[4]/ntot,2),pct4=round(100*cnt[5]/ntot,2)))
  }
}
fwrite(dist, proj_path("outputs/tables/e06_class_distribution.csv"))
cat("=== VALIDATION: derived binary (class>=3) reproduces HAB_H ? ===\n"); print(val)
cat("\n=== CLASS DISTRIBUTION — TRAINING splits (the flag is on class 4 here) ===\n")
print(dist[part=="train", .(H,split,n,n0,n1,n2,n3,n4,pct0,pct1,pct2,pct3,pct4)][order(split,H)], nrow=Inf)
cat("\n=== CLASS DISTRIBUTION — TEST splits (context) ===\n")
print(dist[part=="test", .(H,split,n,n0,n1,n2,n3,n4)][order(split,H)], nrow=Inf)
cat("\n=== STOP#1 FLAG: class 4 (>1e6) < 30 in any TRAINING split? ===\n")
thin<-dist[part=="train" & n4<30]
if(nrow(thin)) { cat("FLAG: class-4 thin in", nrow(thin), "training split(s):\n"); print(thin[,.(H,split,n4,n3,n3_plus_4=n3+n4)]) } else cat("No training split has class-4 < 30.\n")
cat("\nAlso reporting class 3 counts (medium; the old binary positive is 3+4):\n")
print(dist[part=="train",.(H,split,n3,n4,n34=n3+n4)][order(split,H)], nrow=Inf)
