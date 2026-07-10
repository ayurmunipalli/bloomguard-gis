# ============================================================
# FILE: 01_source_data.R
# OWNER: A1 sourcing (reviewer R1)
# PURPOSE: API pulls for HABSOS + MODIS (+ ERA5/CHIRPS/SMAP/static). For anything
#          not API-pullable, write exact steps to data/raw/<source>/manual_downloads.md.
# INPUTS:  config.yaml; credentials in ~/.netrc (Earthdata), ~/.cdsapirc (CDS).
# OUTPUTS: raw files under data/raw/**; source log for A-DOC.
# TECHNIQUES: httr2/download.file (NO wget); Earthdata + CDS auth; server-side bbox
#             for ERA5/CHIRPS; stream-and-discard governed in 04_satellite_features.R.
# CITATIONS: NOAA NCEI HABSOS; NASA OB.DAAC; Copernicus CDS ERA5; UCSB CHIRPS.
# ============================================================

# Bootstrap: walk up to the repo root (dir with config.yaml) and load config.
local({ d <- getwd(); while (!file.exists(file.path(d, "config.yaml")) && dirname(d) != d) d <- dirname(d)
        source(file.path(d, "R", "00_config.R")) })

# NOTE(paper): prefer APIs; manual export only where no API exists (author's standing rule).
# NOTE(limitation): HABSOS non-detection != absence — carried through to labels.

stop("TODO(A1 sourcing): implement data pulls. See PLAN.md §5/§6-A1 and manual_downloads.md files.")
