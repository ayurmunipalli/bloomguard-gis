# CLAUDE.md — repo operating manual

> Claude Code auto-loads this file. It governs **how agents behave**.
> `PLAN.md` governs **what we decided and why** (§2 pinned decisions, §8 feature spec,
> §9 evaluation protocol are **live spec**, not history).
> `PROJECT.md` governs **what we are doing now and when we stop**.
>
> Where these conflict, the more specific file wins for its own domain — and **the conflict is a
> stop-and-report event**, not something to resolve locally. Three sources of truth is D-22 and
> it has already happened once.
>
> Revision 2026-07-16.

---

## Model assignment

**Rule:** anything that *decides* or *exercises judgment* runs **Fable 5** (`claude-fable-5`).
Anything that *verifies against a written checklist* or *records what happened* runs
**Opus 4.8** (`claude-opus-4-8`). This supersedes the per-agent model tags in `PLAN.md §6`.

| Agent | Canonical name | Model |
|---|---|---|
| A5 | `env-features` | fable-5 |
| A6 | `datacube` | fable-5 |
| A7 | `modeling` | fable-5 |
| A8 | `explain` | fable-5 |
| A9 | `gis` | fable-5 |
| A10 | `validation` | fable-5 |
| A-ARM | `arm-parity` | fable-5 |
| A-DOC | `doc-citations` | opus-4-8 |
| **R-POWER** | pre-registration gate | **opus-4-8** |
| **R-PROV** | provenance & single truth | **opus-4-8** |
| **R-STARVE** | too-little-data | **fable-5** |
| **R-SPLIT** | train/test split leakage | **fable-5** |

Do not spawn duplicates. These are the canonical names.
**Retired:** `sourcing`, `grid-clean`, `habsos-label`, `sat-features` (complete — re-running
`sat-features` costs ~6 h for nothing), `transformer` (PLAN.md D7/D8), `R1`–`R6`.

**Why two auditors are on Fable despite being auditors.** Fable 5 sits above Opus 4.8 on the tier
ladder, so "Fable decides, Opus checks" means auditors are weaker than the builders they audit.
That is fine for **mechanical** verification — computing a minimum detectable effect against a
written floor (R-POWER), or checking that a number traces to a command (R-PROV), is far easier
than producing the thing being checked. It is **not** fine for **judgment** work:

- **R-SPLIT** — a silent leakage miss invalidates every number in the paper. Unchanged from the
  previous revision; it was already on Fable, deliberately.
- **R-STARVE** — deciding whether a join is *starved* requires reasoning about what should have
  been there. D-01 passed R6 **and** R-SPLIT because it wasn't leaking. It was starving, and a
  starved feature produces a clean, mechanistically-explained null that is **more** convincing
  than a win. This is the hardest audit in the repo.

**R-STARVE and R-SPLIT are the only agents with authority to block a merge. There is no override.**

---

## Hard rules

Violating any of these is a **stop-and-report** event.

1. **One change at a time.** If you cannot attribute a metric delta to exactly one cause, the
   experiment is void.
2. **Feature parity in any model comparison.** Every arm has identical features, or the mismatch
   is stated in the Result Card. `A-ARM` owns parity across Arm A / Arm B: identical folds,
   seeds, splits, scorer. `ranger`'s bootstrap is row-order-sensitive and `merge()` reorders `dt`
   — an unmatched control drifts ∓0.001–0.006 silently (D-16), which is most of an effect we
   cannot resolve anyway.
3. **One scorer.** `outputs/tables/model_results.csv` is the sole authoritative results table.
   Two tables that disagree **regenerate** — `head_to_head_comparison.csv` was deleted and the
   hazard immediately reappeared as `model_results_bio_inclusive.csv` (P-06). If you produce a
   second results table, R-PROV blocks the merge.
4. **Feature importance for *selection* must be train-derived.** `mean_abs_shap` is computed on
   the test set (D-12). Valid as a diagnostic; **selection leakage** as a criterion. Prune by
   **train-side OOB rank with a pre-declared cut** (PLAN.md §8). OOB calls 3/149 dead, SHAP calls
   86 — that disagreement is a symptom of 2.2 events/feature, not a signal.
5. **Confidence intervals are mandatory.** Every Δ ships with a 30-day block-bootstrap CI,
   n=1000. **No CI ⇒ UNRESOLVED.** Never declare a null on point deltas.
6. **No retraining without explicit authorization.** If a fix does not change features, say so and
   re-score. `best_model.rds` should be byte-identical.
7. **Verify credentials with a minimal test call before any large pull.** On failure, **STOP and
   report** — never write a placeholder. `~/.cdsapirc` was never written and silently blocked
   every ERA5 pull (C3).
   **A HEAD/liveness check is not a credential test.** CHIRPS returns 200 to a single HEAD while
   banning the sustained GET loop within seconds. A test call must be the same *kind* of request
   as the real pull.
