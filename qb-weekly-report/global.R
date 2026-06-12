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

# Extract the text before the first keyword occurrence and clean it into a
# player name. Returns NA where no plausible name can be recovered.
extract_name_before <- function(play_text, keyword_pattern) {
  out <- rep(NA_character_, length(play_text))
  has_kw <- !is.na(play_text) & grepl(keyword_pattern, play_text)
  if (!any(has_kw)) return(out)
  prefix <- sub(paste0(keyword_pattern, ".*$"), "", play_text[has_kw])
  cleaned <- vapply(prefix, clean_display_name, character(1), USE.NAMES = FALSE)
  cleaned[!grepl("^[A-Z]", cleaned)] <- NA_character_
  out[has_kw] <- cleaned
  out
}

# cfbfastR fails to parse player names on many plays (in 2025, 37% of passing
# TD plays have no passer_player_name), which silently drops those plays from
# any stat grouped by player. The name is recoverable from the play text:
# "(13:35) Shotgun #11 C.Beck pass complete ... TOUCHDOWN" -> "C.Beck"
recover_passer_name <- function(play_text) {
  recovered <- extract_name_before(play_text, "\\s+pass\\b")
  missing <- is.na(recovered)
  recovered[missing] <- extract_name_before(play_text[missing], "\\s+sacked\\b")
  recovered
}

recover_rusher_name <- function(play_text) {
  recovered <- extract_name_before(play_text, "\\s+(rush|run)\\b")
  # Kneel-downs ("J. Sayin takes a knee") are excluded from rush stats
  recovered[grepl("takes a knee|kneel", play_text, ignore.case = TRUE)] <- NA_character_
  recovered
}

# TRUE for plays where a replay review nullified the touchdown. cfbfastR keeps
# pass_td = 1 from the original call, but the final ruling is the portion of
# the play text before "(Original Play: ...)".
td_nullified_by_review <- function(play_text) {
  reviewed <- !is.na(play_text) & grepl("(Original Play:", play_text, fixed = TRUE)
  final_ruling <- sub("\\(Original Play:.*$", "", play_text)
  reviewed & !grepl("TOUCHDOWN|for a TD|Yd pass", final_ruling, ignore.case = TRUE)
}

