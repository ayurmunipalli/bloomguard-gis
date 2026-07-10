# Weather / environmental (ERA5 wind, CHIRPS precip, SMAP salinity) — access notes

**Purpose:** environmental features — wind, precipitation, salinity (§8-A).

## ERA5 wind (Copernicus CDS — server-side bbox, use it)
- Requires CDS API key in `~/.cdsapirc`.
  Portal: https://cds.climate.copernicus.eu/
- Request 10 m u/v wind components for the Gulf box directly via `area: [31, -87, 24, -81]`
  (N, W, S, E). No global download needed.
- Python `cdsapi` acceptable for the pull (env layer); or `httr2` against the CDS API.

## CHIRPS precipitation (UCSB CHC — server-side bbox)
- https://data.chc.ucsb.edu/products/CHIRPS-2.0/
- Daily rainfall; subset to the Gulf box. Auth typically not required.

## SMAP sea-surface salinity (RSS / PODAAC — Earthdata auth)
- Requires Earthdata login (`~/.netrc`). ~40–70 km — **broad-context feature only**, flag it.
- PODAAC: https://podaac.jpl.nasa.gov/

## Notes
- Prefer APIs; document exact manual steps here only if a host is blocked (prompt/403).
- Record URL + access date + auth for each in `data/metadata/data_sources.md`.
