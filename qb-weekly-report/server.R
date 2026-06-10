# server.R - Server logic for QB Weekly Stats Report

server <- function(input, output, session) {

  # Reactive value to store raw data
  raw_data <- reactiveVal(NULL)

  # Load data on startup and when refresh is clicked
  observeEvent(c(input$refresh_data, input$season), {
    # Show notification
    showNotification("Loading data...", type = "message", duration = NULL, id = "loading")

    tryCatch({
      data <- fetch_qb_stats(season = as.numeric(input$season))
      raw_data(data)
      removeNotification("loading")
      showNotification("Data loaded successfully!", type = "message", duration = 3)
    }, error = function(e) {
      removeNotification("loading")
      showNotification(paste("Error loading data:", e$message), type = "error", duration = 5)
    })
  }, ignoreNULL = FALSE)

  # Quick select Power 4 conferences
  observeEvent(input$select_power4, {
    updateCheckboxGroupInput(session, "conference_filter", selected = POWER_4_CONFERENCES)
  })

  # Quick select all conferences
  observeEvent(input$select_all_conf, {
    updateCheckboxGroupInput(session, "conference_filter", selected = FBS_CONFERENCES)
  })

  # Filtered and aggregated data
  filtered_data <- reactive({
    req(raw_data())

    data <- raw_data()

    # Filter by week if specific weeks selected
    if (!is.null(input$week_filter) && !"all" %in% input$week_filter) {
      selected_weeks <- as.numeric(input$week_filter)
      data <- data |> filter(week %in% selected_weeks)
    }

    # Filter by conference
    if (!is.null(input$conference_filter)) {
      data <- data |> filter(conference %in% input$conference_filter)
    }

    # Aggregate across weeks
    aggregated <- aggregate_qb_stats(data, min_attempts = input$min_attempts)

    # Filter by minimum games
    aggregated <- aggregated |> filter(games >= input$min_games)

    return(aggregated)
  })

  # Render subtitle with filter info
  output$subtitle <- renderText({
    req(filtered_data())
    n_qbs <- nrow(filtered_data())
    conf_text <- if (length(input$conference_filter) == length(FBS_CONFERENCES)) {
      "All FBS"
    } else if (setequal(input$conference_filter, POWER_4_CONFERENCES)) {
      "Power 4"
    } else {
      paste(length(input$conference_filter), "conferences")
    }
    paste0(" | ", input$season, " Season | ", conf_text, " | Min ", input$min_attempts, " attempts")
  })

  # Render total QB count for callout note
  output$total_qbs <- renderText({
    req(filtered_data())
    nrow(filtered_data())
  })

  # Render main data table
  output$qb_table <- renderReactable({
    req(filtered_data())
    create_qb_table(filtered_data())
  })

  # Download handlers
  output$download_csv <- downloadHandler(
    filename = function() {
      paste0("qb_stats_", input$season, "_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(select(filtered_data(), -logo), file, row.names = FALSE)
    }
  )

  output$download_xlsx <- downloadHandler(
    filename = function() {
      paste0("qb_stats_", input$season, "_", Sys.Date(), ".xlsx")
    },
    content = function(file) {
      export_data <- select(filtered_data(), -logo)
      if (requireNamespace("writexl", quietly = TRUE)) {
        writexl::write_xlsx(export_data, file)
      } else {
        # Fallback to CSV if writexl not available
        write.csv(export_data, file, row.names = FALSE)
        showNotification("writexl package not installed. Downloaded as CSV instead.", type = "warning")
      }
    }
  )
}
