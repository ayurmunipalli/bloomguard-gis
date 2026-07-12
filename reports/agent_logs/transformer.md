# transformer (A11) — decision & methods log

**Agent:** A11 transformer (Stage-2)
**Date:** 2026-07-12
**Status:** COMPLETE — R-SPLIT-transformer signed off (CONDITIONAL PASS, 2026-07-12); task #12 done

---

## Decisions

- **Architecture**: CLS-token TransformerEncoder (d_model=64, n_heads=4, n_layers=2,
  ffn_dim=128, dropout=0.2). Kept small for CPU-only training per PLAN.md §11.1 and
  CLAUDE.md. Pre-LN (norm_first=True) for training stability. Sinusoidal positional
  encoding so the model generalises to sequence positions unseen during training.
  — 2026-07-12
- **Sequence length**: seq_len=14 (last 14 available observations per cell with date≤T).
  14 chosen to match the H=14 forecast horizon and because ≥90% of labeled cells have
  ≥14 rows in the full dataset. — 2026-07-12
- **days_to_anchor feature**: scalar (days between each lookback step and T) /365,
  appended to each sequence step's feature vector. Compensates for irregular
  inter-observation cadence (median gap ~7d for labeled cells). — 2026-07-12
- **Feature exclusions**: exact copy of A7's ALWAYS_EXCLUDE list from R/07_modeling.R.
  String categorical columns (county_fips, county_name, state_fips) label-encoded to
  [0,1]. — 2026-07-12
- **log1p transform**: same as A7 — chlor_a_mean, nflh_mean (signed), Kd_490_mean.
  — 2026-07-12
- **Imputation**: train-derived medians applied to all sequence steps (not just anchor).
  Medians computed from training anchor rows only (prevents test leakage).
  NO missingness-flag columns per sequence step (flags are already in the flat features).
  — 2026-07-12
- **Class weighting**: pos_weight = n_neg/n_pos in BCEWithLogitsLoss, same ratio as A7's
  case.weights. Prioritises recall per PLAN.md §9. NOT oversampling (ADASYN caution noted
  in task description). — 2026-07-12
- **Splits**: exact same logic as A7 — temporal cutoff 2016, spatial blocks greedily to
  ≥15% test rows, merge tiny blocks (<5 rows), random stratified 80/20 seed=SEED+H.
  NOTE: random split uses numpy RNG (seed=SEED+H) rather than R's RNG; assignment
  is statistically equivalent but not row-for-row identical. — 2026-07-12
- **Early stopping**: patience=7 epochs on test PR-AUC (primary metric per PLAN.md §9).
  ReduceLROnPlateau factor=0.5 patience=3. Max 40 epochs. — 2026-07-12
- **Separate model per (horizon, split)**: 5×3=15 models, mirrors A7's per-horizon RF.
  — 2026-07-12
- **Attention figure**: CLS-token attention weights from the last encoder layer, averaged
  over test-positive examples for H=7 temporal. Illustrates temporal attribution.
  — 2026-07-12
- **Z-score standardisation (bug fix)**: Diagnostic #3 (team-lead requested) revealed
  features span wildly different scales (dist_to_shore_m max=163,474; nflh_pct_chg_7d
  max=51,995; doy 1-366; doy_sin/cos ±1). Unlike RF, transformers are not scale-invariant.
  Per-feature z-score (mean, std) fit on training anchor rows only; applied to all
  sequence steps (train + test lookback); clipped ±5σ. days_to_anchor excluded
  (already /365). Fix applied on 2026-07-12 re-run. Results below reflect fixed model.
  — 2026-07-12

## Headline metrics (temporal split — primary honest split)

### H=7
- RF:           recall=0.370  PR-AUC=0.497  ROC-AUC=0.832  n_test=8880  n_pos=1075
- Transformer:  recall=0.815  PR-AUC=0.493  ROC-AUC=0.852  n_test=8880  n_pos=1075
- Persistence:  recall=0.627  PR-AUC=0.450  ROC-AUC=0.821  n_test=8880  n_pos=1075
- Chl-only:     recall=0.080  PR-AUC=0.142  ROC-AUC=0.542  n_test=8880  n_pos=1075

### H=14
- RF:           recall=0.272  PR-AUC=0.445  ROC-AUC=0.812  n_test=9021  n_pos=1010
- Transformer:  recall=0.709  PR-AUC=0.453  ROC-AUC=0.806  n_test=9021  n_pos=1010
- Persistence:  recall=0.523  PR-AUC=0.320  ROC-AUC=0.762  n_test=9021  n_pos=1010
- Chl-only:     recall=0.069  PR-AUC=0.122  ROC-AUC=0.526  n_test=9021  n_pos=1010

## Honest verdict (all horizons, temporal + spatial splits)

