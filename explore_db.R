library(DBI)
library(duckdb)
library(dbplyr)
library(dplyr)

# load data set to duckdb
conn <- DBI::dbConnect(
  duckdb::duckdb(),
  "data-raw/podcastindex_feeds.duckdb"
)

conn_smaller <- DBI::dbConnect(
  duckdb::duckdb(),
  "data-raw/podcastindex_feeds_small.duckdb"
)

podcasts_db <- tbl(conn, "podcasts")

# create a smaller version of the database for purposes of the dem
podcasts_small_df <- podcasts_db |>
  slice_sample(n = 200) |>
  collect()

DBI::dbWriteTable(conn_smaller, "podcasts", podcasts_small_df)

podcasts_db |>
  filter(id %in% c(1:10)) |>
  collect() |>
  View()