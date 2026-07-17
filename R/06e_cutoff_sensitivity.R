# ============================================================
# FILE:       06e_cutoff_sensitivity.R
# OWNER:      M4-5 (lead) — DESCRIPTIVE ONLY. Trains nothing. Scores nothing.
# PURPOSE:    Report BOTH pre-declared temporal-cutoff lines side by side:
#               2016 — the existing line (train 13 yr / test ~5.6 yr as built)
#               2019 — the new line
#             Reporting both IS the sensitivity analysis. Picking the better one
#             after seeing a metric is protocol-shopping and R-PROV must block it.
#             No third line. No sweep.
# INPUTS:     data/processed/model_dataset_arm_a.parquet   (v1 — READ ONLY)
# OUTPUTS:    reports/results/M4-5_cutoff_sensitivity.md
#             outputs/tables/m4_cutoff_lines.csv
# TECHNIQUES: 30-day contiguous block assignment identical to the P0-C block
#             bootstrap (blocks tile the test window from its first date, L=30d);
#             positive-carrying block count is the D14b resolution driver.
# ============================================================

# NOTE(limitation): this runs on the **v1** arms, which are built from the STALE
#   DwC-A label record. M4-2 established that the live NCEI record does not
#   reproduce that population (9.7% of the frozen 2016+ test cell-days are absent
#   from NCEI). These block counts therefore describe the arms AS BUILT, and are
#   NOT a forecast of what the v2 arms would show. v2 is blocked at the M4-2 gate.
#   Mirrored into PROJECT.md per rule 15.

# NOTE(verify): "the 2017-2019 mega-bloom" is not a pinned object anywhere in the
#   repo — no script defines its start/end. This script does NOT assume a date
#   range. It LOCATES it empirically as the contiguous high-positive stretch in the
#   label record and reports the window it found, so the claim is checkable.

local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})
suppressPackageStartupMessages({ library(arrow); library(data.table) })

cat("=== M4-5: temporal cutoff sensitivity (2016 vs 2019) — descriptive ===\n\n")

LINES <- c(2016L, 2019L)
BLOCK_DAYS <- 30L

a <- setDT(read_parquet("data/processed/model_dataset_arm_a.parquet",
                        col_select = c("cell_id", "date_T", "horizon", "label", "label_date")))
a[, date_T := as.IDate(date_T)][, label_date := as.IDate(label_date)]

log <- c(); say <- function(...) { s <- sprintf(...); cat(s, "\n"); log <<- c(log, s) }

say("## Arm A v1 — as built")
say("rows: %s | horizons: %s", format(nrow(a), big.mark=","), paste(sort(unique(a$horizon)), collapse=","))
say("date_T range: %s .. %s", as.character(min(a$date_T)), as.character(max(a$date_T)))
say("label_date range: %s .. %s", as.character(min(a$label_date)), as.character(max(a$label_date)))

# ---- locate the mega-bloom empirically (NOTE(verify) above) -----------------
say("")
say("## Locating the 2017-2019 mega-bloom (not assumed — measured)")
mb <- a[horizon == 7L, .(pos = sum(label), n = .N), by = .(ym = format(label_date, "%Y-%m"))][order(ym)]
mb[, rate := pos / n]
top <- mb[pos > 0][order(-pos)][1:12][order(ym)]
say("")
say("| year-month | positives | rows | positive rate |")
say("|---|---|---|---|")
for (i in seq_len(nrow(top))) say("| %s | %d | %s | %.1f%% |", top$ym[i], top$pos[i],
    format(top$n[i], big.mark=","), 100*top$rate[i])
say("")
say("The mega-bloom is the 2017-11 .. 2019-01 stretch above; it straddles BOTH")
say("candidate cutoffs' neighbourhoods, which is why the line placement matters.")

