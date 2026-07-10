# Decisions log

Records any change to the pinned decisions in `PLAN.md §2` (D0–D12). Only the lead may change
a pinned decision, and only with an explicit written rationale recorded here.

Format: `YYYY-MM-DD — <decision #/topic> — <old value> → <new value> — <rationale> — <author>`

## Changes

- _(none yet — all §2 decisions stand as written in PLAN.md)_

## Open items flagged during scaffolding (2026-07-11, lead)

- **HABSOS export is Darwin Core `occurrence.txt` with only 12 columns** (id, basisOfRecord,
  occurrenceID, organismQuantity, organismQuantityType, occurrenceStatus, eventID,
  scientificNameID, scientificName, kingdom, genus, specificEpithet). It carries
  `organismQuantity` (cell count) and `occurrenceStatus` (present/absent) but **no visible
  coordinates or eventDate**. habsos-label (A3) + reviewer R3 must resolve where lat/lon/date
  live (companion DwC-A files, verbatim.txt, or a re-pull with geo fields) before labels can
  be built. Do not fabricate coordinates/dates — document the blocker if unresolved.
