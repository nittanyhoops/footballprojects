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
library(htmltools)

# Power 4 conferences (Big Ten, SEC, Big 12, ACC)
POWER_4_CONFERENCES <- c("Big Ten", "SEC", "Big 12", "ACC")

# All FBS conferences for filtering
FBS_CONFERENCES <- c(

"ACC", "Big 12", "Big Ten", "SEC",  # Power 4
"American Athletic", "Conference USA", "Mid-American",
"Mountain West", "Sun Belt", "FBS Independents"  # Group of 5
)

# Current season (update as needed)
CURRENT_SEASON <- 2025

# Normalize team names for joining across data sources
# (lowercase, strip accents and punctuation: "San José State" -> "sanjosestate")
normalize_team_name <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  gsub("[^a-z0-9]", "", tolower(x))
}

# Team logos from ESPN's public teams API (no API key required).
# Logo URLs follow the ESPN CDN pattern keyed by team id.
TEAM_LOGOS <- tryCatch({
  raw <- jsonlite::fromJSON(
    "https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams?limit=1000"
  )
  teams_df <- raw$sports$leagues[[1]]$teams[[1]]$team
  data.frame(
    team_key = normalize_team_name(teams_df$location),
    logo = paste0("https://a.espncdn.com/i/teamlogos/ncaa/500/", teams_df$id, ".png"),
    stringsAsFactors = FALSE
  ) |>
    dplyr::distinct(team_key, .keep_all = TRUE)
}, error = function(e) {
  message("Could not load team logos: ", e$message)
  data.frame(team_key = character(), logo = character(), stringsAsFactors = FALSE)
})

# Strip play-formation prefixes and jersey numbers from a player name.
# Real PBP values look like "#10 J.Sayin", ") No Huddle-Shotgun #2 D.Pavia",
# "04:21) No Huddle #15 T.Simpson", or a clean "Julian Sayin".
clean_display_name <- function(name) {
  cleaned <- name
  if (grepl("#\\s*\\d+", cleaned)) {
    # Player name is whatever follows the last jersey-number marker
    cleaned <- sub(".*#\\s*\\d+\\s*", "", cleaned)
  } else {
    # No jersey number: strip leading non-letter junk (") ", ", ", timestamps)
    cleaned <- sub("^[^A-Za-z]+", "", cleaned)
    # Then strip formation prefixes (hyphen- or space-separated)
    cleaned <- sub(
      "^(No Huddle[- ]Shotgun|No Huddle|Shotgun|Pistol|Under Center|Wildcat|I-Form|I Form|Singleback|Single Back|Jumbo|Goal Line|Empty|Ace|Spread)[- ]*",
      "", cleaned, ignore.case = TRUE
    )
  }
  trimws(cleaned)
}

# Build a grouping key of "first initial + last name" so that
# "Julian Sayin", "#10 J.Sayin", and "Shotgun #10 J.Sayin" all become "j_sayin"
normalize_player_name <- function(name) {
  cleaned <- clean_display_name(name)
  # Drop generational suffixes so "R.Moore III" matches "Raymond Moore III"
  cleaned <- gsub("\\s+(Jr\\.?|Sr\\.?|II|III|IV|V)\\.?$", "", cleaned, ignore.case = TRUE)
  if (cleaned == "") return(tolower(name))
  first_initial <- tolower(substr(cleaned, 1, 1))
  # Last name = everything after the final space or period
  # ("Julian Sayin", "J.Sayin", and "D. Pavia" all reduce to their last name)
  last_name <- tolower(sub(".*[ .]", "", cleaned))
  paste(first_initial, last_name, sep = "_")
}

# Pick the best display name from duplicate variants: clean each one,
# then prefer the longest (full "Julian Sayin" over abbreviated "J.Sayin")
get_canonical_name <- function(names) {
  cleaned <- vapply(names, clean_display_name, character(1), USE.NAMES = FALSE)
  cleaned[which.max(nchar(cleaned))]
}

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

  # Filter to passing plays and deduplicate by play ID
  # (raw data sometimes has duplicate rows for the same play)
  qb_stats <- pbp_data |>
    filter(
      pass == 1,
      !is.na(passer_player_name),
      passer_player_name != ""
    ) |>
    distinct(id_play, .keep_all = TRUE) |>
    group_by(
      player = passer_player_name,
      team = pos_team,
      conference = offense_conference,
      week
    ) |>
    summarize(
      # A sack is a pass play but not a passing attempt
      plays = n(),
      attempts = sum(sack != 1, na.rm = TRUE),
      completions = sum(completion, na.rm = TRUE),
      passing_yards = sum(yards_gained[sack != 1], na.rm = TRUE),
      touchdowns = sum(pass_td, na.rm = TRUE),
      interceptions = sum(int, na.rm = TRUE),
      total_epa = sum(EPA, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      comp_pct = round(completions / attempts * 100, 1),
      yards_per_att = round(passing_yards / attempts, 1),
      epa_per_play = round(total_epa / plays, 3)
    ) |>
    arrange(desc(epa_per_play))

  return(qb_stats)
}

