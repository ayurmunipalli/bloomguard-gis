# ============================================================
# FILE:       R/09d_drilldown.R
# PURPOSE:    M3-5 / D12 — intra-cell drill-down. For ONE flagged 10 km cell, show the
#             ~4 km MODIS chlor_a pixels within it, i.e. WHERE the flag-driving condition
#             concentrates. This is a FEATURE-CONCENTRATION OVERLAY, NOT a validated
#             sub-cell forecast. The floor is the ~4 km pixel. NO skill metric is computed
#             (there is no sub-cell label to score against — any number would be fiction).
# INPUTS:     risk_surface_H7.parquet, study_area_grid.gpkg, one MODIS L3m 4km granule
#             (re-pulled for 2018-10-29; the 4 km raw is otherwise stream-and-discarded).
# OUTPUTS:    outputs/gis/drilldown_cell<ID>_20181029.png (committed)
# ============================================================
local({ d<-getwd(); while(!file.exists(file.path(d,"config.yaml"))&&dirname(d)!=d) d<-dirname(d); source(file.path(d,"R","00_config.R")) })
suppressPackageStartupMessages({ library(arrow); library(data.table); library(sf); library(terra); library(ggplot2) })
NC <- Sys.getenv("MODIS_NC"); TAU <- 0.4582; D <- as.Date("2018-10-29")

surf <- as.data.table(read_parquet("outputs/gis/risk_surface_H7.parquet")); surf[,date:=as.Date(date)]
grid <- st_read("data/processed/study_area_grid.gpkg", quiet=TRUE)
# flagged cells in the mega-bloom window, pick the highest-risk one that has neighbours (interior)
w <- surf[date>=D-7 & date<=D]; setorder(w,cell_id,date); r <- w[,.SD[.N],by=cell_id][prob>=TAU][order(-prob)]
cell_id_sel <- r$cell_id[1]
cat("selected flagged cell:", cell_id_sel, "prob=", round(r$prob[1],3), "\n")
cellpoly <- grid[grid$cell_id==cell_id_sel,]
cell4326 <- st_transform(cellpoly, 4326); bb <- st_bbox(cell4326)

# read MODIS L3m 4 km chlor_a global raster, crop to the cell
modis <- terra::rast(NC); nm <- grep("chlor_a", names(modis), value=TRUE); if(length(nm)) modis <- modis[[nm[1]]]
sub <- terra::crop(modis, terra::ext(bb["xmin"]-0.02, bb["xmax"]+0.02, bb["ymin"]-0.02, bb["ymax"]+0.02))
px <- as.data.frame(sub, xy=TRUE); names(px)[3] <- "chlor_a"
cat("4 km pixels inside/near the cell:", nrow(px), " chlor_a range [",
    round(min(px$chlor_a,na.rm=TRUE),3),",",round(max(px$chlor_a,na.rm=TRUE),3),"] mg/m3\n")

p <- ggplot() +
  geom_tile(data=px, aes(x=x, y=y, fill=chlor_a)) +
  scale_fill_viridis_c(option="viridis", trans="log10", name="chlor_a\n(mg/m3, 4km)") +
  geom_sf(data=cell4326, fill=NA, color="red", linewidth=0.9) +
  labs(title=sprintf("DIAGNOSTIC OVERLAY (NOT a sub-cell forecast) — cell %s, %s", cell_id_sel, D),
       subtitle="~4 km MODIS chlor_a pixels inside one flagged 10 km cell (red). The ~4 km pixel is the floor.",
       caption="D12 feature-concentration overlay. NO skill metric: there is no sub-cell label to validate against.",
       x="lon", y="lat") +
  theme(plot.title=element_text(face="bold", color="red"))
ggsave(sprintf("outputs/gis/drilldown_cell%s_20181029.png", cell_id_sel), p, width=7, height=6, dpi=120)
cat(sprintf("=== 09d DONE: outputs/gis/drilldown_cell%s_20181029.png ===\n", cell_id_sel))
