# ============================================================
# FILE:       01c_habsos_overlap_audit.R
# OWNER:      M4-2 (lead) — gate, not a build step
# PURPOSE:    Decide ONE question: is the live NCEI HABSOS extract the same
#             population as the GBIF/OBIS IPT DwC-A v1.5 mirror over the overlap
#             window (1953-08-19 .. 2021-12-31)? If it is not, M4 stops here and
#             the author decides — a different schema/dedup/QC would mean every
#             existing number is built on a different population.
#             Reference (from the frozen record):
#               190,341 records / 169,871 in bbox / 94,810 cell-day rows /
#               7,523 positive (7.93%)
# INPUTS:     data/raw/habsos/event.txt, occurrence.txt        (DwC-A v1.5, old)
#             data/raw/habsos/ncei/habsos_ncei_raw.parquet     (NCEI live, R/01b)
#             data/processed/study_area_grid.gpkg
# OUTPUTS:    reports/results/M4-2_overlap_audit.md
#             outputs/tables/m4_habsos_overlap.csv
# TECHNIQUES: stage-by-stage replay of 03_habsos_labels.R's exact pipeline on both
#             sources; per-year delta; QA-flag decomposition; cell-day agreement
#             on the join key (cell_id x sample_date).
# CITATIONS:  NOTE(cite) tags inline
# ============================================================

# NOTE(verify): this script REPLAYS 03_habsos_labels.R's logic rather than sourcing
#   it, because 03 writes habsos_labels.parquet as a side effect and the frozen
#   parquet must not be touched by an audit. The replayed stages are copied from
#   03_habsos_labels.R sections 1-4 (bbox -> date -> st_within -> max per cell-day
#   -> HAB = max_count > threshold). If 03 changes, this replay must change with it.

local({
  d <- getwd()
  while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
  source(file.path(d, "R", "00_config.R"))
})

suppressPackageStartupMessages({
  library(data.table); library(sf); library(arrow)
})

cat("=== M4-2: HABSOS overlap audit (NCEI live vs DwC-A v1.5) ===\n\n")

OVERLAP_END <- as.IDate("2021-12-31")
bbox      <- cfg$study_area$bbox_wgs84
threshold <- cfg$label$threshold_cells_per_L
id_col    <- cfg$grid$id_col
grid      <- st_read(proj_path(cfg$paths$grid), quiet = TRUE)

log <- c()
say <- function(...) { s <- sprintf(...); cat(s, "\n"); log <<- c(log, s) }