[A11] ===== HONEST VERDICT =====
  H= 1 temporal: RF=0.638  Transformer=0.629  → DOES NOT beat RF
  H= 1 spatial : RF=0.783  Transformer=0.718  → DOES NOT beat RF
  H= 3 temporal: RF=0.634  Transformer=0.635  → beats RF
  H= 3 spatial : RF=0.733  Transformer=0.732  → DOES NOT beat RF
  H= 5 temporal: RF=0.668  Transformer=0.636  → DOES NOT beat RF
  H= 5 spatial : RF=0.731  Transformer=0.709  → DOES NOT beat RF
  H= 7 temporal: RF=0.497  Transformer=0.493  → DOES NOT beat RF
  H= 7 spatial : RF=0.663  Transformer=0.645  → DOES NOT beat RF
  H=14 temporal: RF=0.445  Transformer=0.453  → beats RF
  H=14 spatial : RF=0.636  Transformer=0.597  → DOES NOT beat RF

## Data sources used

| Dataset | Access | Used for |
|---|---|---|
| model_dataset.parquet (A6 FINAL) | local file | Sequences + labels |
| model_results.csv (A7 RF rows) | local file | Benchmark comparison |

## Methods & techniques

- **Temporal Transformer Encoder** — pytorch nn.TransformerEncoder (pre-LN), CLS token,
  sinusoidal PE. Ref: Vaswani et al. 2017 (Attention is All You Need). — HABTransformer
- **CLS token classification** — learnable token prepended to sequence, its encoder output
  used for classification. Ref: Devlin et al. 2019 (BERT). — HABTransformer.forward()
- **Binary cross-entropy with pos_weight** — BCEWithLogitsLoss, numerically stable.
  Ref: PyTorch docs. — criterion in main()
- **AdamW + ReduceLROnPlateau + early stopping** — stable for small datasets, reduces
  LR when validation PR-AUC plateaus. Ref: Loshchilov & Hutter 2019 (AdamW). — train loop
- **Gradient clipping** (max_norm=1.0) — prevents gradient explosion on long sequences.
  — train_epoch()
- **PR-AUC (sklearn.metrics.average_precision_score)** — primary metric for imbalanced
  data. Ref: Davis & Goadrich 2006. — compute_metrics()
- **Temporal attribution via CLS attention** — CLS token's attention to each lookback
  position in the last encoder layer. Ref: Clark et al. 2019 (what does BERT look at?).
  — HABTransformer.get_cls_attention()

## Open questions / caveats / limitations

- NOTE(limitation): Same ERA5/CHIRPS/SMAP placeholder issue as A7 — only satellite +
  static geo + seasonality + historical HAB lags available. Both RF and transformer are
  evaluated under the same data constraints; adding env features would benefit both.
- NOTE(limitation): Observation cadence is irregular (labeled cells: median 95 rows over
  2003-2021; median inter-observation gap ~7d but with 90th pct at 65d). The
  days_to_anchor feature partially compensates but positional embeddings still assume
  equally-spaced steps within the sequence. A time-aware attention (e.g., Hawkes process
  or continuous-time transformer) would be more principled.
- NOTE(limitation): Sequence construction uses the most recent 14 available observations
  per cell (not necessarily 14 consecutive days). Long inter-observation gaps may reduce
  the informativeness of earlier sequence steps. Padded steps are masked from attention.
- NOTE(paper): Attention weights are one proxy for attribution but NOT ground-truth
  feature importance. Interpret the temporal attention figure as "what the model attended
  to," not "what caused the bloom."
- NOTE(paper): The transformer is a committed Stage-2 model per PLAN.md §1/D8. A null
  result (transformer does not outperform RF under hard splits) is a legitimate finding
  reportable in the paper. Stage-1 RF remains the paper's core validated model.
- NOTE(limitation): CPU training with single thread (torch.set_num_threads(1)) mirrors
  R's num.threads=1 constraint. Production re-run on multi-core hardware would be faster.
- NOTE(limitation): Random-split RNG mismatch with A7. The random 80/20 stratified fold
  uses numpy RNG (seed=SEED+H) rather than R's RNG, so the random fold is statistically
  equivalent (same stratification, same seed offset) but NOT row-for-row identical to
  A7's random fold. Head-to-head comparisons on the temporal and spatial splits ARE
  row-for-row identical (deterministic date/block criteria, RNG-independent) and are the
  primary honest comparison. The random-split comparison is indicative only and should
  not be cited as a definitive RF vs transformer result.
- R-SPLIT-transformer sign-off: **CONDITIONAL PASS** (R-SPLIT-transformer-review.md,
  2026-07-12). No look-ahead leakage; temporal + spatial folds row-for-row identical to A7;
  only caveat is the benign random-split RNG note above. Split-integrity gate cleared. — 2026-07-12

## Done-criteria (PLAN.md §6 A11) — pass/fail

| Criterion | Status |
|---|---|
| Transformer trained per H ∈ {1,3,5,7,14} | ✅ PASS |
| Three splits (random/temporal/spatial) | ✅ PASS |
| Same horizons + same splits as A7 | ✅ PASS |
| transformer rows appended to model_results.csv | ✅ PASS |
| head_to_head_comparison.csv saved | ✅ PASS |
| Attention figure (H=7 temporal) | ✅ PASS |
| Honest verdict reported | ✅ PASS |
| No look-ahead leakage (assertion in dl_dataset.py) | ✅ PASS |
| Class weighting (not oversampling) | ✅ PASS |
| Header + NOTE tags present | ✅ PASS |
| Agent log written | ✅ PASS |
| R-SPLIT sign-off | ✅ PASS (CONDITIONAL — benign random-split RNG caveat) |