# Function to aggregate stats across multiple weeks
aggregate_qb_stats <- function(qb_data, min_attempts = 1) {
  qb_data |>
    # Add normalized name key for grouping (first initial + last name)
    mutate(
      name_key = vapply(player, normalize_player_name, character(1), USE.NAMES = FALSE)
    ) |>
    # Group by normalized name + team + conference to combine duplicates
    # like "Julian Sayin" and "Shotgun #10 J.Sayin"
    group_by(name_key, team, conference) |>
    summarize(
      # Pick the cleaned full-name variant as the display name
      player = get_canonical_name(unique(player)),
      games = n_distinct(week),
      plays = sum(plays),
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
      epa_per_play = round(total_epa / plays, 3)
    ) |>
    filter(attempts >= min_attempts) |>
    # Join logos on a normalized team key so accents/punctuation don't break matches
    mutate(team_key = normalize_team_name(team)) |>
    left_join(TEAM_LOGOS, by = "team_key") |>
    select(
      logo, player, team, conference, games,
      completions, attempts, comp_pct,
      passing_yards, yards_per_att, touchdowns, interceptions,
      plays, total_epa, epa_per_play
    ) |>
    arrange(desc(epa_per_play))
}

# Create styled reactable for QB stats
create_qb_table <- function(data) {

  # Diverging color scale for EPA/Play: low = light red, mid = white, high = light green
  epa_play_range <- range(data$epa_per_play, na.rm = TRUE)
  epa_play_ramp <- grDevices::colorRamp(c("#f8b4b4", "#ffffff", "#b7e4c7"))
  epa_play_style <- function(value) {
    if (is.na(value)) return(list())
    norm <- if (diff(epa_play_range) == 0) {
      0.5
    } else {
      (value - epa_play_range[1]) / diff(epa_play_range)
    }
    rgb_vals <- epa_play_ramp(norm)
    list(
      background = grDevices::rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3], maxColorValue = 255),
      color = "#1f2937",
      fontWeight = "bold"
    )
  }

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
      borderColor = "#d1d5db",
      stripedColor = "#f3f4f6",
      highlightColor = "#e5e7eb",
      headerStyle = list(
        backgroundColor = "#001E44",
        color = "#ffffff",
        fontWeight = "bold"
      ),
      cellPadding = "8px 12px",
      style = list(fontFamily = "-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif")
    ),
    columns = list(
      logo = colDef(
        name = "",
        minWidth = 50,
        sticky = "left",
        sortable = FALSE,
        filterable = FALSE,
        align = "center",
        cell = function(value) {
          if (is.na(value) || value == "") return("")
          htmltools::img(src = value, height = "24px", alt = "")
        }
      ),
      player = colDef(
        name = "Player",
        minWidth = 150,
        sticky = "left",
        style = list(fontWeight = "bold", whiteSpace = "nowrap")
      ),
      team = colDef(
        name = "Team",
        minWidth = 120,
        style = list(whiteSpace = "nowrap")
      ),
      conference = colDef(
        name = "Conf",
        minWidth = 100,
        style = list(whiteSpace = "nowrap")
      ),
      games = colDef(
        name = "G",
        minWidth = 50,
        align = "center"
      ),
      completions = colDef(
        name = "CMP",
        minWidth = 60,
        align = "center"
      ),
      attempts = colDef(
        name = "ATT",
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
        style = list(color = "#001E44", fontWeight = "bold")
      ),
      interceptions = colDef(
        name = "INT",
        minWidth = 50,
        align = "center",
        style = list(color = "#6b7280")
      ),
      plays = colDef(
        name = "Plays",
        minWidth = 65,
        align = "center"
      ),
      total_epa = colDef(
        name = "Total EPA",
        minWidth = 90,
        align = "center",
        format = colFormat(digits = 1),
        style = function(value) {
          color <- if (value > 0) "#001E44" else if (value < 0) "#6b7280" else "#9ca3af"
          list(color = color, fontWeight = "bold")
        }
      ),
      epa_per_play = colDef(
        name = "EPA/Play",
        minWidth = 90,
        align = "center",
        style = epa_play_style
      )
    )
  )
}
