# BloomGuard GIS — publication source set (A-DOC · FINAL deliverable)

> **This is the project's final deliverable.** For every decision, method, and dataset used
> anywhere in the project, this document gives a publication-ready entry (plain-language
> description + the citation to use + which agent/file it came from), organized by paper
> section so the author can lift it straight into the manuscript.
>
> A-DOC builds this from every `reports/agent_logs/*.md` and the inline `NOTE()` tags.
> **A-DOC does NOT write the paper** — no abstract, intro, related-work, or discussion prose.
> **No invented citations.** Every entry here resolves to an entry in `references.bib`.

_Status: seeded during scaffolding; populated continuously as agents land work._

---

## Data
_(dataset entries: what it is, access, resolution/CRS/coverage, license, which agent/file used it, citation)_

## Methods
_(spatial engineering, gridding, feature construction, trend features, leakage controls)_

## Modeling
_(Stage-1 Random Forest; Stage-2 transformer; baselines; evaluation protocol)_

## Results
_(tables/figures the author reports from — filled after M1/M3)_

## Limitations
- HABSOS non-detection ≠ proven absence (sampling gaps).
- MODIS ~4.6 km pixels vs. 10 km cells; SMAP salinity ~40–70 km (broad-context only).
- Intra-cell attention drill-down is diagnostic feature concentration, not a sub-cell forecast.
- No causal claims; no "first ever"; no "operationally ready" without hard-split survival.
