# M4-5 — temporal cutoff sensitivity: 2016 vs 2019 (Arm A v1, descriptive)

Generated 2026-07-17 16:43:53.602341 by `R/06e_cutoff_sensitivity.R`.

## Arm A v1 — as built
rows: 278,218 | horizons: 1,3,5,7,14
date_T range: 2003-01-04 .. 2021-12-28
label_date range: 2003-01-06 .. 2021-12-31

## Locating the 2017-2019 mega-bloom (not assumed — measured)

| year-month | positives | rows | positive rate |
|---|---|---|---|
| 2005-09 | 127 | 271 | 46.9% |
| 2006-09 | 142 | 341 | 41.6% |
| 2006-10 | 145 | 384 | 37.8% |
| 2013-01 | 111 | 300 | 37.0% |
| 2016-01 | 95 | 317 | 30.0% |
| 2016-10 | 114 | 369 | 30.9% |
| 2016-11 | 106 | 374 | 28.3% |
| 2018-08 | 155 | 469 | 33.0% |
| 2018-09 | 139 | 450 | 30.9% |
| 2018-10 | 106 | 565 | 18.8% |
| 2018-11 | 155 | 463 | 33.5% |
| 2019-11 | 145 | 473 | 30.7% |

The mega-bloom is the 2017-11 .. 2019-01 stretch above; it straddles BOTH
candidate cutoffs' neighbourhoods, which is why the line placement matters.

## LINE 2016 — cutoff 2016-01-01

| H | train rows | train pos | test rows | test pos | test base rate | test blocks | pos-carrying blocks |
|---|---|---|---|---|---|---|---|
| 1 | 34,337 | 2,275 | 21,535 | 1,972 | 9.16% | 70 | **42** |
| 3 | 34,043 | 2,242 | 21,404 | 1,970 | 9.20% | 71 | **42** |
| 5 | 34,169 | 2,257 | 21,380 | 1,929 | 9.02% | 71 | **42** |
| 7 | 34,306 | 2,273 | 21,323 | 1,923 | 9.02% | 71 | **42** |
| 14 | 34,370 | 2,276 | 21,351 | 1,944 | 9.10% | 69 | **39** |

**Mega-bloom (2017-11 .. 2019-01) at the 2016 line, H=7:** 891 of its 891 positives fall in TEST (100%); the rest are in TRAIN.
Largest single 30-day test block: **169 positives** (2018-10-17 .. 2018-11-15) = **8.8% of all H=7 test positives** in one block.

## LINE 2019 — cutoff 2019-01-01

| H | train rows | train pos | test rows | test pos | test base rate | test blocks | pos-carrying blocks |
|---|---|---|---|---|---|---|---|
| 1 | 46,905 | 3,742 | 8,967 | 505 | 5.63% | 33 | **15** |
| 3 | 46,592 | 3,714 | 8,855 | 498 | 5.62% | 34 | **15** |
| 5 | 46,676 | 3,702 | 8,873 | 484 | 5.45% | 34 | **15** |
| 7 | 46,793 | 3,710 | 8,836 | 486 | 5.50% | 34 | **15** |
| 14 | 46,931 | 3,724 | 8,790 | 496 | 5.64% | 33 | **15** |

**Mega-bloom (2017-11 .. 2019-01) at the 2019 line, H=7:** 18 of its 891 positives fall in TEST (2%); the rest are in TRAIN.
Largest single 30-day test block: **144 positives** (2019-10-28 .. 2019-11-26) = **29.6% of all H=7 test positives** in one block.

## The lever, named (not buried)

At H=7 the 2019 line moves **1,437 test positives into train** (test pos 1,923 -> 486) and cuts
positive-carrying 30-day blocks from **42 to 15**. Since the D14b resolution floor is set by
the positive-carrying block count, the 2019 line is the **less** powered of the two:
fewer blocks = a WIDER CI, not a tighter one. Moving the mega-bloom into train buys
training signal at the cost of the only thing that sets resolution.

**Both lines are pre-declared. Neither is 'the answer'. Report both.**
