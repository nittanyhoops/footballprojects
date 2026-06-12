# Football Projects

## QB Weekly Report (`qb-weekly-report/`)

R Shiny dashboard for college QB stats (traditional + EPA), deployed to
shinyapps.io. Data from cfbfastR play-by-play.

### REMINDER: Adding the 2026 season (user will ask in late August 2026)

The app serves precomputed stat files, NOT live cfbfastR data, because the
raw play-by-play exceeds shinyapps.io's 1GB memory limit. To add 2026:

1. In `qb-weekly-report/data-prep.R`: change `SEASONS <- 2021:2025` to `2021:2026`
2. In `qb-weekly-report/global.R`: change `CURRENT_SEASON <- 2025` to `2026`
3. In `qb-weekly-report/ui.R`: add `2026` to the season `selectInput` choices
   (first in the list, and set `selected = 2026`)
4. User runs locally: `setwd("qb-weekly-report"); source("data-prep.R")`
5. User redeploys: `rsconnect::deployApp()`
6. During the season, steps 4-5 must be rerun after each week's games to pick
   up new data (the deployed app shows whatever the .rds files contained at
   deploy time)

### Key data-quality corrections (do not undo)

`fetch_qb_stats()` in global.R corrects several cfbfastR data issues, all
validated against ESPN season totals (Beck 30 TD, Simpson 28, Sayin 32,
Mendoza 41, Pavia 29):

- Recovers passer/rusher names from play_text when cfbfastR fails to parse
  them (~37% of passing TD plays have NA passer_player_name)
- Excludes TDs nullified by replay review (pass_td stays 1 on overturned
  calls; final ruling is parsed from play_text before "(Original Play:")
- Passing yards sum over completions only (yards_gained on INTs holds the
  defender's return yardage)
- Kneel-downs excluded from rush stats
- Plays deduplicated by id_play; postseason games are all coded week=1, so
  games are counted by game_id, never by week

### Known source-data limitations (not bugs)

- Some games are missing or partially captured in the cfbfastR feed (e.g.,
  several 2025 Ohio State games have ~40 of ~150 plays); disclosed in the
  app footer
- A few pick-sixes use a short text format with no passer name, so INTs can
  run 1 low for some QBs

### Stat logic changes require regenerating data files

If the calculations in `global.R` change, the cached `data/*.rds` files
still hold numbers from the old logic. Rerun `data-prep.R` and redeploy.
