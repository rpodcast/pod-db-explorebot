# load packages
library(dotenv)
library(shiny)
library(elmer)
library(bslib)
library(duckdb)
library(DBI)
library(dplyr)
library(shinychat)
library(reactable)
library(reactablefmtr)

# load scripts
source("R/query.R")
source("R/utils.R")

# initialize connection to duckdb database
conn <- dbConnect(
  duckdb(),
  #dbdir = "data-raw/podcastindex_feeds.duckdb",
  dbdir = "data-raw/podcastindex_feeds_small.duckdb",
  read_only = TRUE
)

# Close the database when the app stops
onStop(\() dbDisconnect(conn))

# import prompt from markdown file in root of directory
prompt_content <- readLines("prompt.md", warn = FALSE)
system_prompt_str <- paste(prompt_content, collapse = "\n")

# define user interface
ui <- page_sidebar(
  title = "Podcast Index Explorer",
  sidebar = sidebar(
    width = 400,
    style = "height: 100%",
    chat_ui("chat", height = "100%", fill = TRUE)
  ),
  useBusyIndicators(),

  # Header
  textOutput("show_title", container = h3),
  verbatimTextOutput("show_query") |>
    tagAppendAttributes(style = "max-height: 100px; overflow: auto;"),

  # Data table
  card(
    card_header("Podcast Index Data"),
    reactableOutput("table")
  )
)

# define server
server <- function(input, output, session) {
  # reactive values
  current_title <- reactiveVal(NULL)
  current_query <- reactiveVal("")

  # This object must always be passed as the `.ctx` argument to query(), so that
  # tool functions can access the context they need to do their jobs; in this
  # case, the database connection that query() needs.
  ctx <- list(conn = conn)

  # reactive data frame of podcast data
  podcast_data <- reactive({
    sql <- current_query()
    if (is.null(sql) || sql == "") {
      sql <- "SELECT * FROM podcasts;"
    }
    dbGetQuery(conn, sql)
  })

  # header outputs
  output$show_title <- renderText({
    current_title()
  })

  output$show_query <- renderText({
    current_query()
  })

  # data table
  output$table <- renderReactable({
    record_detail_table(podcast_data())
    # reactable(
    #   podcast_data(),
    #   pagination = FALSE,
    #   bordered = TRUE
    # )
  })

  # sidebot

  #' Update podcast database dashboard data
  #' 
  #' @param query DuckDB SQL query that must be a SELECT statement.
  #' @param title String with title to display at the top of the data dashboard. This string should summarize the intent of the SQL query.
  #' 
  #' @returns NULL, called for side effects
  update_dashboard <- function(query, title) {
    if (!is.null(query)) {
      current_query(query)
    }
    if (!is.null(title)) {
      current_title(title)
    }
  }

  #' Perform SQL query on the data, returning result as JSON format.
  #' 
  #' @param query DuckDB SQL query that must be a SELECT statement.
  #' 
  #' @return a JSON string of the data resulting from the query
  query <- function(query) {
    df <- dbGetQuery(conn, query)
    df |> jsonlite::toJSON(auto_unbox = TRUE)
  }

  # Preload the conversation with the system prompt. These are instructions for
  # the chat model, and must not be shown to the end user.
  chat <- elmer::chat_openai(system_prompt = system_prompt_str)

  # register update_dashboard function as tool
  # created with: elmer::create_tool_def(update_dashboard)
  chat$register_tool(
    ToolDef(
      fun = update_dashboard,
      name = "update_dashboard",
      description = "Updates the dashboard based on a query and title.",
      arguments = list(
        query = ToolArg(
          type = "string",
          description = "DuckDB SQL query that must be a SELECT statement.",
          required = TRUE
        ),
        title = ToolArg(
          type = "string",
          description = "The title for the dashboard update.",
          required = TRUE
        )
      )
    )
  )

  # register query function as tool
  # created with: elmer::create_tool_def(query)
  chat$register_tool(
    ToolDef(
      fun = query,
      name = "query",
      description = "Perform SQL query on the data, returning result as JSON format",
      arguments = list(
        query = ToolArg(
          type = "string",
          description = "DuckDB SQL query that must be a SELECT statement.",
          required = TRUE
        )
      )
    )
  )

  # add greeting (only for user, not for model itself)
  # chat_append(
  #   "chat",
  #   list(
  #     role = "assistant",
  #     content = "Hello! I hope you enjoy this chat."
  #   )
  # )

  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream)
  })
}

shinyApp(ui, server)
