# ============================================================
# FILE:       R/09c_maps.R
# PURPOSE:    M3-4 — the risk-surface maps (GeoTIFF + PNG, EPSG:5070) for 4 dates chosen to
#             show the product honestly (not a highlight reel): a 2017-19 mega-bloom day the
#             model never trained on, a clean true-positive, a false-positive, a missed bloom.
#             HABSOS sample points overlaid so prediction vs ground truth is visible.
# INPUTS:     outputs/gis/risk_surface_H7.parquet, study_area_grid.gpkg, static_geo, habsos
# OUTPUTS:    outputs/gis/risk_map_<tag>_<date>.tif (gitignored) + .png (committed, small)
# ============================================================
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); library(data.table); library(sf); library(terra); library(ggplot2) })
TAU <- 0.4582   # M3-3 operating threshold (precision->0.5 on H=7 temporal test)
DATES <- list(c("2018-10-29","megabloom_2018_untrained"), c("2018-08-27","true_positive"),
              c("2016-08-11","false_positive"), c("2016-11-21","missed_bloom"))

surf <- as.data.table(read_parquet("outputs/gis/risk_surface_H7.parquet")); surf[,date:=as.Date(date)]
grid <- st_read("data/processed/study_area_grid.gpkg", quiet=TRUE)          # EPSG:5070 polygons
stat <- as.data.table(read_parquet("data/processed/static_geo.parquet"))
lab  <- as.data.table(read_parquet("data/processed/habsos_labels.parquet",col_select=c("cell_id","sample_date","HAB")))
lab[,sample_date:=as.Date(sample_date)]
setkey(stat,cell_id)
dir.create("outputs/gis",showWarnings=FALSE,recursive=TRUE)

for (dd in DATES) {
  D <- as.Date(dd[1]); tag <- dd[2]
  # snap: latest clear score per cell in [D-7, D]
  w <- surf[date>=D-7 & date<=D]; setorder(w,cell_id,date); r <- w[, .SD[.N], by=cell_id][,.(cell_id,prob)]
  g <- merge(grid, r, by="cell_id", all.x=TRUE)
  # GeoTIFF (rasterize prob onto a 10 km raster in EPSG:5070)
  tif <- sprintf("outputs/gis/risk_map_%s_%s.tif", tag, gsub("-","",dd[1]))
  rast_tmpl <- terra::rast(terra::vect(g), resolution=10000)
  terra::writeRaster(terra::rasterize(terra::vect(g), rast_tmpl, field="prob"), tif, overwrite=TRUE)
  # HABSOS points for that day (+/- 3 d) as ground truth
  lp <- lab[abs(as.integer(sample_date-D))<=3]; lp <- merge(lp, stat[,.(cell_id,centroid_lon,centroid_lat)], by="cell_id")
  pts <- if(nrow(lp)) st_transform(st_as_sf(lp, coords=c("centroid_lon","centroid_lat"), crs=4326), 5070) else NULL
  # PNG
  p <- ggplot(g) + geom_sf(aes(fill=prob), color=NA) +
    scale_fill_viridis_c(option="magma", na.value="grey85", limits=c(0,1), name="H+7 risk") +
    labs(title=sprintf("Arm A risk surface — %s (%s)", D, gsub("_"," ",tag)),
         subtitle=sprintf("flag threshold tau=%.3f (precision 0.50 / recall 0.17 on test). Points = HABSOS same-week samples.", TAU),
         caption="EPSG:5070. Cloudy cells (grey) have NO prediction — not imputed. Model trained on years <2016.")
  if(!is.null(pts)) p <- p + geom_sf(data=pts, aes(shape=factor(HAB)), size=1.6, stroke=0.6, color="cyan") +
    scale_shape_manual(values=c("0"=4,"1"=19), name="HABSOS", labels=c("0"="non-detect","1"="bloom>=1e5"))
  ggsave(sprintf("outputs/gis/risk_map_%s_%s.png", tag, gsub("-","",dd[1])), p, width=8, height=6, dpi=110)
  cat(sprintf("%s (%s): %d cells scored in window, %d flagged>=tau, %d HABSOS pts -> %s (.tif/.png)\n",
      D, tag, sum(!is.na(g$prob)), sum(g$prob>=TAU,na.rm=TRUE), nrow(lp), tag))
}
cat("=== 09c DONE ===\n")
