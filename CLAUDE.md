# CLAUDE.md — repo operating manual (Claude Code auto-loads this)

**Three files govern this repo. They do not compete:**

- **`CLAUDE.md`** (this file) — *how* we operate. Model assignment, hard rules, push discipline,
  result cards, environment. **Wins on any operating question.**
- **`PLAN.md`** — *the spec*. Pinned scientific decisions (§2), feature spec (§8), evaluation
  protocol (§9), guardrails (§1), agent roles (§6). **Live reference — its §2 is still binding and
  must not be relitigated.** Its §3 milestones (M1–M3) are complete, and its §6 per-agent model
  tags are superseded by the table below.
- **`PROJECT.md`** — *the program*. What is being built now, the queue, the scoreboard, the pivot
  triggers, and the corrections in its §2. **Wins on any "what do we build next" question.**

Read all three. If PLAN.md and PROJECT.md conflict on *what to build*: PROJECT.md. If either
conflicts with this file on *how to operate*: this file.

---

## Model assignment

**Rule:** anything that *decides* runs **Fable 5** (`claude-fable-5`). Anything that *verifies
against a written checklist* or *records what happened* runs **Opus 4.8** (`claude-opus-4-8`).
This supersedes the per-agent model tags in `PLAN.md §6`, which are stale.

| Agent | Canonical name | Model |
|---|---|---|
| A1 | `sourcing` | fable-5 |
| A2 | `grid-clean` | fable-5 |
| A3 | `habsos-label` | fable-5 |
| A4 | `sat-features` | fable-5 |
| A5 | `env-features` | fable-5 |
| A6 | `datacube` | fable-5 |
| A7 | `modeling` | fable-5 |
| A8 | `explain` | opus-4-8 |
| A9 | `gis` | fable-5 |
| A10 | `validation` | opus-4-8 |
| A11 | `transformer` | fable-5 |
| A-DOC | `doc-citations` | opus-4-8 |
| R1–R5 | paired reviewers (A1–A5) | opus-4-8 |
| **R6** | datacube leakage | **fable-5** |
| **R-SPLIT** | train/test split leakage | **fable-5** |

Do not spawn duplicates. These are the canonical names.

**Why R6 and R-SPLIT are on Fable despite being reviewers.** Fable 5 sits above Opus 4.8 on the
tier ladder, so "Fable decides, Opus checks" means reviewers are weaker than builders. That is
fine for mechanical verification — checking *"does this split have an embargo"* is far easier
than designing one. It is **not** fine for leakage detection, which is judgment work where a
silent miss invalidates every number in the paper. R-SPLIT has already issued two conditional
passes that the master record lost track of (see PROJECT.md §2). These two are the only
reviewers with authority to **block a merge**, and there is no override.

---

## Push before you ask (mandatory)

**Any time you are about to hand a decision back to the author, commit and push first.**

The author reviews this repo through a Claude chat session that reads the *public* GitHub state.
Unpushed work is invisible to that review. This is not a nicety: one review pass against the
pushed repo caught four material errors that the summary documents had lost — a test-set-derived
importance table, two conditional-pass split caveats, a feature-mismatched head-to-head, and a
horizon sample-size confound. **A question asked against unpushed state gets a worse answer.**

- Before any stop-and-report, author decision, or gate escalation: `git add -A && git commit && git push`.
- The commit message states **what is being asked**, not only what was done.
  Format: `wip(<agent>): <what was done> — BLOCKED ON: <the question for the author>`
- **WIP is fine.** A pushed WIP commit beats a clean unpushed one. Do not tidy before pushing.
- No experiment is finished until its Result Card is pushed.
- **If `git push` fails on auth, that IS the blocker.** Fix it (`gh auth login`) before asking
  anything else. A local-only commit is a commit that does not exist — commit `21320f7`
  (bio-optical, a documented negative result) has been stranded on one laptop for exactly this
  reason.
- Push at the end of every long run, not just at milestones. The remote has drifted 5 commits
  behind before.

## The notes convention (this is how the paper gets written — enforce it)

Every script opens with a header block: FILE / PURPOSE / INPUTS / OUTPUTS / TECHNIQUES /
CITATIONS. Tag anything the author will cite or explain:

```
# NOTE(paper):      goes in the paper body
# NOTE(cite):       needs a citation resolved by A-DOC
# NOTE(limitation): goes in the limitations section
```

**Untagged work does not reach the paper.** A-DOC harvests these into `paper/source_set.md`.

