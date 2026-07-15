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

## Verdict: **CONFIRMED** — with one correction to the mechanism

The substantive claim holds: at **every horizon** and for **both** features, the positive
(`== 1`) rate is **~1.4–2.0× higher in the test era than in the training era**, monotone in
direction and consistent with an intensive post-2015 HABSOS sampling regime. The RF is trained
where these prior-observation features fire ~7–17% of the time and evaluated where they fire
~14–28% of the time — the history signal is roughly twice as dense exactly where the model is
scored.

**Correction to the literal §2.5 framing:** the effect is **not** in the *non-missing rate*.
Both features are **zero-imputed indicators** (0 = no prior HAB observation in the window), so
`% non-missing = 100%` in both eras at every horizon. The regime shift lives entirely in the
**value distribution** (fraction `== 1`), not in missingness. The `non-missing-rate` instrument
named in §2.5 is therefore the wrong probe for this feature encoding; the `== 1` rate is the
correct one, and it confirms the hypothesis.

<!-- NOTE(paper): P0-J confirms the sampling-regime asymmetry of §2.5. -->
<!-- NOTE(limitation): confirmed via the ==1 rate, not missingness; the features are 0-imputed. -->

## Implication for how the temporal split must be described in the paper
The 2016 temporal split must be described as **partly a sampling-regime shift, not only a time
shift**: the HAB-history features (and, per §6, label prevalence) are ~1.5–2× denser in the
held-out era, so the temporal number measures transfer across a HABSOS sampling regime — and
persistence, which reads that prior-observation signal directly, is advantaged exactly where it
is evaluated.

## Downstream (author decision — not actioned here)
PROJECT.md §7.3 pivot trigger: *"P0-J confirms the sampling-regime hypothesis → escalate the
supervision fix to a live experiment ahead of E-04. Author decision."* This diagnostic clears
that trigger's condition; the escalation is an author call, not initiated by this task.
