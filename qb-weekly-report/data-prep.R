# data-prep.R - Precompute per-game QB stats for every season.
#
# The app reads these files instead of loading raw play-by-play data, which
# keeps memory under the 1GB shinyapps.io limit and makes startup instant.
#
# Run this locally, then redeploy:
#   setwd("qb-weekly-report")   # if not already there
#   source("data-prep.R")
#   rsconnect::deployApp()
#
# IMPORTANT: rerun this whenever (a) new games are played in the current
# season, or (b) the stat logic in global.R changes - otherwise the deployed
# app serves numbers computed with the old data/logic.

source("global.R")

SEASONS <- 2021:2025

dir.create("data", showWarnings = FALSE)

for (s in SEASONS) {
  message("Processing season ", s, " ...")
  stats <- fetch_qb_stats(season = s)
  out_file <- file.path("data", paste0("qb_stats_", s, ".rds"))
  saveRDS(stats, out_file)
  message("  Wrote ", out_file, " (", nrow(stats), " QB-game rows)")
}

message("Done. Redeploy with: rsconnect::deployApp()")
