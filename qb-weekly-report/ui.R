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
      choices = c("All Weeks" = "all", setNames(1:15, paste("Week", 1:15))),
      selected = "all",
      multiple = TRUE
    ),

    # Conference filter
    checkboxGroupInput(
      inputId = "conference_filter",
      label = "Conferences",
      choices = FBS_CONFERENCES,
      selected = POWER_4_CONFERENCES
    ),

    # Quick select buttons for conferences
    div(
      class = "d-flex gap-2 mb-3",
      actionButton("select_power4", "Power 4", class = "btn-sm btn-outline-primary"),
      actionButton("select_all_conf", "All FBS", class = "btn-sm btn-outline-secondary")
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

    # Minimum games filter (type or use arrows)
    numericInput(
      inputId = "min_games",
      label = "Minimum Games",
      value = 1,
      min = 1,
      max = 15,
      step = 1
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
        class = "text-center text-muted small mt-3",
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
