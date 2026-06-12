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

  # Conferences checked across both the Power 4 and Group of 5 inputs
  selected_conferences <- reactive({
    c(input$conference_p4, input$conference_g5)
  })

  # Filtered and aggregated data
  filtered_data <- reactive({
    req(raw_data())

    data <- raw_data()

    # Filter by week if specific weeks selected. Postseason games are all
    # coded as week 1 in the data, so they get their own filter value.
    if (!is.null(input$week_filter) && !"all" %in% input$week_filter) {
      keep_postseason <- "post" %in% input$week_filter
      selected_weeks <- suppressWarnings(as.numeric(setdiff(input$week_filter, "post")))
      data <- data |> filter(
        (season_type == "regular" & week %in% selected_weeks) |
          (keep_postseason & season_type == "postseason")
      )
    }

    # Filter by conference (no boxes checked = show all)
    confs <- selected_conferences()
    if (length(confs) > 0) {
      data <- data |> filter(conference %in% confs)
    }

    # Aggregate across weeks
    aggregated <- aggregate_qb_stats(data, min_attempts = input$min_attempts)

    return(aggregated)
  })

  # Render subtitle with filter info
  output$subtitle <- renderText({
    req(filtered_data())
    n_qbs <- nrow(filtered_data())
    confs <- selected_conferences()
    conf_text <- if (setequal(confs, FBS_CONFERENCES)) {
      "All FBS"
    } else if (setequal(confs, POWER_4_CONFERENCES)) {
      "Power 4"
    } else {
      paste(length(confs), "conferences")
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