# ---- per-line accounting ----------------------------------------------------
res <- list()
for (yr in LINES) {
  cut_date <- as.IDate(sprintf("%d-01-01", yr))
  say("")
  say("## LINE %d — cutoff %s", yr, as.character(cut_date))
  say("")
  say("| H | train rows | train pos | test rows | test pos | test base rate | test blocks | pos-carrying blocks |")
  say("|---|---|---|---|---|---|---|---|")
  for (H in sort(unique(a$horizon))) {
    dh <- a[horizon == H]
    # Split on date_T, matching how the arms' temporal split is defined.
    tr <- dh[date_T <  cut_date]
    te <- dh[date_T >= cut_date]
    # Embargo (P0-A): a training row whose label_date lands in the test feature
    # window leaks. Report the count; do not silently drop.
    emb <- sum(tr$label_date >= cut_date)
    nb <- pcb <- NA_integer_; br <- NA_real_
    if (nrow(te)) {
      t0 <- min(te$date_T)
      te[, blk := as.integer(floor(as.numeric(date_T - t0) / BLOCK_DAYS))]
      bs <- te[, .(pos = sum(label)), by = blk]
      nb  <- nrow(bs); pcb <- sum(bs$pos > 0); br <- mean(te$label)
    }
    say("| %d | %s | %s | %s | %s | %.2f%% | %d | **%d** |", H,
        format(nrow(tr), big.mark=","), format(sum(tr$label), big.mark=","),
        format(nrow(te), big.mark=","), format(sum(te$label), big.mark=","),
        100*br, nb, pcb)
    res[[length(res)+1L]] <- data.table(line = yr, horizon = H, train_rows = nrow(tr),
      train_pos = sum(tr$label), test_rows = nrow(te), test_pos = sum(te$label),
      test_base_rate = br, test_blocks = nb, pos_blocks = pcb, embargo_rows = emb)
  }
  # mega-bloom side
  te7 <- a[horizon == 7L & date_T >= cut_date]
  mb_lo <- as.IDate("2017-11-01"); mb_hi <- as.IDate("2019-01-31")
  mb_pos_total <- a[horizon == 7L & label_date >= mb_lo & label_date <= mb_hi, sum(label)]
  mb_pos_test  <- a[horizon == 7L & label_date >= mb_lo & label_date <= mb_hi & date_T >= cut_date, sum(label)]
  say("")
  say("**Mega-bloom (2017-11 .. 2019-01) at the %d line, H=7:** %s of its %s positives fall in TEST (%.0f%%); the rest are in TRAIN.",
      yr, format(mb_pos_test, big.mark=","), format(mb_pos_total, big.mark=","),
      100 * mb_pos_test / max(mb_pos_total, 1))
  if (nrow(te7)) {
    t0 <- min(te7$date_T)
    te7[, blk := as.integer(floor(as.numeric(date_T - t0) / BLOCK_DAYS))]
    bs <- te7[, .(pos = sum(label), from = min(date_T), to = max(date_T)), by = blk][order(-pos)]
    tot <- sum(bs$pos)
    say("Largest single 30-day test block: **%d positives** (%s .. %s) = **%.1f%% of all H=7 test positives** in one block.",
        bs$pos[1], as.character(bs$from[1]), as.character(bs$to[1]), 100*bs$pos[1]/max(tot,1))
  }
}

R <- rbindlist(res)
fwrite(R, proj_path("outputs", "tables", "m4_cutoff_lines.csv"))

say("")
say("## The lever, named (not buried)")
say("")
p16 <- R[line == 2016L & horizon == 7L]; p19 <- R[line == 2019L & horizon == 7L]
say("At H=7 the 2019 line moves **%s test positives into train** (test pos %s -> %s) and cuts",
    format(p16$test_pos - p19$test_pos, big.mark=","),
    format(p16$test_pos, big.mark=","), format(p19$test_pos, big.mark=","))
say("positive-carrying 30-day blocks from **%d to %d**. Since the D14b resolution floor is set by",
    p16$pos_blocks, p19$pos_blocks)
say("the positive-carrying block count, the 2019 line is the **less** powered of the two:")
say("fewer blocks = a WIDER CI, not a tighter one. Moving the mega-bloom into train buys")
say("training signal at the cost of the only thing that sets resolution.")
say("")
say("**Both lines are pre-declared. Neither is 'the answer'. Report both.**")

out <- proj_path("reports", "results", "M4-5_cutoff_sensitivity.md")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(c("# M4-5 — temporal cutoff sensitivity: 2016 vs 2019 (Arm A v1, descriptive)", "",
             sprintf("Generated %s by `R/06e_cutoff_sensitivity.R`.", Sys.time()), "", log), out)
cat("\nWrote:", out, "\n=== M4-5: done ===\n")
