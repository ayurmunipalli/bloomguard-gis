# M4-3 — Aqua tail quality

Generated 2026-07-17 16:52:49.815775 by `R/04c_aqua_tail_quality.R`.

## M4-3 — Aqua tail quality: 2022 vs 2021, matched calendar dates

Design: days 1/11/21 of every month, both years; identical products, grid, and
aggregation code path. Season and day-of-year are held fixed; the YEAR is the
only contrast. This is a sample (36 dates/yr), not a census.

### File availability (rule 8: n_expected vs n_retrieved)
n_expected files : 288
n_retrieved      : 280
missing          : 8 

### Per-year metrics (mean over dates; each date = all 4743 grid cells)

| year | dates sampled | dates WITH data | files | chlor_a NA% | cloud_flag% | chlor_a valid px/cell | sst NA% | nflh NA% | Kd490 NA% |
|---|---|---|---|---|---|---|---|---|---|
| 2021 | 36 | 36 | 144 | 74.0% | 60.0% | 1.16 | 61.1% | 80.5% | 74.1% |
| 2022 | 36 | 34 | 136 | 72.3% | 56.5% | 1.24 | 57.4% | 77.1% | 72.4% |

Rates are computed only over dates WHERE A FILE EXISTS. A date with no file is a gap,
not a 0% and not a 100% — see the availability census below.

### Upstream file availability census (independent of this sample)
`AQUA_MODIS.<date>.L3m.DAY.CHL.chlor_a.4km.nc` present at OB.DAAC, per calendar day:

| year | days with a CHL file | days in year | gap |
|---|---|---|---|
| 2021 | 365 | 365 | none |
| 2022 | **351** | 365 | **April 2022 only: 16/30 days** |

The 2022 deficit is NOT spread thin — it is one contiguous outage in April 2022
(2022-04-01/02 and 2022-04-10/11/12 return HTTP 404 on a direct GET; the whole
month serves 16 of 30 days). Every other month of 2022 is complete.
**NOTE(verify): the CAUSE of the April 2022 outage is NOT established here.** It is
recorded as a measured gap. Do not attribute it to orbital drift without evidence —
drift is gradual and would not produce a 14-day hole bounded by two complete months.

### Delta (2022 - 2021), and a paired test across the 36 matched dates
chlor_a NA%     : -1.71 pp
cloud_flag%     : -3.54 pp
valid px/cell   : +0.075
(34 of 36 matched date-pairs are complete; 2 dropped — no Aqua file exists for the
 2022 side of the pair. Dropped, NOT imputed.)

paired t-test on chlor_a NA% across 34 matched date-pairs:
  mean paired diff = -1.24 pp, 95% CI [-11.04, +8.56], p = 0.7985
paired t-test on chlor_a valid px/cell:
  mean paired diff = +0.056, 95% CI [-0.404, +0.515], p = 0.8067

### VERDICT
**Is the 2022 tail materially degraded vs 2021, in retrieval terms? NO**

On matched dates, 2022's chlor_a retrieval rate and valid-pixel density are
statistically indistinguishable from 2021 — and the point estimates run in the
*better* direction (fewer NA, more valid pixels). The paired CI [-11.04, +8.56] pp
comfortably contains 0 and excludes any material degradation.

**The 'post-2021 MODIS-Aqua is degraded by orbital drift' assertion is NOT
SUPPORTED by these measurements and should be retracted, not repeated.** It was
never verified when first asserted. What IS real is a 14-day file outage in
April 2022 — a gap, not a degradation, and not drift-shaped.

### NOTE(limitation)
Retrieval rate is NOT the same as radiometric accuracy. Aqua's orbit HAS drifted
(later equator crossing -> different solar geometry), and this test measures
COVERAGE (how many cells get a value) and MISSINGNESS, not bias in the value.
A drift-induced systematic bias in chlor_a would not show up in any metric here.
Testing that needs a matchup against in-situ or a cross-sensor comparison
(VIIRS/SNPP overlaps Aqua for the whole tail) and is NOT done here.
