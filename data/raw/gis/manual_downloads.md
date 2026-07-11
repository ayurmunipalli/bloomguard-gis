# GIS / Static Layers — Download Notes

Generated: 

## GEBCO 2026 Bathymetry (DOWNLOADED — no manual step needed)

**Status:** REAL — downloaded via GEBCO queue API (download.gebco.net/api/queue)
**Cite:** GEBCO Compilation Group (2026). GEBCO 2026 Grid.
  British Oceanographic Data Centre. doi:10.5285/1c44ce99-0a0d-5f4f-e063-7086abc0ea0f
**File:** data/raw/gis/gebco/gebco_2026_n31.0_s24.0_w-87.0_e-81.0_geotiff.tif
**Resolution:** ~450 m (15 arc-second), EPSG:4326
**API used:**
  POST https://download.gebco.net/api/queue
  Body: {"items":[{"data_source_ids":[1],"formats":[2],"left":-87,"right":-81,"top":31,"bottom":24}]}
  Then poll: GET https://download.gebco.net/api/queue/status/{basketId}
  Then: GET https://download.gebco.net/api/queue/download/{basketId}

## Census TIGER 2023 Counties (DOWNLOADED — no manual step needed)

**Status:** REAL — tl_2023_us_county.zip and tl_2023_us_coastline.zip
**Source:** https://www2.census.gov/geo/tiger/TIGER2023/COUNTY/
**License:** Public domain (US government work)
