# ui.R - User Interface for QB Weekly Stats Report

ui <- page_sidebar(
  theme = bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#001E44",
    secondary = "#6c757d",
    success = "#5a6d7a",
    info = "#8a9aa5"
  ),

  # Sidebar with filters
 sidebar = sidebar(
    width = 280,
    title = "Filters",

    # Season selector
    selectInput(
      inputId = "season",
      label = "Season",
      choices = c(2025, 2024, 2023, 2022, 2021),
      selected = 2025
    ),

    # Week selector
    selectInput(
      inputId = "week_filter",
      label = "Week(s)",
      choices = c(
        "All Weeks" = "all",
        setNames(1:15, paste("Week", 1:15)),
        "Postseason" = "post"
      ),
      selected = "all",
      multiple = TRUE
    ),

    # Conference filter: Power 4 always visible, Group of 5 folded away
    checkboxGroupInput(
      inputId = "conference_p4",
      label = "Conferences",
      choices = POWER_4_CONFERENCES,
      selected = POWER_4_CONFERENCES
    ),
    accordion(
      open = FALSE,
      class = "mb-3",
      accordion_panel(
        "Group of 5 / Independents",
        checkboxGroupInput(
          inputId = "conference_g5",
          label = NULL,
          choices = GROUP_5_CONFERENCES,
          selected = NULL
        )
      )
    ),

    hr(),

    # Minimum attempts filter (type or use arrows)
    numericInput(
      inputId = "min_attempts",
      label = "Minimum Attempts",
      value = 50,
      min = 1,
      max = 500,
      step = 5
    ),

    hr(),

    # Data refresh button
    actionButton(
      inputId = "refresh_data",
      label = "Refresh Data",
      icon = icon("sync"),
      class = "btn-primary w-100"
    ),

    hr(),

    # Info text
    div(
      class = "text-muted small",
      p("EPA = Expected Points Added"),
      p("Sorted by EPA/Play by default")
    )
  ),

  # Main content area
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        h4("College QB Report", class = "mb-0"),
        textOutput("subtitle", inline = TRUE)
      ),
      div(
        downloadButton("download_csv", "Download CSV", class = "btn-sm btn-outline-primary me-2"),
        downloadButton("download_xlsx", "Download Excel", class = "btn-sm btn-outline-secondary")
      )
    ),
    card_body(
      # Callout note: total QBs matching current filters
      div(
        class = "alert d-flex align-items-center gap-2",
        style = "background-color: #f3f4f6; border-left: 4px solid #001E44; color: #1f2937;",
        icon("users"),
        span(
          strong(textOutput("total_qbs", inline = TRUE)),
          " quarterbacks match the current filters"
        )
      ),

      # Main data table
      shinycssloaders::withSpinner(
        reactableOutput("qb_table"),
        type = 6,
        color = "#001E44"
      ),

      # Footer
      hr(),
      div(
        class = "text-muted small mt-3",
        p(class = "fw-bold mb-1", "Column definitions"),
        tags$ul(
          class = "list-unstyled mb-3",
          tags$li(strong("All Plays:"), " pass plays (including sacks) plus the QB's rushing attempts (kneel-downs excluded)."),
          tags$li(strong("Success Rate:"), " percentage of the QB's plays with positive EPA (Expected Points Added)."),
          tags$li(strong("Pass EPA:"), " total EPA on pass plays, including sacks."),
          tags$li(strong("Rush EPA:"), " total EPA on the QB's rushing attempts."),
          tags$li(strong("Total EPA:"), " Pass EPA plus Rush EPA."),
          tags$li(strong("EPA/All Plays:"), " Total EPA divided by All Plays - the key per-play efficiency metric.")
        )
      ),
      div(
        class = "text-center text-muted small",
        p(
          "Data sourced from ",
          tags$a(href = "https://cfbfastR.sportsdataverse.org/", target = "_blank", "cfbfastR"),
          " - Data not available for all games."
        ),
        p("Dashboard by @NittanyHoops")
      )
    )
  )
)
