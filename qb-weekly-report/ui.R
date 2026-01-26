# ui.R - User Interface for QB Weekly Stats Report

ui <- page_sidebar(
  title = "College QB Weekly Stats Report",
  theme = bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#2c3e50",
    "navbar-bg" = "#2c3e50"
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

    # Minimum attempts filter
    sliderInput(
      inputId = "min_attempts",
      label = "Minimum Attempts",
      min = 1,
      max = 200,
      value = 50,
      step = 5
    ),

    # Minimum games filter
    sliderInput(
      inputId = "min_games",
      label = "Minimum Games",
      min = 1,
      max = 15,
      value = 1,
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
      p("Data sourced from cfbfastR"),
      p("EPA = Expected Points Added"),
      p("Sorted by EPA/Play by default")
    )
  ),

  # Main content area
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        h4("Quarterback Rankings", class = "mb-0"),
        textOutput("subtitle", inline = TRUE)
      ),
      div(
        downloadButton("download_csv", "Download CSV", class = "btn-sm btn-outline-primary me-2"),
        downloadButton("download_xlsx", "Download Excel", class = "btn-sm btn-outline-success")
      )
    ),
    card_body(
      # Summary stats
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        value_box(
          title = "Total QBs",
          value = textOutput("total_qbs"),
          showcase = icon("users"),
          theme = "primary"
        ),
        value_box(
          title = "Avg EPA/Play",
          value = textOutput("avg_epa"),
          showcase = icon("chart-line"),
          theme = "success"
        ),
        value_box(
          title = "Total TDs",
          value = textOutput("total_tds"),
          showcase = icon("football"),
          theme = "info"
        ),
        value_box(
          title = "Conferences",
          value = textOutput("num_conferences"),
          showcase = icon("building-columns"),
          theme = "secondary"
        )
      ),

      # Main data table
      hr(),
      shinycssloaders::withSpinner(
        reactableOutput("qb_table"),
        type = 6,
        color = "#2c3e50"
      )
    )
  )
)
