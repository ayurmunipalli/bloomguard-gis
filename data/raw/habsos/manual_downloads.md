# HABSOS — manual download / access notes

**Purpose:** ground-truth *Karenia brevis* cell counts → binary HAB labels (D2).

## What is present
- `occurrence.txt` — Darwin Core occurrence export (~190k rows). Columns: `id`,
  `basisOfRecord`, `occurrenceID`, `organismQuantity` (cell count), `organismQuantityType`
  (`cells/L`), `occurrenceStatus` (`present`/`absent`), `eventID`, `scientificNameID`,
  `scientificName` (`Karenia brevis`), `kingdom`, `genus`, `specificEpithet`.

## ⚠️ Gap to resolve before labeling (A1/A3 + R3)
This slice has **no visible `decimalLatitude`/`decimalLongitude`/`eventDate`.** HABSOS labels
require coordinates + date. Resolve one of:
1. The full Darwin Core Archive (DwC-A `.zip`) usually ships companion files
   (`verbatim.txt`, `meta.xml`, `event.txt`) that carry `decimalLatitude`, `decimalLongitude`,
   `eventDate`, `depth`. Locate/obtain them.
2. Re-export from the HABSOS portal with geographic + date fields included.

Do **not** fabricate coordinates or dates. If unresolved, keep a clearly-labeled placeholder
and record the exact re-pull steps here.

## Source
- NOAA NCEI HABSOS landing page:
  https://www.ncei.noaa.gov/products/harmful-algal-blooms-observing-system
- Map viewer / data export portal linked from that page.

## Manual export steps (fill exact steps once confirmed)
1. Open the HABSOS data portal.
2. Filter species = *Karenia brevis*, region = Gulf of Mexico / West Florida Shelf.
3. Export with fields: latitude, longitude, sample date/time, cell count (cells/L), agency,
   sample depth.
4. Save to `data/raw/habsos/`. Record URL + access date in `data/metadata/data_sources.md`.
