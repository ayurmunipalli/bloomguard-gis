# Scoring reconciliation — A7 (modeling) vs A10 (validation)

**Dispatched:** modeling A7 + validation A10 (investigation/fix), R-SPLIT (observer)
**Date:** 2026-07-13
**Trigger:** `model_results.csv` (A7) and `reports/agent_logs/validation.md` (A10) reported
different confusion matrices for the *same* saved model (`outputs/models/best_model.rds`,
H=7 temporal RF). A7: recall=0.355 (TP=382, FP=254, FN=693, TN=7551). A10: recall=0.321
(TP=345, FP=232, FN=730, TN=7573). Confirmed to predate the ERA5 wind run (same
discrepancy pattern existed in the pre-wind backups).

**Constraint honored:** no retraining occurred. `outputs/models/best_model.rds` MD5 is
byte-identical before and after this fix (`42a974c0e233027a7b3e355873f48c4c`). Only A10's
scoring/reconstruction code changed; A10 was then re-run to regenerate its own outputs
against the untouched, already-fitted model.

---

## Root cause

`best_model.rds` stores far more than the fitted `ranger` object — it also stores
`feat_cols`, `na_cols`, `train_medians`, `test_idx`, and the exact `prob_rf`/`act` arrays
A7 used to compute its own metrics at training time. Recomputing the confusion matrix
directly from `best_model.rds$prob_rf`/`$act` at threshold 0.5 reproduces A7's numbers
exactly (TP=382, FP=254, FN=693, TN=7551) — proving **A7's self-reported metrics were
already correct** and internally consistent with the saved model.

A10 independently reconstructs its own test frame from `data/processed/model_dataset.parquet`
rather than reusing the model's stored artifacts. Its feature-exclusion list
(`R/10_validation.R`, then line 113) was:

```r
feat_cols <- setdiff(names(h_dt), c(excl_H, TARGET_COL, "year", "month", "doy"))
```

— excluding `"month"` and `"doy"` in addition to `"year"`. But `07_modeling.R`'s
equivalent list only excludes `"year"`:

```r
feat_cols <- setdiff(names(h_dt), c(excl_H, target_col, "year"))
```

`month` and `doy` **are real trained features** — confirmed directly:
`"month" %in% best$rf$forest$independent.variable.names` → `TRUE`;
`"doy" %in% best$rf$forest$independent.variable.names` → `TRUE`. Both are also present in
`best$feat_cols` (the 155-column list A7 actually trained on).

Because A10 dropped `month`/`doy` from its own reconstructed test frame, its "missing
model vars" fallback (added to defensively pad any column gap) silently zero-filled both
for **every test row**:

```
[A10] Adding 2 missing model vars (set to 0)
```

Feeding the model `month=0, doy=0` (values it never saw with that meaning during training —
real month is 1–12, real day-of-year is 1–365) shifted every prediction and corrupted A10's
entire confusion matrix, not just a few rows.

## Verification (bit-exact)

Reconstructing A10's test frame with the fix applied (excluding only `"year"`, matching
A7) and predicting with the unmodified `best$rf`:

```
missing vars with fix: 0
FIXED reconstruction: TP=382 FP=254 FN=693 TN=7551 recall=0.3553
prob_rf identical to best_model.rds-stored prob_rf: TRUE  (all.equal, bit-exact)
```

This confirms the fix, not a coincidence — the corrected reconstruction reproduces A7's
stored predictions exactly, row for row.

## Authoritative scoring procedure (declared)

**A7's feature-exclusion list is authoritative.** Any script that reconstructs the test
frame for scoring/diagnostics against a saved BloomGuard RF model must exclude only:
identifiers (`cell_id`, `date_T`), the label family (`HAB`, `HAB_H1/H3/H5/H7/H14`), the
CV grouping key (`spatial_block_tiger`), direct label-inputs (`max_count`, `n_samples`),
all diagnostic/meta flags, still-placeholder env columns (`precip_mm`, `salinity_pss`),
and `"year"` (a split key, not a feature). **`month` and `doy` are real features and must
NOT be excluded.** `doy_sin`/`doy_cos` were never excluded by either script and are
unaffected.

A more robust guard for future scripts: prefer reconstructing the feature frame from
`best$feat_cols`/`best$na_cols`/`best$train_medians` (already stored in `best_model.rds`)
rather than re-deriving an independent exclusion list from scratch — this class of bug
(two independently-maintained exclusion lists silently drifting apart) can only recur if
someone edits one list without the other. Flagging as a follow-up hardening idea, not
implemented here (would touch code beyond the reconciliation scope).

## Fix applied

`R/10_validation.R`, line 113: removed `"month"`, `"doy"` from the exclusion list (now
matches `R/07_modeling.R` exactly, `+9/-1` diff, comment-documented in place). A10 was
re-run — **no retraining**: `best_model.rds` MD5 unchanged before/after
(`42a974c0e233027a7b3e355873f48c4c` both times) — to regenerate `outputs/tables/error_analysis.csv`
and `reports/agent_logs/validation.md` against the untouched model.

## Result — A7 and A10 now agree

| Source | TP | FP | FN | TN | Recall | Precision |
|---|---|---|---|---|---|---|
| A7 (`model_results.csv`, H=7 temporal rf) | 382 | 254 | 693 | 7551 | 0.3553 | 0.6006 |
| A10 (`validation.md`, post-fix) | 382 | 254 | 693 | 7551 | 0.355 | 0.601 |

Exact match (A10's log rounds to 3 decimals; underlying values identical).

## R-SPLIT observation (scope check)

Dispatched to confirm this is not a split-construction issue. Verdict: **PASS — confirmed
feature-reconstruction bug only, split integrity untouched.**

- `temp_train_idx`/`temp_test_idx` are computed purely from `h_dt$year` vs.
  `TEMPORAL_CUTOFF_YEAR` and are constructed **before and independently of** `feat_cols` —
  row membership was never a function of the feature-exclusion list, so this bug could not
  have changed which rows landed in train vs. test.
- `git diff --stat -- R/10_validation.R`: 1 file changed, 9 insertions(+), 1 deletion(-) —
  entirely the `feat_cols` line + its explanatory comment. `TEMPORAL_CUTOFF_YEAR`,
  `spatial_block_tiger` handling, and seed/split logic are byte-identical to before.
- The split-integrity conclusions in `reports/agent_logs/R-SPLIT-review.md` (Sarasota
  County 12_115 prevalence confound on the spatial split; H=14 zero-embargo boundary
  bleed, ~49 rows) remain fully in force and are unaffected by this fix.

## Scope / what this does NOT cover

- Only H=7 temporal could be reconciled this way, because `best_model.rds` only persists
  **one** fitted model (H=7 temporal, per the "best model" convention) — the other 14
  horizon×split RF fits in `07_modeling.R`'s loop are transient and were never saved.
  There is no way to check whether the same A10 bug affected other horizon/split
  combinations' *validation-side* numbers, because A10 only ever evaluates `best$horizon`
  (hardcoded to whatever's in `best_model.rds`, currently H=7 temporal) — A10 has never
  produced independent numbers for H=1/3/5/14 or the random/spatial splits to compare
  against. A7's `model_results.csv` numbers for those combinations are unaffected (A7
  never had this bug — the discrepancy was entirely on A10's side), so no other numbers
  in `model_results.csv` needed changing.
- `error_analysis.csv`'s non-RF slices (persistence baseline, season/geography/cloud_flag
  breakdowns keyed off the corrected `pred_05`) were regenerated by the same A10 re-run and
  are now consistent with the corrected predictions throughout.