This convention already works and is the reason the split caveats survived at all — R-SPLIT wrote
them as `NOTE(limitation)` in `R/07_modeling.R:38–60` and they are still the most accurate
account of the split's honesty in the repo. **Corollary, learned the hard way: a caveat that
lives only in a script header will not propagate to summary documents. Anything that changes what
a headline number *means* must also be written to `PROJECT.md §2` in the same commit.**

Every agent also maintains `reports/agent_logs/<name>.md`: Decisions / Data sources used /
Methods & techniques / Open questions & caveats.

---

## Hard rules (violating any of these is a stop-and-report event)

1. **One change at a time.** If you cannot attribute a metric delta to exactly one cause, the
   result is worthless.
2. **Feature parity in any model comparison.** The current RF-vs-transformer head-to-head is
   feature-mismatched (RF has ERA5 wind; the transformer does not). Never compare two models
   trained on different feature sets and report it as a model-architecture result.
3. **One scorer.** `model_results.csv` is authoritative (post-wind). `head_to_head_comparison.csv`
   is stale (pre-wind RF) and must be regenerated or deleted, not read.
4. **Feature importance for *selection* must be train-derived.** `mean_abs_shap` in
   `top_features.csv` / `variable_importance.csv` is computed by permuting the **test set**
   (`R/08_explainability.R:169–178`). It is a valid *diagnostic* and invalid as a *selection
   criterion* — pruning or choosing features by it is test-set leakage. Use
   `permutation_importance` (ranger OOB, train-side) or importance recomputed on training folds.
   The two disagree materially in this repo (see PROJECT.md §2.5); do not treat them as
   interchangeable.
5. **Confidence intervals are mandatory.** Every Δ ships with a block-bootstrap CI (blocks =
   contiguous time segments, n=1000, report block length), or the verdict is `UNRESOLVED`, not
   `NULL`. The effects being chased (~0.01 PR-AUC) are the same size as the effects already
   declared null. Without a CI those declarations are assertions.
6. **No retraining without explicit authorization.** If a fix does not change features, say so
   and confirm the artifact is byte-identical.
7. **Verify credentials with a minimal test call before any large pull.** On failure, STOP and
   report. Never write a placeholder credential.
8. **Never fabricate data.** A gap is a gap. Report `n_dates_expected` vs `n_dates_retrieved`.
   Placeholders are always labeled `IS_PLACEHOLDER = TRUE`.
9. **Do not cite "Harris et al. 2021, *Harmful Algae* 103:101999."** Appears fabricated; that
   article number belongs to an unrelated cyanobacteria paper. Real comparators: PROJECT.md §8.
10. **No prose.** Agents write logs, diagnoses, tables, commit messages. The author writes the paper.
11. **Match the statistic to the claim.** Marginal rates do not test conditional claims;
    default-threshold metrics do not test skill. Before declaring any finding, state whether the
    number is marginal or conditional, default-threshold or matched-recall — and whether that is
    the quantity the claim actually needs. Three apparent findings in this project (persistence
    beating the RF, bio-optical harming skill, P0-J CONFIRMED) were artifacts of the wrong one.

---

## Project guardrails

- **This is FORECASTING:** label at day T+H from features observed through T. Every feature and
  rolling statistic computed at or before T. No look-ahead, ever.
- **HABSOS non-detection ≠ proven absence.** May be unsampled. State this wherever labels are
  used. It is not a footnote — it is a live confound in every recall number.
- **"Associated with," never "causes."**
- **The intra-cell attention drill-down shows where flagging conditions concentrate** — a
  diagnostic overlay, **not** a validated sub-cell forecast. Floor is the ~4 km MODIS pixel.
- **No "operationally ready" claim** unless the model survives the temporal/spatial splits — and
  see PROJECT.md §2 before assuming it has.

---

## Environment

- **R-first.** `sf`, `sftime`, `stars`, `tmap`, `data.table`, `ranger`/`caret`, `arrow`, `httr2`.
  Sourced `.R` scripts that run end-to-end — not notebooks. `renv`; commit `renv.lock`.
- **Python only** where R has no path: the Stage-2 transformer (`python/`) and TabPFN v2.
  Handoffs go through parquet on disk, never in-memory bridges.
- **`wget` is NOT installed.** Use R `download.file()`/`httr2`, or `curl`. Never wget.
- **Arrow thread guard:** source `R/00_config.R` *before* `library(arrow)` — it sets
  `ARROW_NUM_THREADS=1`. Skipping this deadlocked the host once (7 processes at 95% CPU, 15 h).
- **`renv.lock` fixes are narrow only** (`renv::record("pkg")`), never a blind full snapshot.
  `ecmwfr` is installed-but-unlocked; fix it that way.

