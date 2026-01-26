# global.R - Shared data and functions for QB Weekly Stats Report
# This file loads packages and prepares data used by both ui.R and server.R

# Load required packages
library(shiny)
library(cfbfastR)
library(dplyr)
library(reactable)
library(reactablefmtr)
library(bslib)
library(shinycssloaders)

# Power 4 conferences (Big Ten, SEC, Big 12, ACC)
POWER_4_CONFERENCES <- c("Big Ten", "SEC", "Big 12", "ACC")

# All FBS conferences for filtering
FBS_CONFERENCES <- c(

"ACC", "Big 12", "Big Ten", "SEC",  # Power 4
"American Athletic", "Conference USA", "Mid-American",
"Mountain West", "Sun Belt", "FBS Independents"  # Group of 5
)

# Current season (update as needed)
CURRENT_SEASON <- 2024

# Function to fetch and process QB stats
fetch_qb_stats <- function(season = CURRENT_SEASON, week = NULL) {

  # Fetch play-by-play data
  if (is.null(week)) {
    # Get all weeks up to current
    pbp_data <- cfbfastR::load_cfb_pbp(seasons = season)
  } else {
    pbp_data <- cfbfastR::load_cfb_pbp(seasons = season) |>
      filter(week == !!week)
  }

  # Filter to passing plays and calculate QB stats
  qb_stats <- pbp_data |>
    filter(
      pass == 1,
      !is.na(passer_player_name),
      passer_player_name != ""
    ) |>
    group_by(
      player = passer_player_name,
      team = pos_team,
      conference = offense_conference,
      week
    ) |>
    summarize(
      attempts = n(),
      completions = sum(completion, na.rm = TRUE),
      passing_yards = sum(yards_gained, na.rm = TRUE),
      touchdowns = sum(pass_td, na.rm = TRUE),
      interceptions = sum(int, na.rm = TRUE),
      total_epa = sum(EPA, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      comp_pct = round(completions / attempts * 100, 1),
      yards_per_att = round(passing_yards / attempts, 1),
      epa_per_play = round(total_epa / attempts, 3)
    ) |>
    arrange(desc(epa_per_play))

  return(qb_stats)
}

# Function to aggregate stats across multiple weeks
aggregate_qb_stats <- function(qb_data, min_attempts = 1) {
  qb_data |>
    group_by(player, team, conference) |>
    summarize(
      games = n_distinct(week),
      attempts = sum(attempts),
      completions = sum(completions),
      passing_yards = sum(passing_yards),
      touchdowns = sum(touchdowns),
      interceptions = sum(interceptions),
      total_epa = sum(total_epa),
      .groups = "drop"
    ) |>
    mutate(
      comp_pct = round(completions / attempts * 100, 1),
      yards_per_att = round(passing_yards / attempts, 1),
      epa_per_play = round(total_epa / attempts, 3)
    ) |>
    filter(attempts >= min_attempts) |>
    arrange(desc(epa_per_play))
}

# Create styled reactable for QB stats
create_qb_table <- function(data) {
  reactable(
    data,
    searchable = TRUE,
    filterable = TRUE,
    highlight = TRUE,
    bordered = TRUE,
    striped = TRUE,
    compact = TRUE,
    defaultPageSize = 25,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 25, 50, 100),
    defaultSorted = list(epa_per_play = "desc"),
    theme = reactableTheme(
      borderColor = "#dfe2e5",
      stripedColor = "#f6f8fa",
      highlightColor = "#f0f5ff",
      cellPadding = "8px 12px",
      style = list(fontFamily = "-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif")
    ),
    columns = list(
      player = colDef(
        name = "Player",
        minWidth = 150,
        sticky = "left",
        style = list(fontWeight = "bold")
      ),
      team = colDef(
        name = "Team",
        minWidth = 120
      ),
      conference = colDef(
        name = "Conf",
        minWidth = 100
      ),
      games = colDef(
        name = "G",
        minWidth = 50,
        align = "center"
      ),
      attempts = colDef(
        name = "ATT",
        minWidth = 60,
        align = "center"
      ),
      completions = colDef(
        name = "CMP",
        minWidth = 60,
        align = "center"
      ),
      comp_pct = colDef(
        name = "CMP%",
        minWidth = 70,
        align = "center",
        format = colFormat(suffix = "%")
      ),
      passing_yards = colDef(
        name = "YDS",
        minWidth = 70,
        align = "center",
        format = colFormat(separators = TRUE)
      ),
      yards_per_att = colDef(
        name = "Y/A",
        minWidth = 60,
        align = "center"
      ),
      touchdowns = colDef(
        name = "TD",
        minWidth = 50,
        align = "center",
        style = list(color = "#28a745", fontWeight = "bold")
      ),
      interceptions = colDef(
        name = "INT",
        minWidth = 50,
        align = "center",
        style = list(color = "#dc3545")
      ),
      total_epa = colDef(
        name = "Total EPA",
        minWidth = 90,
        align = "center",
        format = colFormat(digits = 1),
        style = function(value) {
          color <- if (value > 0) "#28a745" else if (value < 0) "#dc3545" else "#6c757d"
          list(color = color, fontWeight = "bold")
        }
      ),
      epa_per_play = colDef(
        name = "EPA/Play",
        minWidth = 90,
        align = "center",
        style = function(value) {
          color <- if (value > 0) "#28a745" else if (value < 0) "#dc3545" else "#6c757d"
          list(color = color, fontWeight = "bold")
        }
      )
    )
  )
}
