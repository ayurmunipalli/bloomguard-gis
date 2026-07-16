# ============================================================
# FILE:       R/07f_pC_roc_bootstrap.R
# PURPOSE:    Gate 0. Extend the 07e block-bootstrap code path to emit ROC-AUC
#             level + paired-difference CIs (temporal split, H in {1,3,5,7,14}).
#             Answers: is 0.900 inside the 95% CI around RF H=7 ROC 0.8360?
# INPUTS:     outputs/tables/predictions_pC.parquet (rf_adopted, persistence, ...)
#             outputs/tables/predictions_transformer.parquet (for identical 'wide')
# OUTPUTS:    APPENDS rows to outputs/tables/bootstrap_cis_pC.csv (no existing row
#             touched — new lines only). Byte-safe append via temp file.
# TECHNIQUES: IDENTICAL machinery to 07e: seed=42, L=30d non-overlapping calendar
#             blocks, n=1000, paired resamples. rank-based (Mann-Whitney) ROC-AUC.
# NOTE(limitation): chl_only per-row predictions are NOT in any dump; regenerating
#             them = retraining (prohibited, Rule 6). chl_roc / d_rf_chl_roc are
#             emitted as BLANK rows (n_boot=0), the table's existing null convention.
# NOTE(limitation): persistence ROC from predictions_pC disagrees with
#             model_results.csv persistence roc_auc (H7: 0.7873 vs 0.8213) — a
#             tie-handling/definition gap. RF ROC matches model_results exactly.
# ============================================================
Sys.setenv(ARROW_NUM_THREADS=1)
suppressWarnings(suppressMessages({library(arrow); arrow::set_cpu_count(1L); library(data.table)}))
N_BOOT<-1000L; BLOCK_L<-30L; Q<-c(0.025,0.975)

roc_auc_fn <- function(prob, act){ if(length(unique(act))<2) return(NA_real_)
  r<-rank(prob); npos<-sum(act==1L); nneg<-sum(act==0L)
  (sum(r[act==1L]) - npos*(npos+1)/2)/(npos*nneg) }
ci <- function(v){ v<-v[is.finite(v)]; c(lo=unname(quantile(v,Q[1])),hi=unname(quantile(v,Q[2])),n=length(v)) }

# reconstruct 'wide' EXACTLY as 07e (guarantees identical block draws under seed=42)
pc <- as.data.table(read_parquet("outputs/tables/predictions_pC.parquet"))
tf <- as.data.table(read_parquet("outputs/tables/predictions_transformer.parquet")); tf[,model:="transformer"]
for(d in list(pc,tf)){ d[,date_T:=as.Date(date_T)]; d[,cell_id:=as.character(cell_id)] }
allp <- rbind(pc,tf,use.names=TRUE)
wide <- dcast(allp, horizon+split+cell_id+date_T+act ~ model, value.var="prob")
setnames(wide, c("rf_adopted","rf_bio","rf_nowind","persistence","transformer"),
         c("p_rf","p_bio","p_nw","p_pers","p_tf"), skip_absent=TRUE)

boot_roc <- function(w, L, nboot=N_BOOT, seed=42){
  set.seed(seed); d0<-min(w$date_T)
  w<-copy(w)[,blk:=as.integer(as.integer(date_T-d0)%/%L)]
  setkey(w,blk); blks<-unique(w$blk); nb<-length(blks)
  M<-matrix(NA_real_,nboot,3,dimnames=list(NULL,c("rf_roc","pers_roc","d_rf_pers_roc")))
  for(i in seq_len(nboot)){
    r<-w[.(sample(blks,nb,replace=TRUE)),allow.cartesian=TRUE]; a<-r$act
    rr<-roc_auc_fn(r$p_rf,a); pr<-roc_auc_fn(r$p_pers,a)
    M[i,"rf_roc"]<-rr; M[i,"pers_roc"]<-pr; M[i,"d_rf_pers_roc"]<-rr-pr
  }
  M
}

fmt <- function(x) formatC(round(x,4), format="fg", drop0trailing=TRUE)
rows <- character(0)
for(H in c(1L,3L,5L,7L,14L)){
  w<-wide[horizon==H & split=="temporal"]; a<-w$act
  M<-boot_roc(w,BLOCK_L)
  pts<-list(rf_roc=roc_auc_fn(w$p_rf,a), pers_roc=roc_auc_fn(w$p_pers,a),
            d_rf_pers_roc=roc_auc_fn(w$p_rf,a)-roc_auc_fn(w$p_pers,a))
  for(q in c("rf_roc","pers_roc","d_rf_pers_roc")){
    c95<-ci(M[,q]); pt<-pts[[q]]
    ex<-((c95["lo"]>0 & c95["hi"]>0)|(c95["lo"]<0 & c95["hi"]<0))
    rows<-c(rows, sprintf("%d,temporal,%s,%s,%s,%s,%s,30,%d",
        H,q,fmt(pt),fmt(c95["lo"]),fmt(c95["hi"]),ifelse(ex,"TRUE","FALSE"),c95["n"]))
  }
  # chl_only: MISSING per-row predictions -> blank rows (table null convention)
  rows<-c(rows, sprintf("%d,temporal,chl_roc,,,,,30,0",H),
                 sprintf("%d,temporal,d_rf_chl_roc,,,,,30,0",H))
}
cat("=== NEW ROWS (to append) ===\n"); cat(rows, sep="\n"); cat("\n")

# ---- Append canonical ROC rows to bootstrap_cis_pC.csv, idempotently ----
# Run AFTER 07e (which rewrites the base PR/p80/delta table). Re-runnable: drops any
# existing temporal ROC-quantity rows before re-adding, so it never double-appends.
csv    <- "outputs/tables/bootstrap_cis_pC.csv"
roc_q  <- c("rf_roc","pers_roc","d_rf_pers_roc","chl_roc","d_rf_chl_roc")
base   <- fread(csv)
base   <- base[!(quantity %in% roc_q & split == "temporal")]
hdr    <- "horizon,split,quantity,point,ci_lo,ci_hi,excludes_0,block_days,n_boot"
newdt  <- fread(text = paste(c(hdr, rows), collapse = "\n"))
fwrite(rbindlist(list(base, newdt), use.names = TRUE), csv)
cat("[07f] appended", length(rows), "ROC rows to", csv, "\n")

# ---- Block diagnostics: H=7 temporal test set ----
w7<-wide[horizon==7 & split=="temporal"]; d0<-min(w7$date_T)
w7[,blk:=as.integer(as.integer(date_T-d0)%/%BLOCK_L)]
bd<-w7[,.(npos=sum(act==1L), n=.N), by=blk][order(blk)]
cat("\n=== BLOCK DIAGNOSTICS (H=7 temporal, L=30d) ===\n")
cat("n_blocks total          :", nrow(bd), "\n")
cat("n_blocks with >=1 pos   :", sum(bd$npos>=1), "\n")
cat("n_blocks zero-positive  :", sum(bd$npos==0), "\n")
cat("positives per block: min=",min(bd$npos)," median=",median(bd$npos)," max=",max(bd$npos),"\n",sep="")
cat("date range:", as.character(min(w7$date_T)),"->",as.character(max(w7$date_T)),
    " total positives=",sum(w7$act==1L),"\n")
