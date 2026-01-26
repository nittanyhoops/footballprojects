# app.R - Main entry point for QB Weekly Stats Report Shiny App
#
# Run this app with: shiny::runApp("qb-weekly-report")
# Or click "Run App" in RStudio

# Source the component files
source("global.R")
source("ui.R")
source("server.R")

# Run the application
shinyApp(ui = ui, server = server)
