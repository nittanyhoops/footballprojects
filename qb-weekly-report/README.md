# College QB Weekly Stats Report

An interactive Shiny dashboard for analyzing college football quarterback performance using EPA (Expected Points Added) and traditional stats.

## Features

- **Dynamic Filtering**: Filter by conference, week, minimum attempts, and minimum games
- **Advanced Stats**: EPA/Play, Total EPA alongside traditional passing stats
- **Power 4 Focus**: Quick toggle for Power 4 conferences (Big Ten, SEC, Big 12, ACC)
- **Data Export**: Download filtered data as CSV or Excel
- **Responsive Design**: Modern UI built with bslib and reactable

## Quick Start

### Prerequisites

Install required R packages:

```r
install.packages(c(
  "shiny",
  "cfbfastR",
  "dplyr",
  "reactable",
  "reactablefmtr",
  "bslib",
  "shinycssloaders",
  "writexl"  # Optional, for Excel export
))
```

### Running the App

```r
# From R/RStudio
shiny::runApp("qb-weekly-report")

# Or set working directory and run
setwd("path/to/qb-weekly-report")
shiny::runApp()
```

## Stats Included

| Stat | Description |
|------|-------------|
| G | Games played |
| ATT | Pass attempts |
| CMP | Completions |
| CMP% | Completion percentage |
| YDS | Passing yards |
| Y/A | Yards per attempt |
| TD | Passing touchdowns |
| INT | Interceptions |
| Total EPA | Cumulative Expected Points Added |
| EPA/Play | EPA per pass attempt (key efficiency metric) |

## Understanding EPA

**EPA (Expected Points Added)** measures how much a play changes the expected points for the offense. A positive EPA means the play increased expected points, while negative EPA means it decreased them.

**EPA/Play** is the average EPA per pass attempt - the key metric for evaluating QB efficiency. Higher values indicate more efficient passers who consistently create value.

## Data Source

Data is sourced from [cfbfastR](https://cfbfastR.sportsdataverse.org/), which provides play-by-play data for college football including EPA calculations.

## Deployment Options

### Local
Run directly from RStudio or R console.

### shinyapps.io
1. Create account at [shinyapps.io](https://www.shinyapps.io/)
2. Install rsconnect: `install.packages("rsconnect")`
3. Deploy: `rsconnect::deployApp("qb-weekly-report")`

### Shiny Server
Deploy on your own Shiny Server instance.

## Alternative: Static HTML Report

For a simpler deployment without a Shiny server, see `static-report/qb_report.qmd` - a Quarto document that generates a static HTML file with client-side filtering using reactable.

## File Structure

```
qb-weekly-report/
├── app.R           # Main app entry point
├── global.R        # Shared data, functions, constants
├── ui.R            # User interface definition
├── server.R        # Server logic and reactivity
└── README.md       # This file
```

## License

MIT