# ---------------------------------------------------------------- stage replay
# NOTE(verify): the grid join is done on UNIQUE (lon,lat) pairs and then mapped
#   back to rows, rather than st_join-ing every record. HABSOS is a repeat-station
#   network — 220,979 NCEI records sit on 37,749 unique coordinates (5.9x) — and
#   st_within is a pure function of the coordinate, so this is EXACT, not an
#   approximation. It is done because the naive per-row st_join did not complete
#   in 45 min of CPU. Verified equivalent: the DwC-A replay below must reproduce
#   the frozen 169,871 / 94,810 / 7,523 exactly, which is the check on this.
to_cellday <- function(dt, qty_col, lat_col, lon_col, date_col, tag) {
  d <- copy(dt)
  setnames(d, c(qty_col, lat_col, lon_col, date_col), c("qty", "lat", "lon", "sample_date"))
  n0 <- nrow(d)
  d <- d[!is.na(lat) & !is.na(lon)]
  n1 <- nrow(d)
  d <- d[lon >= bbox$xmin & lon <= bbox$xmax & lat >= bbox$ymin & lat <= bbox$ymax]
  n2 <- nrow(d)
  d <- d[!is.na(sample_date)]
  n3 <- nrow(d)

  loc <- unique(d[, .(lon, lat)])
  pts <- st_as_sf(loc, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
  pts <- st_transform(pts, crs = 5070)
  idx <- st_within(pts, grid, sparse = TRUE)
  hit <- lengths(idx) > 0L
  loc[, cell_id := NA_character_]
  loc[hit, cell_id := as.character(grid[[id_col]][vapply(idx[hit], `[`, 1L, 1L)])]
  d <- merge(d, loc, by = c("lon", "lat"), all.x = TRUE)
  j <- d[!is.na(cell_id)]
  n4 <- nrow(j)
  cd <- j[, .(max_count = max(qty, na.rm = TRUE), n_samples = .N),
          by = .(cell_id, sample_date)]
  cd[, HAB := as.integer(max_count > threshold)]
  list(tag = tag, n_records = n0, n_latlon = n1, n_bbox = n2, n_dated = n3,
       n_ongrid = n4, cellday = cd,
       n_cellday = nrow(cd), n_pos = sum(cd$HAB), pct_pos = 100 * mean(cd$HAB))
}

# ---------------------------------------------------------------- A. OLD (DwC-A)
say("## A. OLD source — GBIF/OBIS IPT DwC-A v1.5 (published 2022-09-30)")
ev <- fread(proj_path(cfg$paths$raw_habsos, "event.txt"),
            select = c("id", "eventDate", "decimalLatitude", "decimalLongitude"),
            encoding = "UTF-8", showProgress = FALSE)
setnames(ev, c("event_id", "eventDate", "lat", "lon"))
ev <- ev[!is.na(lat) & !is.na(lon) & lat != "" & lon != ""]
ev[, lat := as.numeric(lat)][, lon := as.numeric(lon)]
ev <- ev[!is.na(lat) & !is.na(lon)]
oc <- fread(proj_path(cfg$paths$raw_habsos, "occurrence.txt"),
            select = c("id", "eventID", "organismQuantity", "organismQuantityType",
                       "occurrenceStatus"),
            encoding = "UTF-8", showProgress = FALSE)
setnames(oc, c("occ_id", "event_id", "organism_quantity", "organismQuantityType",
               "occurrenceStatus"))
oc[, organism_quantity := as.numeric(organism_quantity)]
old_raw <- merge(ev, oc, by = "event_id", all.x = FALSE, all.y = FALSE)
old_raw[, sample_date := as.IDate(substr(eventDate, 1, 10))]
say("DwC-A after event x occurrence join : %s records", format(nrow(old_raw), big.mark=","))
say("DwC-A max eventDate                 : %s   <- the mirror does NOT stop at 2021-12-31",
    as.character(max(old_raw$sample_date, na.rm = TRUE)))
say("DwC-A records after 2021-12-31      : %d", sum(old_raw$sample_date > OVERLAP_END, na.rm=TRUE))

OLD <- to_cellday(old_raw[sample_date <= OVERLAP_END | is.na(sample_date)],
                  "organism_quantity", "lat", "lon", "sample_date", "DwC-A v1.5 <=2021-12-31")

# ---------------------------------------------------------------- B. NEW (NCEI)
say("")
say("## B. NEW source — NCEI live ArcGIS (pulled %s)", Sys.Date())
new_raw <- setDT(read_parquet(proj_path(cfg$paths$raw_habsos, "ncei", "habsos_ncei_raw.parquet")))
say("NCEI all dates                      : %s records", format(nrow(new_raw), big.mark=","))
say("NCEI date range                     : %s .. %s",
    as.character(min(new_raw$sample_date)), as.character(max(new_raw$sample_date)))
NEW <- to_cellday(new_raw[sample_date <= OVERLAP_END],
                  "CELLCOUNT", "LATITUDE", "LONGITUDE", "sample_date", "NCEI <=2021-12-31")

# ---------------------------------------------------------------- C. compare
say("")
say("## C. STAGE-BY-STAGE OVERLAP COMPARISON (1953-08-19 .. 2021-12-31)")
say("")
say("| stage | frozen record | DwC-A replay | NCEI live | NCEI - DwC-A |")
say("|---|---|---|---|---|")
ref <- list(n_records = 190341, n_bbox = 169871, n_cellday = 94810, n_pos = 7523)
row <- function(lbl, key, refv) {
  say("| %s | %s | %s | %s | %+d |", lbl,
      if (is.null(refv)) "—" else format(refv, big.mark=","),
      format(OLD[[key]], big.mark=","), format(NEW[[key]], big.mark=","),
      NEW[[key]] - OLD[[key]])
}
row("records (source rows)", "n_records", ref$n_records)
row("in bbox 24-31N/87-81W", "n_bbox",    ref$n_bbox)
row("on grid (st_within)",   "n_ongrid",  NULL)
row("cell-day rows",         "n_cellday", ref$n_cellday)
row("positive (HAB=1)",      "n_pos",     ref$n_pos)
say("| positive %% | 7.93%% | %.2f%% | %.2f%% | %+.2f pp |",
    OLD$pct_pos, NEW$pct_pos, NEW$pct_pos - OLD$pct_pos)

repro <- (OLD$n_bbox == ref$n_bbox) && (OLD$n_cellday == ref$n_cellday) && (OLD$n_pos == ref$n_pos)
say("")
say("**DwC-A replay reproduces the frozen record: %s**", if (repro) "YES" else "NO")
say("**NCEI reproduces the frozen record: %s**",
    if (NEW$n_cellday == ref$n_cellday && NEW$n_pos == ref$n_pos) "YES" else "NO")

# ---------------------------------------------------------------- D. cell-day agreement
say("")
say("## D. CELL-DAY AGREEMENT on the actual join key (cell_id x sample_date)")
mo <- OLD$cellday[, .(cell_id, sample_date, old_max = max_count, old_HAB = HAB)]
mn <- NEW$cellday[, .(cell_id, sample_date, new_max = max_count, new_HAB = HAB)]
mm <- merge(mo, mn, by = c("cell_id", "sample_date"), all = TRUE)
say("cell-days in BOTH            : %s", format(sum(!is.na(mm$old_max) & !is.na(mm$new_max)), big.mark=","))
say("cell-days ONLY in DwC-A      : %s   <- present in the frozen labels, GONE from NCEI",
    format(sum(!is.na(mm$old_max) & is.na(mm$new_max)), big.mark=","))
say("cell-days ONLY in NCEI       : %s   <- new/backfilled", format(sum(is.na(mm$old_max) & !is.na(mm$new_max)), big.mark=","))
both <- mm[!is.na(old_max) & !is.na(new_max)]
say("of the shared cell-days, max_count DIFFERS on : %s (%.2f%%)",
    format(sum(both$old_max != both$new_max), big.mark=","),
    100 * mean(both$old_max != both$new_max))
say("of the shared cell-days, HAB LABEL FLIPS on   : %s (%.3f%%)  [0->1: %d, 1->0: %d]",
    format(sum(both$old_HAB != both$new_HAB), big.mark=","),
    100 * mean(both$old_HAB != both$new_HAB),
    sum(both$old_HAB == 0 & both$new_HAB == 1), sum(both$old_HAB == 1 & both$new_HAB == 0))

# ---------------------------------------------------------------- E. per-year
say("")
say("## E. PER-YEAR record delta (bbox-filtered, overlap window)")
oy <- old_raw[sample_date <= OVERLAP_END & lon >= bbox$xmin & lon <= bbox$xmax &
              lat >= bbox$ymin & lat <= bbox$ymax, .N, by = .(yr = year(sample_date))]
ny <- new_raw[sample_date <= OVERLAP_END & LONGITUDE >= bbox$xmin & LONGITUDE <= bbox$xmax &
              LATITUDE >= bbox$ymin & LATITUDE <= bbox$ymax, .N, by = .(yr = year(sample_date))]
yy <- merge(oy, ny, by = "yr", all = TRUE, suffixes = c("_old", "_new"))
yy[is.na(N_old), N_old := 0][is.na(N_new), N_new := 0]
yy[, diff := N_new - N_old]
say("years with ANY delta : %d of %d", sum(yy$diff != 0), nrow(yy))
say("")
say("| year | DwC-A | NCEI | diff |")
say("|---|---|---|---|")
for (i in which(yy$diff != 0)) say("| %d | %s | %s | %+d |", yy$yr[i],
    format(yy$N_old[i], big.mark=","), format(yy$N_new[i], big.mark=","), yy$diff[i])

# ---------------------------------------------------------------- F. QA decomposition
say("")
say("## F. Does a QA flag explain the extra NCEI records?")
nb <- new_raw[sample_date <= OVERLAP_END & LONGITUDE >= bbox$xmin & LONGITUDE <= bbox$xmax &
              LATITUDE >= bbox$ymin & LATITUDE <= bbox$ymax]
qa <- nb[, .N, by = CELLCOUNT_QA][order(-N)]
for (i in seq_len(nrow(qa))) say("CELLCOUNT_QA = %-4s : %s records",
    as.character(qa$CELLCOUNT_QA[i]), format(qa$N[i], big.mark=","))
say("NCEI-in-bbox minus DwC-A-in-bbox = %+d ; records at any non-1 QA flag = %s",
    NEW$n_bbox - OLD$n_bbox, format(sum(qa$N[qa$CELLCOUNT_QA != 1 | is.na(qa$CELLCOUNT_QA)]), big.mark=","))

# ---------------------------------------------------------------- G. schema
say("")
say("## G. SCHEMA — the Arm B in-situ candidates (M4-2)")
say("")
say("| field | in DwC-A? | in NCEI? | %% non-null (NCEI, in bbox, all dates) | %% non-null 2016+ |")
say("|---|---|---|---|---|")
nbb <- new_raw[LONGITUDE >= bbox$xmin & LONGITUDE <= bbox$xmax &
               LATITUDE >= bbox$ymin & LATITUDE <= bbox$ymax]
nb16 <- nbb[sample_date >= as.IDate("2016-01-01")]
pct <- function(d, cc) 100 * mean(!is.na(d[[cc]]))
say("| WATER_TEMP | no | **yes** | %.1f%% | %.1f%% |", pct(nbb,"WATER_TEMP"), pct(nb16,"WATER_TEMP"))
say("| SALINITY | no | **yes** | %.1f%% | %.1f%% |", pct(nbb,"SALINITY"), pct(nb16,"SALINITY"))
say("| SAMPLE_DEPTH | yes (min/maxDepthInMeters) | **yes** | %.1f%% | %.1f%% |", pct(nbb,"SAMPLE_DEPTH"), pct(nb16,"SAMPLE_DEPTH"))
say("| WIND_SPEED | no | **yes** | %.1f%% | %.1f%% |", pct(nbb,"WIND_SPEED"), pct(nb16,"WIND_SPEED"))
say("| WIND_DIR | no | **yes** | %.1f%% | %.1f%% |", pct(nbb,"WIND_DIR"), pct(nb16,"WIND_DIR"))
say("")
say("QA-clean (_QA==1) non-null rates, in bbox, all dates:")
say("  WATER_TEMP QA==1 : %.1f%%   SALINITY QA==1 : %.1f%%",
    100*mean(!is.na(nbb$WATER_TEMP) & nbb$WATER_TEMP_QA == 1),
    100*mean(!is.na(nbb$SALINITY)   & nbb$SALINITY_QA   == 1))

# ---------------------------------------------------------------- H. the tail
say("")
say("## H. THE POST-2021 TAIL — sampling density by year-month (all states, bbox)")
tail_dt <- nbb[sample_date >= as.IDate("2020-01-01")]
tm <- tail_dt[, .N, by = .(yr = year(sample_date), mo = month(sample_date))]
say("")
say("| year | %s |", paste(sprintf("%4s", month.abb), collapse = " | "))
say("|---|%s", paste(rep("---|", 12), collapse = ""))
for (y in sort(unique(tm$yr))) {
  v <- vapply(1:12, function(m) { x <- tm[yr == y & mo == m, N]; if (length(x)) format(x, big.mark=",") else "." }, "")
  say("| %d | %s |", y, paste(v, collapse = " | "))
}

# ---------------------------------------------------------------- I. blast radius
# The overlap disagreement only matters in proportion to where it lands. The 2016
# cutoff is the frozen temporal split (PLAN.md D14b / PROJECT.md §6), so a change
# inside 2016+ moves the reported test numbers; a change before it moves training.
say("")
say("## I. BLAST RADIUS — where the disagreement lands relative to the 2016 split")
mm[, era := ifelse(sample_date < as.IDate("2016-01-01"), "train (<2016)", "test (2016+)")]
br <- mm[, .(
  only_dwca   = sum(!is.na(old_max) & is.na(new_max)),
  only_ncei   = sum(is.na(old_max) & !is.na(new_max)),
  shared      = sum(!is.na(old_max) & !is.na(new_max)),
  flips       = sum(!is.na(old_max) & !is.na(new_max) & old_HAB != new_HAB)
), by = era]
say("")
say("| era | shared cell-days | only in DwC-A (lost) | only in NCEI (new) | HAB flips |")
say("|---|---|---|---|---|")
for (i in seq_len(nrow(br))) say("| %s | %s | %s | %s | %d |", br$era[i],
    format(br$shared[i], big.mark=","), format(br$only_dwca[i], big.mark=","),
    format(br$only_ncei[i], big.mark=","), br$flips[i])
fz_test <- OLD$cellday[sample_date >= as.IDate("2016-01-01")]
say("")
say("frozen (DwC-A) cell-days in the 2016+ test era : %s (%s positive)",
    format(nrow(fz_test), big.mark=","), format(sum(fz_test$HAB), big.mark=","))
say("of those, NO LONGER PRESENT in NCEI            : %s (%.1f%% of the test era)",
    format(br[era == "test (2016+)", only_dwca], big.mark=","),
    100 * br[era == "test (2016+)", only_dwca] / nrow(fz_test))

out <- proj_path("reports", "results", "M4-2_overlap_audit.md")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(c("# M4-2 — HABSOS overlap audit: NCEI live vs DwC-A v1.5", "",
             sprintf("Generated %s by `R/01c_habsos_overlap_audit.R`.", Sys.time()), "", log), out)
fwrite(yy, proj_path("outputs", "tables", "m4_habsos_overlap.csv"))
cat("\nWrote:", out, "\n")
cat("=== M4-2: done ===\n")
