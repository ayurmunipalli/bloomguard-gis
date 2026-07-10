# BloomGuard GIS — repo operating manual (Claude Code auto-loads this)

**PLAN.md is the source of truth.** Read it in full before acting. If this file and PLAN.md
conflict on a project decision, PLAN.md wins. This file = how we operate in this repo.

## Environment
- R-first. Data/spatial/modeling pipeline is R (sf, sftime, stars, tmap, data.table,
  ranger/caret). Use renv; commit renv.lock. Python only for the Stage-2 transformer.
- Commit the pipeline as sourced .R scripts that run end-to-end, not notebooks.
- Network egress IS available: NASA/NOAA/Copernicus/CRAN + package repos are allowlisted in
  ~/.claude/settings.json — pull data directly in-pipeline. If a host is still blocked
  (prompt or 403), note it and fall back to data/raw/<source>/manual_downloads.md.
- wget is NOT installed on this machine. Use R's download.file()/httr2, or curl. Never wget.

## Credentials (never commit)
- NASA Earthdata -> ~/.netrc. Copernicus CDS -> ~/.cdsapirc.
- .gitignore must exclude: data/raw/, *.tif, *.rds, *.pkl, .env, any keys/tokens.

## Satellite pulls — stream-and-discard (mandatory)
MODIS L3 is global-file-only (no server-side bbox). NEVER bulk-download the archive.
Per day: download -> clip to 24-31N/87-81W -> aggregate to the 10 km grid -> append rows
-> DELETE the raw file. Make it resumable (checkpoint by date). Do deletions in-script
(R unlink()/file.remove()), not shell rm. ERA5/CHIRPS support server-side bbox — use it.

## Notes convention (this is how the paper gets written — enforce it)
Every script opens with a header block: FILE / PURPOSE / INPUTS / OUTPUTS / TECHNIQUES /
CITATIONS. Tag anything the author will cite or explain: NOTE(paper): NOTE(cite):
NOTE(limitation):. Untagged work does not reach the paper. A-DOC harvests these.

## Project guardrails (on top of the global ones)
- This is FORECASTING: label at day T+H from features observed through T. No look-ahead
  leakage, ever — every feature/rolling stat computed at or before T.
- HABSOS non-detection != proven absence. State this wherever labels are used.
- "Associated with," never "causes." The intra-cell attention layer shows feature
  concentration, NOT a validated sub-cell forecast — label it that way.

## Teammates (canonical names — do not spawn duplicates)
doc-citations (A-DOC), sourcing, grid-clean, habsos-label, sat-features, env-features,
datacube, modeling, explain, gis, validation, transformer.

## Reporting
Return to the lead: did / file produced / done-criteria pass-fail / blocker. Summaries,
not transcripts. Run /commit-push-pr at each milestone.