# Function to fetch and process QB stats (passing + rushing)
fetch_qb_stats <- function(season = CURRENT_SEASON, week = NULL) {

  # Fetch play-by-play data
  if (is.null(week)) {
    pbp_data <- cfbfastR::load_cfb_pbp(seasons = season)
  } else {
    pbp_data <- cfbfastR::load_cfb_pbp(seasons = season) |>
      filter(week == !!week)
  }

  # Deduplicate all plays by play ID
  pbp_data <- pbp_data |> distinct(id_play, .keep_all = TRUE)

  # Recover player names that cfbfastR failed to parse from the play text
  # (touchdown, sack, and pick-six play texts are the most affected)
  needs_passer <- pbp_data$pass == 1 &
    (is.na(pbp_data$passer_player_name) | pbp_data$passer_player_name == "")
  needs_passer[is.na(needs_passer)] <- FALSE
  pbp_data$passer_player_name[needs_passer] <-
    recover_passer_name(pbp_data$play_text[needs_passer])

  needs_rusher <- pbp_data$rush == 1 &
    (is.na(pbp_data$rusher_player_name) | pbp_data$rusher_player_name == "")
  needs_rusher[is.na(needs_rusher)] <- FALSE
  pbp_data$rusher_player_name[needs_rusher] <-
    recover_rusher_name(pbp_data$play_text[needs_rusher])

  # --- PASSING STATS (per game) ---
  # Note: postseason games are all coded as week 1 with season_type =
  # "postseason", so stats are grouped per game_id, not per week
  pass_stats <- pbp_data |>
    filter(
      pass == 1,
      !is.na(passer_player_name),
      passer_player_name != ""
    ) |>
    mutate(
      # pass_td stays 1 on TDs overturned by replay review and is also set on
      # a handful of interception plays; both must be excluded
      is_pass_td = pass_td == 1 &
        coalesce(int, 0) != 1 &
        !td_nullified_by_review(play_text)
    ) |>
    group_by(
      player = passer_player_name,
      team = pos_team,
      conference = offense_conference,
      season_type,
      week,
      game_id
    ) |>
    summarize(
      pass_plays = n(),
      successful_pass_plays = sum(EPA > 0, na.rm = TRUE),
      attempts = sum(sack != 1, na.rm = TRUE),
      completions = sum(completion, na.rm = TRUE),
      # Completions only: on interceptions and fumbles, yards_gained holds
      # the defender's return yardage, not passing yards
      passing_yards = sum(yards_gained[completion == 1], na.rm = TRUE),
      touchdowns = sum(is_pass_td, na.rm = TRUE),
      interceptions = sum(int, na.rm = TRUE),
      pass_epa = sum(EPA, na.rm = TRUE),
      .groups = "drop"
    )

  # Build set of (name_key, team) for all passers to identify QBs
  pass_stats <- pass_stats |>
    mutate(name_key = vapply(player, normalize_player_name, character(1), USE.NAMES = FALSE))
  qb_keys <- pass_stats |>
    distinct(name_key, team)

  # --- RUSHING STATS (only for players who are also passers = QBs) ---
  rush_data <- pbp_data |>
    filter(
      rush == 1,
      !is.na(rusher_player_name),
      rusher_player_name != "",
      # Kneel-downs are clock kills, not rushing performance
      !grepl("takes a knee|kneel", play_text, ignore.case = TRUE)
    ) |>
    mutate(
      player = rusher_player_name,
      name_key = vapply(rusher_player_name, normalize_player_name, character(1), USE.NAMES = FALSE)
    ) |>
    inner_join(qb_keys, by = c("name_key", "pos_team" = "team"))

  rush_stats <- rush_data |>
    group_by(
      name_key,
      team = pos_team,
      game_id
    ) |>
    summarize(
      rush_plays = n(),
      successful_rush_plays = sum(EPA > 0, na.rm = TRUE),
      rush_epa = sum(EPA, na.rm = TRUE),
      .groups = "drop"
    )

  # --- COMBINE PASSING AND RUSHING (per game, so postseason games
  # don't collide with regular-season games sharing a week number) ---
  qb_stats <- pass_stats |>
    left_join(
      rush_stats,
      by = c("name_key", "team", "game_id")
    ) |>
    mutate(
      rush_plays = coalesce(rush_plays, 0L),
      successful_rush_plays = coalesce(successful_rush_plays, 0L),
      rush_epa = coalesce(rush_epa, 0)
    ) |>
    mutate(
      all_plays = pass_plays + rush_plays,
      successful_plays = successful_pass_plays + successful_rush_plays,
      total_epa = pass_epa + rush_epa,
      comp_pct = round(completions / attempts * 100, 1),
      success_rate = round(successful_plays / all_plays * 100, 1),
      epa_per_play = round(total_epa / all_plays, 3)
    ) |>
    select(-name_key) |>
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
      # Count actual games: all postseason games share week = 1, so
      # counting weeks would undercount QBs with playoff appearances
      games = n_distinct(game_id),
      pass_plays = sum(pass_plays),
      rush_plays = sum(rush_plays),
      successful_plays = sum(successful_plays),
      attempts = sum(attempts),
      completions = sum(completions),
      passing_yards = sum(passing_yards),
      touchdowns = sum(touchdowns),
      interceptions = sum(interceptions),
      pass_epa = sum(pass_epa),
      rush_epa = sum(rush_epa),
      .groups = "drop"
    ) |>
    mutate(
      all_plays = pass_plays + rush_plays,
      total_epa = pass_epa + rush_epa,
      comp_pct = round(completions / attempts * 100, 1),
      success_rate = round(successful_plays / all_plays * 100, 1),
      epa_per_play = round(total_epa / all_plays, 3)
    ) |>
    filter(attempts >= min_attempts) |>
    # Join logos on a normalized team key so accents/punctuation don't break matches
    mutate(team_key = normalize_team_name(team)) |>
    left_join(TEAM_LOGOS, by = "team_key") |>
    select(
      logo, player, team, conference, games,
      completions, attempts, comp_pct,
      passing_yards, touchdowns, interceptions,
      all_plays, success_rate, pass_epa, rush_epa, total_epa, epa_per_play
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
      all_plays = colDef(
        name = "All Plays",
        minWidth = 80,
        align = "center"
      ),
      success_rate = colDef(
        name = "Success%",
        minWidth = 80,
        align = "center",
        format = colFormat(suffix = "%")
      ),
      pass_epa = colDef(
        name = "Pass EPA",
        minWidth = 85,
        align = "center",
        format = colFormat(digits = 1),
        style = function(value) {
          color <- if (value > 0) "#001E44" else if (value < 0) "#6b7280" else "#9ca3af"
          list(color = color, fontWeight = "bold")
        }
      ),
      rush_epa = colDef(
        name = "Rush EPA",
        minWidth = 85,
        align = "center",
        format = colFormat(digits = 1),
        style = function(value) {
          color <- if (value > 0) "#001E44" else if (value < 0) "#6b7280" else "#9ca3af"
          list(color = color, fontWeight = "bold")
        }
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
        name = "EPA/All Plays",
        minWidth = 105,
        align = "center",
        style = epa_play_style
      )
    )
  )
}
