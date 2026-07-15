# P0-J — Sampling-regime test for the HAB-history features

**Task:** PROJECT.md §2.5 / §3 P0-J. Read-only diagnostic. No model, feature, or split change.
**Script:** `R/diagnostics/P0-J_sampling_regime.R` (reproducible; arrow single-thread read).
**Data:** `data/processed/model_dataset.parquet` (194 cols). Feature date = `date_T`.
**Method:** For each horizon H ∈ {1,3,5,7,14}, restrict to that horizon's modeling set
(rows where `HAB_H{H}` is non-missing), split by the temporal cutoff (**train: year < 2016;
test: year ≥ 2016**), and report `% non-missing`, `% == 1`, and `n` for `hab_any_prior_7d`
and `hab_any_prior_14d`.

## Hypothesis under test
These features are **sparse/uninformative in the training era** (sparse pre-2016 HABSOS
sampling) and **dense/informative in the test era** (post-2015 intensive sampling) — so the
RF is trained where the feature rarely fires and evaluated where it is the strongest signal
available.

## Results

### `hab_any_prior_7d`
| H | n train | n test | % non-miss train | % non-miss test | % ==1 train | % ==1 test | test/train ratio (==1) |
|---|---|---|---|---|---|---|---|
| 1 | 4,787 | 3,004 | 100 | 100 | 10.97 | 19.17 | 1.75× |
| 3 | 2,813 | 1,952 | 100 | 100 | 12.73 | 22.18 | 1.74× |
| 5 | 3,474 | 2,677 | 100 | 100 | 12.84 | 18.04 | 1.40× |
| 7 | 14,871 | 8,880 | 100 | 100 | 7.30 | 14.49 | 1.98× |
| 14 | 14,868 | 9,021 | 100 | 100 | 7.23 | 13.66 | 1.89× |

### `hab_any_prior_14d`
| H | n train | n test | % non-miss train | % non-miss test | % ==1 train | % ==1 test | test/train ratio (==1) |
|---|---|---|---|---|---|---|---|
| 1 | 4,787 | 3,004 | 100 | 100 | 14.02 | 24.93 | 1.78× |
| 3 | 2,813 | 1,952 | 100 | 100 | 16.81 | 27.92 | 1.66× |
| 5 | 3,474 | 2,677 | 100 | 100 | 16.87 | 24.36 | 1.44× |
| 7 | 14,871 | 8,880 | 100 | 100 | 10.29 | 18.95 | 1.84× |
| 14 | 14,868 | 9,021 | 100 | 100 | 9.94 | 18.35 | 1.85× |

## Verdict: **REJECTED**  *(revised — see the conditional follow-up below)*

> **This line was originally recorded as CONFIRMED on the strength of the marginal (`==1`) rate.
> That was wrong.** The marginal rate cannot test §2.5's claim, because the feature-`==1` rate and
> the label positive rate rise together (H=7 train: feature 7.30% / label 7.16%; test: 14.49% /
> 12.11% — both roughly double), which is equally consistent with "more sampling detects more of
> everything" (no fix needed). §2.5 is a claim about **conditional informativeness**, and the
> conditional test (next section) **rejects it.** The marginal description below is retained as
> Part A because the density shift is a real, disclosed property of the split — but it is not
> evidence for the hypothesis.

### Part A — marginal firing rate (descriptive only; does NOT test the hypothesis)
At every horizon and for both features the positive (`== 1`) rate is ~1.4–2.0× higher in the test
era than in training. Non-missing rate is 100% in both eras — the features are **zero-imputed
indicators** (0 = no prior HAB observation in the window), so the density shift lives in the value
distribution, not in missingness. But because label prevalence rises in lockstep (§6: test prev
~1.6× train), this marginal shift is what intensive post-2015 HABSOS sampling produces mechanically
and says nothing about whether the feature became more *predictive*.

## Implication for how the temporal split must be described in the paper
The 2016 temporal split is **partly a sampling-regime shift** — the HAB-history features and the
label are ~1.5–2× denser in the held-out era. But that shift does **not** make the feature more
informative in test; at the primary horizons it makes it **less** (Part B). So the temporal number
reflects a prevalence/sampling-density change to be **disclosed as a limitation**, not a
train-where-weak/grade-where-strong feature-transfer failure that a supervision fix would repair.

---

## Follow-up (Part B) — the conditional test that actually decides P0-J

**Why Part A was insufficient.** §2.5 claims the features are *less informative* in training — a
**conditional** (P(label | feature)), not a **frequency**. The `==1` rate and the label rate move
together, so a marginal doubling is fully explained by sampling intensity. The correct instrument
is the odds ratio linking feature to label, compared across eras.

**Method.** For each H, temporal split, per feature: 2×2 table of `feature{0,1}` × `HAB_H{H}{0,1}`.
Report `P(label=1|feature=1)`, `P(label=1|feature=0)`, their ratio (**lift**), the **odds ratio**
with a Wald 95% CI, and the **era interaction** `OR_test / OR_train` with a 95% CI (combined SE) and
a Wald p. **If OR_test/OR_train's CI excludes 1, the feature's informativeness differs by era.**
Computed in `R/diagnostics/P0-J_sampling_regime.R` (Part B).