## Credentials (never commit)
NASA Earthdata → `~/.netrc`. Copernicus CDS → `~/.cdsapirc`.
**`cds.climate.copernicus.eu` (Climate Data Store, ERA5) ≠ `marine.copernicus.eu`** — different
service, account, and credential. Accept the ERA5 licence on the CDS site or downloads 403 with a
valid key. `.gitignore` must exclude `data/raw/`, `*.tif`, `*.rds`, `*.pkl`, `.env`, keys/tokens.

## Satellite pulls — stream-and-discard (mandatory)
MODIS L3 is global-file-only (no server-side bbox). **Never bulk-download the archive.** Per day:
download → clip to 24–31°N/87–81°W → aggregate to the 10 km grid → append rows → **delete the raw
file**, in-script (`unlink()`/`file.remove()`), not shell `rm`. Checkpoint by date so an
interruption resumes rather than restarts. ERA5/CHIRPS support server-side bbox — use it.

---

## Every experiment produces a Result Card

Not done until `reports/results/<experiment_id>.md` exists and its row is in `PROJECT.md §6`.

```
# <experiment_id> — <name>

## Hypothesis          one falsifiable claim, written BEFORE the run
## Change              exactly one thing; diff summary + files touched
## Feature parity      confirm every arm has identical features, or state the mismatch
## Metrics             temporal split primary; spatial reported with the prevalence caveat;
                       random indicative only. PR-AUC, p@r80, recall, FNR, base rate, n_test.
## Δ vs baseline       with 95% block-bootstrap CI. No CI => UNRESOLVED.
## Verdict             WIN / NULL / NEGATIVE / UNRESOLVED / SUSPECT (PROJECT.md §6.2)
## Mechanistic check   did it move the errors it was supposed to move?
                       (e.g. FP concentration ratio before/after)
## Baselines           did it beat persistence on recall AND FNR AND PR-AUC?
## Importance source   if feature selection was involved: state that it was train-side/OOB
## Gate status         R6: PASS/FAIL/BLOCKED · R-SPLIT: PASS/FAIL/BLOCKED
## Pushed              commit SHA — the card is not done until it is on the remote
```

A metric that moves for the wrong reason is not a win. **A model that loses to persistence on
recall and FNR is not a headline model, whatever its PR-AUC.**

---

## Operational discipline (do not relearn)

- **Commit frequently during long runs**, not at milestones. Push; the remote has drifted before
  and currently lacks the bio-optical branch entirely.
- **`caffeinate -i` for any pull over ~30 min.** A sleeping Mac stalls pulls silently.
- **After any interrupted run, hunt for orphans first.** A detached watchdog reparented to
  launchd once kept relaunching a pull after its session died; zombie R processes caused a 3-way
  parquet write race. Kill orphaned launchers *before* dispatching fresh work. Single-writer
  parquet access is enforced by atomic POSIX lockfile.
- **cmux pinned to 0.64.17.** Never run `cmux --version` (hangs on old builds); use
  `mdls -name kMDItemVersion /Applications/cmux.app`. Poisoned
  `session-com.cmuxterm.app*.json` carries crashes forward — move it aside.
- **Validate `settings.json` with `python3 -m json.tool`.** A wrong `$schema` makes Claude Code
  silently skip the *entire* file, disabling the sandbox allowlist. If offered "Continue without
  these settings" — always **Exit and fix**.
- **Work lives in git and the filesystem, not terminal windows.** Recovery pattern for every
  crash so far: read `git log` + `reports/agent_logs/`, resume from disk.

## Reporting
Return to the lead: did / file produced / done-criteria pass-fail / blocker. Summaries, not
transcripts. Run `/commit-push-pr` at each milestone.

---

## When to stop and ask

- A gate (R6 / R-SPLIT) fails and the fix requires changing the split or the label.
- The result would change the target definition (e.g. ordinal-severity reframe). Author decision.
- **A metric improves by more than +0.05 PR-AUC from one change.** That is more likely leakage
  than skill. Treat it as a bug report until R6 and R-SPLIT clear it.
- You are about to re-run an experiment with different hyperparameters after a NULL. **Halt.**
  That is optimizing against the test set, and it is the one thing that would retroactively
  devalue every honest result in this repo.

## The discipline that makes the results worth anything

The failure mode is not a bad model. It is a *murky* one — a "we threw everything at it" story
where nobody can say which lever did what. The negative results are assets **because** they were
not tuned away. If a lever comes back NULL: document it and move on. A clean null is publishable.
A null hammered into a marginal win is a liability.