8. **Never fabricate data.** A gap is a gap. Report `n_expected` vs `n_retrieved`. Never
   interpolate silently. Never zero-fill. A10 once zero-filled `month`/`doy` and corrupted every
   prediction it scored (D-04-era scoring bug).
9. **Do not cite "Harris et al. 2021, *Harmful Algae* 103:101999."** Fabricated — that article
   number belongs to an unrelated cyanobacteria paper. **Also: "Green, J. W. (2022), *The
   Professional Geographer* 74(1):67–78" does not exist.** CrossRef's full 2022 contents for that
   journal contain no such author, pages, or topic. The RTM/RF grid-cell methodology citation is
   **Wheeler, A. P. & Steenbeek, W. (2021), *J. Quantitative Criminology* 37(2):445–480,
   doi:10.1007/s10940-020-09457-7**. Two fabrications have now been found; **A-DOC must resolve
   every remaining citation against a DOI before submission.**
10. **No prose.** Agents write logs, diagnoses, tables, Result Cards, commit messages. The author
    writes the paper.
11. **Match the statistic to the claim (P-02).** Marginal rates do not test conditional claims.
    Default-threshold metrics do not test skill. Three separate "findings" were artifacts of this:
    persistence "beating" the RF, the transformer's recall "advantage", P0-J "CONFIRMED".
12. **No claim about the repo, the data, or a constant without a command that produced it.**
    State inference as inference, explicitly. If you cannot verify it, write
    `NOTE(verify): <claim> — unverified because <reason>` and move on. Every serious error in this
    project's history has the same shape: a plausible inference reported as a fact. D-01 described
    a bug and called it a property of the world (P-05). The register's own line references have
    gone stale (`07_modeling.R:24`). **A wrong number is worse than a gap.**
13. **R-POWER gates every experiment.** Before a run: state the expected effect size and compare it
    to the resolution floor (PLAN.md D14: **≈ ±0.03 at H=7**, from **333 effective events**). If
    the effect cannot resolve, **do not run it** — or run it pre-declared as underpowered and
    report it as such. Wind, bio-optical, spatial-lag, and cloud-compositing each burned a week
    proving an effect the instrument cannot see.
14. **Every rich-lag model ships against a rich-persistence baseline** (PLAN.md D19), built from
    the same lags that arm uses. Persistence already reaches 70–96% of RF PR-AUC. Enrich the lags
    and you build a better persistence model. Report what satellite bought over it, in the same
    table.
15. **Mirror every `NOTE(limitation)` into `PROJECT.md` in the same commit** (P-04). A caveat that
    lives only in a script header does not propagate — both split defects were correctly found,
    written into a header, and lost for months.

---

## The notes convention

Every script carries a header block:

```r
# ============================================================
# FILE:       06_build_datacube.R
# PURPOSE:    Assemble cell x date x feature datacube for both arms.
# INPUTS:     data/processed/satellite_features_bio_optical.parquet, ...
# OUTPUTS:    data/processed/model_dataset_arm_a.parquet, ..._arm_b.parquet
# TECHNIQUES: calendar-day slope windows, T = label_date - H anchoring
# CITATIONS:  NOTE(cite) tags inline
# ============================================================
```

Inline tags:

```r
# NOTE(paper):      goes in the paper body
# NOTE(cite):       needs a citation resolved by A-DOC
# NOTE(limitation): goes in the limitations section — AND into PROJECT.md, same commit (rule 15)
# NOTE(verify):     an unverified constant or assumption (rule 12)
```

---

## Every experiment produces a Result Card

```
# <experiment_id> — <name>

## Hypothesis        one falsifiable claim, written BEFORE the run
## Power             expected effect vs the +/-0.03 floor. R-POWER sign-off. (rule 13)
## Change            exactly one thing; diff summary + files touched
## Arm               A (portable) or B (instrumented) — never mixed
## Feature parity    every arm has identical features, or state the mismatch
## Metrics           temporal primary; spatial with the prevalence caveat; PR-AUC + p@r80 + ROC
## Baselines         rich-persistence for this arm (rule 14) + chl-only + RF
## Delta vs baseline with 95% block-bootstrap CI. No CI => UNRESOLVED.
## Verdict           WIN / NULL / NEGATIVE / UNDERPOWERED / VOID
## Provenance        the command that produced every number above
```

`UNDERPOWERED` is a first-class verdict. It is **not** the same as `NULL`, and conflating them is
how four negatives got reported as findings about the world rather than about the instrument.

---

## Push before you ask

Commit frequently during long runs — a crash between commits loses more the longer the gap. Push
to the remote; it has drifted 5 commits behind before. Commit `21320f7` sat local-only for a full
session on stale GitHub auth.