### `hab_any_prior_7d`
| H | P(y\|f=1) tr→te | P(y\|f=0) tr→te | lift tr | lift te | OR train [95% CI] | OR test [95% CI] | OR_te/OR_tr [95% CI] | interaction p |
|---|---|---|---|---|---|---|---|---|
| 1 | 57.71→61.11 | 4.25→4.98 | 13.59 | 12.26 | 30.77 [24.49, 38.67] | 29.96 [23.38, 38.39] | 0.97 [0.70, 1.36] | 0.88 |
| 3 | 56.15→62.82 | 5.01→5.92 | 11.21 | 10.60 | 24.27 [18.41, 32.00] | 26.82 [20.10, 35.80] | 1.11 [0.74, 1.65] | 0.62 |
| 5 | 52.91→62.73 | 4.59→5.97 | 11.53 | 10.51 | 23.36 [18.15, 30.05] | 26.51 [20.54, 34.22] | 1.13 [0.79, 1.62] | 0.49 |
| 7 | 48.11→50.35 | 2.96→5.62 | 16.26 | 8.95 | 30.40 [26.05, 35.48] | 17.02 [14.70, 19.70] | **0.56 [0.45, 0.69]** | **9.3e-08** |
| 14 | 41.30→44.32 | 3.10→5.96 | 13.34 | 7.44 | 22.03 [18.86, 25.72] | 12.56 [10.85, 14.55] | **0.57 [0.46, 0.71]** | **2.5e-07** |

### `hab_any_prior_14d`
| H | P(y\|f=1) tr→te | P(y\|f=0) tr→te | lift tr | lift te | OR train [95% CI] | OR test [95% CI] | OR_te/OR_tr [95% CI] | interaction p |
|---|---|---|---|---|---|---|---|---|
| 1 | 50.82→52.34 | 3.47→3.59 | 14.63 | 14.57 | 28.71 [22.92, 35.96] | 29.47 [22.63, 38.38] | 1.03 [0.73, 1.45] | 0.88 |
| 3 | 48.41→53.94 | 4.06→4.83 | 11.93 | 11.16 | 22.18 [16.88, 29.15] | 23.06 [17.15, 31.02] | 1.04 [0.70, 1.56] | 0.85 |
| 5 | 45.39→54.14 | 3.77→4.00 | 12.03 | 13.54 | 21.19 [16.49, 27.24] | 28.33 [21.62, 37.13] | 1.34 [0.92, 1.93] | 0.12 |
| 7 | 40.59→43.55 | 2.32→4.75 | 17.52 | 9.17 | 28.81 [24.75, 33.55] | 15.47 [13.38, 17.88] | **0.54 [0.43, 0.66]** | **6.7e-09** |
| 14 | 35.99→38.43 | 2.53→5.08 | 14.22 | 7.57 | 21.65 [18.61, 25.19] | 11.67 [10.11, 13.47] | **0.54 [0.44, 0.66]** | **6.4e-09** |

### Decision (rule stated up front, applied mechanically)
- **lift SIMILAR train vs test → REJECTED** (feature transfers fine; density shift is sampling
  intensity; no supervision fix; prevalence shift stays a disclosed limitation).
- **lift MATERIALLY HIGHER in test, CIs non-overlapping → CONFIRMED** (trained-where-weak,
  graded-where-strong).

**What the data show:**
- **H=1, 3, 5** — OR ratio 0.97–1.34, every CI spans 1, interaction p = 0.12–0.88. Lift is
  statistically indistinguishable across eras. **Similar → REJECTED.**
- **H=7, 14 (the primary horizons)** — OR ratio ≈ **0.54–0.57**, CIs **exclude 1** (upper bound
  ≤ 0.71), interaction p between 6e-9 and 3e-7. The feature is significantly **less** informative
  in test, driven by the feature-negative background rate roughly doubling (H=7 7d: P(y|f=0)
  2.96%→5.62%) while P(y|f=1) barely moves. This is the **opposite** of the hypothesised direction.

**Nowhere is lift materially higher in test.** Under the stated rule the hypothesis is **REJECTED** —
and at H=7/14 it is rejected in the strong sense (the conditional moves significantly the wrong way).

### Consequence
- **No supervision fix is warranted on P0-J's basis.** The §7.3 pivot trigger
  (*"P0-J confirms the sampling-regime hypothesis → escalate the supervision fix ahead of E-04"*)
  **does not fire.**
- The train/test prevalence/density shift remains a **disclosed limitation** of the temporal split,
  not a feature-transfer defect.
- Limitations note (measurement property, not a feature failure): the H=7/14 odds-ratio decline in
  the test era is most likely a **ceiling effect**, not a change in bloom dynamics. Detection
  intensity roughly doubled post-2015, so the feature-negative background rate doubled with it
  (P(label|feature=0): 2.96%→5.62% at H=7), while P(label|feature=1) was already near ceiling and
  could not rise — so the odds ratio compresses. Nothing changed about the underlying process; the
  measurement got denser. Disclose as a prevalence/sampling-density property of the split.

<!-- NOTE(paper): P0-J REJECTED on the conditional test. Marginal density shift ≠ informativeness. -->
<!-- NOTE(paper): at H=7/14 the feature is significantly LESS informative in test (OR ratio ~0.55, p<1e-6). -->
<!-- NOTE(limitation): temporal split has a prevalence/sampling-density shift; disclose it. Not a supervision-fix trigger. -->
