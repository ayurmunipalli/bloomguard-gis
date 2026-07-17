# M4-2 — HABSOS overlap audit: NCEI live vs DwC-A v1.5

Generated 2026-07-17 16:32:03.777252 by `R/01c_habsos_overlap_audit.R`.

## A. OLD source — GBIF/OBIS IPT DwC-A v1.5 (published 2022-09-30)
DwC-A after event x occurrence join : 190,339 records
DwC-A max eventDate                 : 2022-01-11   <- the mirror does NOT stop at 2021-12-31
DwC-A records after 2021-12-31      : 12

## B. NEW source — NCEI live ArcGIS (pulled 2026-07-17)
NCEI all dates                      : 220,979 records
NCEI date range                     : 1953-08-19 .. 2026-07-09

## C. STAGE-BY-STAGE OVERLAP COMPARISON (1953-08-19 .. 2021-12-31)

| stage | frozen record | DwC-A replay | NCEI live | NCEI - DwC-A |
|---|---|---|---|---|
| records (source rows) | 190,341 | 190,327 | 194,382 | +4055 |
| in bbox 24-31N/87-81W | 169,871 | 169,871 | 173,232 | +3361 |
| on grid (st_within) | — | 169,871 | 173,232 | +3361 |
| cell-day rows | 94,810 | 94,810 | 95,430 | +620 |
| positive (HAB=1) | 7,523 | 7,523 | 7,475 | -48 |
| positive % | 7.93% | 7.93% | 7.83% | -0.10 pp |

**DwC-A replay reproduces the frozen record: YES**
**NCEI reproduces the frozen record: NO**

## D. CELL-DAY AGREEMENT on the actual join key (cell_id x sample_date)
cell-days in BOTH            : 88,871
cell-days ONLY in DwC-A      : 5,939   <- present in the frozen labels, GONE from NCEI
cell-days ONLY in NCEI       : 6,559   <- new/backfilled
of the shared cell-days, max_count DIFFERS on : 427 (0.48%)
of the shared cell-days, HAB LABEL FLIPS on   : 67 (0.075%)  [0->1: 45, 1->0: 22]

## E. PER-YEAR record delta (bbox-filtered, overlap window)
years with ANY delta : 21 of 69

| year | DwC-A | NCEI | diff |
|---|---|---|---|
| 1956 | 2,922 | 2,923 | +1 |
| 1964 | 892 | 921 | +29 |
| 1965 | 37 | 52 | +15 |
| 1980 | 821 | 843 | +22 |
| 1986 | 275 | 276 | +1 |
| 1991 | 1,102 | 1,119 | +17 |
| 2000 | 3,709 | 3,711 | +2 |
| 2006 | 6,353 | 6,372 | +19 |
| 2008 | 5,284 | 5,285 | +1 |
| 2009 | 5,682 | 5,683 | +1 |
| 2010 | 5,217 | 5,218 | +1 |
| 2012 | 6,292 | 6,294 | +2 |
| 2013 | 6,836 | 6,834 | -2 |
| 2014 | 6,848 | 6,850 | +2 |
| 2015 | 6,148 | 6,168 | +20 |
| 2016 | 7,684 | 7,698 | +14 |
| 2017 | 8,164 | 8,190 | +26 |
| 2018 | 9,568 | 9,628 | +60 |
| 2019 | 8,743 | 8,933 | +190 |
| 2020 | 5,128 | 6,767 | +1639 |
| 2021 | 3,783 | 5,084 | +1301 |

## F. Does a QA flag explain the extra NCEI records?
CELLCOUNT_QA = 1    : 173,232 records
NCEI-in-bbox minus DwC-A-in-bbox = +3361 ; records at any non-1 QA flag = 0

## G. SCHEMA — the Arm B in-situ candidates (M4-2)

| field | in DwC-A? | in NCEI? | % non-null (NCEI, in bbox, all dates) | % non-null 2016+ |
|---|---|---|---|---|
| WATER_TEMP | no | **yes** | 48.8% | 56.7% |
| SALINITY | no | **yes** | 49.5% | 52.3% |
| SAMPLE_DEPTH | yes (min/maxDepthInMeters) | **yes** | 99.6% | 99.7% |
| WIND_SPEED | no | **yes** | 0.0% | 0.0% |
| WIND_DIR | no | **yes** | 0.0% | 0.0% |

QA-clean (_QA==1) non-null rates, in bbox, all dates:
  WATER_TEMP QA==1 : 48.5%   SALINITY QA==1 : 49.5%

## H. THE POST-2021 TAIL — sampling density by year-month (all states, bbox)

| year |  Jan |  Feb |  Mar |  Apr |  May |  Jun |  Jul |  Aug |  Sep |  Oct |  Nov |  Dec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2020 | 655 | 492 | 415 | 255 | 457 | 640 | 598 | 756 | 593 | 627 | 488 | 791 |
| 2021 | 736 | 787 | 751 | 900 | 726 | 1,051 | 61 | 30 | 39 | 3 | . | . |
| 2022 | . | 1 | 8 | 21 | 18 | 91 | 24 | 24 | 10 | 20 | 4 | 29 |
| 2023 | 17 | 30 | 21 | 36 | 28 | 12 | 31 | 33 | 14 | 14 | 20 | 7 |
| 2024 | 168 | 783 | 777 | 731 | 747 | 761 | 973 | 808 | 723 | 813 | 844 | 720 |
| 2025 | 797 | 830 | 788 | 783 | 689 | 685 | 708 | 696 | 469 | 155 | 129 | 584 |
| 2026 | 631 | 717 | 846 | 745 | 746 | 699 | 138 | . | . | . | . | . |

## I. BLAST RADIUS — where the disagreement lands relative to the 2016 split

| era | shared cell-days | only in DwC-A (lost) | only in NCEI (new) | HAB flips |
|---|---|---|---|---|
| train (<2016) | 65,765 | 3,445 | 3,183 | 39 |
| test (2016+) | 23,106 | 2,494 | 3,376 | 28 |

frozen (DwC-A) cell-days in the 2016+ test era : 25,600 (2,179 positive)
of those, NO LONGER PRESENT in NCEI            : 2,494 (9.7% of the test era)
