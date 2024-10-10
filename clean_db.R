# load packages
library(DBI)
library(RSQLite)
library(dplyr)
library(dbplyr)
library(tidyr)
library(anytime)
library(duckdb)

source("R/utils.R")

# unpack and import database
archive::archive_extract("data-raw/podcastindex_feeds.db.tgz", dir = "data-raw")

# initialize database connection
con <- DBI::dbConnect(
  RSQLite::SQLite(),
  "data-raw/podcastindex_feeds.db"
)

# database cleaning: Create itunesIdText as text variable
itunes_add_q <- dbSendStatement(con, "ALTER TABLE podcasts ADD  COLUMN itunesIdText text")
dbClearResult(itunes_add_q)
itunes_update_q <- dbSendStatement(con, "UPDATE podcasts SET itunesIdText = CAST(itunesId AS text)")
dbClearResult(itunes_update_q)

podcasts_db <- tbl(con, "podcasts")

# remove records with missing chash value
podcasts_filtered_db <- podcasts_db |>
  filter(chash != "")

# perform data cleaning
# perform data cleaning
podcasts_clean_df<- podcasts_db |>
  collect() |>
  tibble::as_tibble() |>
  mutate(newestItemPubdate = na_if(newestItemPubdate, 0),
         oldestItemPubdate = na_if(oldestItemPubdate, 0),
         title = na_if(title, ""),
         lastUpdate = na_if(lastUpdate, 0),
         createdOn = na_if(createdOn, 0),
         newestEnclosureDuration = na_if(newestEnclosureDuration, 0)) |>
  mutate(lastUpdate_p = anytime(lastUpdate),
         newestItemPubdate_p = anytime(newestItemPubdate),
         oldestItemPubdate_p = anytime(oldestItemPubdate),
         createdOn_p = anytime(createdOn)) |>
  mutate(pub_timespan_days = lubridate::interval(oldestItemPubdate_p, newestItemPubdate_p) / lubridate::ddays(1)) |>
  mutate(created_timespan_days = lubridate::interval(createdOn_p, Sys.time()) / lubridate::ddays(1))

# load data set to duckdb
conn2 <- DBI::dbConnect(
  duckdb::duckdb(),
  "data-raw/podcastindex_feeds.duckdb"
)

DBI::dbWriteTable(conn2, "podcasts", podcasts_clean_df)

# experiment with schema function
schema <- df_to_schema(
  podcasts_clean_df,
  "podcasts",
  categorical_threshold = 10
)