**Work lives in git and the filesystem, not in terminal windows** (C1). This has survived one cmux
memory balloon, three window closes, and a garbled terminal with zero loss of committed work,
because state is externalised and no single context is load-bearing. Keep it that way.

**After any interrupted run, check for orphaned launchers before dispatching fresh work.** The
interrupted bio-optical session left a detached auto-resume watchdog — reparented to launchd,
survived session death — that kept relaunching the pull, plus zombie R processes causing a 3-way
write race on one parquet. Resolved with an atomic POSIX lockfile (single writer).

---

## Terminal output → chat (the copy-paste fix)

Copy-pasting agent output out of the terminal arrives garbled. **Do not paste terminal text.**

Write the answer to a file and hand over the file:

```
Write your findings to ~/Desktop/<name>.md
Print only: "Wrote ~/Desktop/<name>.md (<N> lines)"
Do not paste the file into the terminal.
```

Then upload that file. No terminal text crosses the boundary, so nothing can be mangled. This is
also why every diagnostic is a file-producing task, not a print-to-stdout task.

---

## Environment

- **R-first** for data and spatial work (PLAN.md D0). Python only where no R path exists.
- New environmental sources are **sections of `R/05_environmental_features.R`**
  (A=TIGER · B=GEBCO · C=dist-to-shore · D=CHIRPS · E=ERA5 · F=SMAP · G=seasonality · **H=SSH**),
  not new scripts.
- `data/raw/` is organised **by domain** — `gis/`, `habsos/`, `satellite/`, `weather/` — **not by
  product**. There is no per-product directory convention.
- Every dataset gets a row in **`data/metadata/data_sources.md`** with the mandated schema: source
  URL · date accessed · access method · auth Y/N · spatial resolution · CRS · temporal coverage ·
  license · purpose. A-DOC verifies it is complete.
- **`renv.lock` currently records 34 of 176 packages and `ranger` — the model — is unlocked.**
  A clean `renv::restore()` does not install the model. This is not drift; the lockfile is
  decorative. Fix narrowly (`renv::record()`), never a blind full snapshot.
- **`wget` is not installed.** Use R `curl`/`httr2`/`download.file()`.
- `settings.json` `$schema` must be exactly `json.schemastore.org/claude-code-settings.json`. A
  wrong URL makes Claude Code skip the **entire** settings file — silently disabling the sandbox
  allowlist. "Continue without these settings" runs the team with config ignored; always **"Exit
  and fix."** Validate with `python3 -m json.tool`.
- **cmux: pin to ≥ 0.64.17.** Versions 0.64.8/0.64.9 balloon to 5 GB+ and crash. Do **not** run
  `cmux --version` (hangs on old builds); use
  `mdls -name kMDItemVersion /Applications/cmux.app`. Poisoned `session-com.cmuxterm.app*.json`
  files carry a crash forward — move them aside.

---

## Credentials — never commit

| Service | File | Gives |
|---|---|---|
| NASA Earthdata | `~/.netrc` | MODIS (done), SMAP |
| Copernicus **CDS** | `~/.cdsapirc` | ERA5 wind (done) |
| Copernicus **Marine** | `~/.copernicusmarine/` | **SSH — Section H** |
| Copernicus **Atmosphere** | `~/.adsapirc` | CAMS dust AOD (not scheduled) |

**Copernicus has three siblings.** `cds.climate.copernicus.eu` ≠ `marine.copernicus.eu` ≠
`ads.atmosphere.copernicus.eu`. Three services, three accounts, three credential files, one brand.
C4 recorded the first two colliding. Also: accept the licence on the site or downloads 403 with a
valid key.

Never store credentials in the repo or in any script. Never print them.

---

## Satellite pulls — stream-and-discard (mandatory)

MODIS L3 is served as global daily files with no server-side bbox. Per day: download one global
file → clip to 24–31°N/87–81°W → aggregate to the 10 km grid → append → **`unlink()` the raw
file** → next day. Checkpoint by date; resume, never restart. Peak disk ≈ one file (~15 MB) plus a
growing parquet. This is what kept 300–500 GB off the machine.

**The MODIS pull is FINAL — 5,829/5,829 dates. Do not re-pull.**

---

## Parallelism has one carve-out

**ASAP, maximally parallel** is the default (PLAN.md §12). It is not a law.

It is what triggered the CHIRPS CrowdSec ban: 5,829 requests fired at once **is** a bot signature.
Any endpoint that rate-limits gets **serial access with exponential backoff**, and that is not a
violation. A ban is not "transient" and it is not about the IP — wait well over 24 h, and note
that a passing liveness check does **not** mean the ban has lifted for GETs (rule 7).
