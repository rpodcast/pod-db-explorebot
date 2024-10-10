df_to_schema <- function(df, name, categorical_threshold) {
  schema <- c(paste("Table:", name), "Columns:")

  column_info <- lapply(names(df), function(column) {
    # Map R classes to SQL-like types
    sql_type <- if (is.integer(df[[column]])) {
      "INTEGER"
    } else if (is.numeric(df[[column]])) {
      "FLOAT"
    } else if (is.logical(df[[column]])) {
      "BOOLEAN"
    } else if (inherits(df[[column]], "POSIXt")) {
      "DATETIME"
    } else {
      "TEXT"
    }

    info <- paste0("- ", column, " (", sql_type, ")")

    # For TEXT columns, check if they're categorical
    if (sql_type == "TEXT") {
      unique_values <- length(unique(df[[column]]))
      if (unique_values <= categorical_threshold) {
        categories <- unique(df[[column]])
        categories_str <- paste0("'", categories, "'", collapse = ", ")
        info <- c(info, paste0("  Categorical values: ", categories_str))
      }
    }

    return(info)
  })

  schema <- c(schema, unlist(column_info))
  return(paste(schema, collapse = "\n"))
}

# create concatenated list of categories
gen_categories_df <- function(data) {
  data <- dplyr::select(data, id, starts_with("category"))
  data_long <- tidyr::pivot_longer(
    data,
    cols = starts_with("category"),
    names_to = "category_index",
    values_to = "category_value"
  ) |>
    dplyr::filter(category_value != "")

  data_sum <- data_long |>
    group_by(id) |>
    summarize(category = glue::glue_collapse(category_value, ", ", last = " and ")) |>
    ungroup()
  return(data_sum)
}

clean_podcast_df <- function(data, dev_mode = FALSE) {
  df <- data |>
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

  # obtain categories df
  cat_df <- gen_categories_df(df)

  # preprocessing
  df <- df |>
    dplyr::select(!starts_with("category")) |>
    left_join(cat_df, by = "id") |>
    # dplyr::mutate(
    #   episodeCount_colors = dplyr::case_when(
    #     episodeCount >= 0 ~ 'darkgreen',
    #     TRUE ~ 'orange'
    #   )
    # ) |>
    dplyr::mutate(
      imageUrl = dplyr::case_when(
        imageUrl == "" ~ "https://podcastindex.org/images/no-cover-art.png",
        stringr::str_length(imageUrl) < 29 ~ "https://podcastindex.org/images/no-cover-art.png",
        !grepl("https|http", imageUrl) ~ "https://podcastindex.org/images/no-cover-art.png",
        .default = imageUrl
      )
    ) |>
    dplyr::select(-newestItemPubdate, -oldestItemPubdate, -createdOn, -lastUpdate) |>
    dplyr::select(imageUrl, podcastGuid, title, url, lastUpdate_p, newestEnclosureDuration, newestItemPubdate_p, oldestItemPubdate_p, episodeCount, everything())

  if (dev_mode) df <- dplyr::slice(df, 1:100)

  return(df)
}

process_extract_df <- function(extract_df, step_id_value, podcasts_db) {
  # define post-processing function to use
  # clean_only: 1, 3, 4, 7
  clean_only_steps <- c(
    "step-nonmissing-podcastguid",
    "step-nonmissing-chash",
    "step-nonmissing-newestEnclosureDuration",
    "step-valid-newestEnclosureDuration"
  )

  if (step_id_value %in% clean_only_steps) {
    df <- clean_podcast_df(extract_df)
  } else {
    if (step_id_value == "step-unique-podcastguid") {
      df <- process_unique_podcastguid(extract_df, podcasts_db)
    } else if (step_id_value == "step-unique-itunesId") {
      df <- process_unique_itunesid(extract_df, podcasts_db)
    } else if (step_id_value == "step-dup-chash-host") {
      df <- process_chash_host(extract_df, podcasts_db)
    } else if (step_id_value == "step-dup-title-imageUrl") {
      df <- process_title_image(extract_df, podcasts_db)
    } else if (step_id_value == "step-dup-chash-title-imageUrl") {
      df <- process_chash_title_image(extract_df, podcasts_db)
    }
  }
  return(df)
}

process_unique_podcastguid <- function(extract_df, podcasts_db, clean = TRUE) {
  podcast_guids <- unique(extract_df$podcastGuid)
  df <- podcasts_db |>
    filter(podcastGuid %in% podcast_guids) |>
    collect()

  if (clean) {
    df <- clean_podcast_df(df)
  }

  df <- dplyr::arrange(df, podcastGuid)

  return(df)
}

process_unique_itunesid <- function(extract_df, podcasts_db, clean = TRUE) {
  itunes_id <- unique(extract_df$itunesIdText)
  df <- podcasts_db |>
    filter(itunesIdText %in% itunes_id) |>
    collect()

  if (clean) {
    df <- clean_podcast_df(df)
  }

  df <- df |>
    select(podcastGuid, itunesIdText, everything())

  df <- dplyr::arrange(df, itunesIdText)

  return(df)
}

process_chash_host <- function(extract_df, podcasts_db, clean = TRUE) {
  host_value <- unique(extract_df$host)
  chash_value <- unique(extract_df$chash)
  df <- podcasts_db |>
    filter(host %in% !!host_value) |>
    filter(chash %in% !!chash_value) |>
    collect()

  if (clean) {
    df <- clean_podcast_df(df)
  }

  df <- df |>
    select(podcastGuid, host, chash, everything())

  return(df)
}

process_title_image <- function(extract_df, podcasts_db, clean = TRUE) {
  title_value <- unique(extract_df$title)
  image_value <- unique(extract_df$imageUrl)
  df <- podcasts_db |>
    filter(chash != "") |>
    filter(title %in% !!title_value) |>
    filter(imageUrl %in% !!image_value) |>
    collect()

  if (clean) {
    df <- clean_podcast_df(df)
  }

  df <- df |>
    select(podcastGuid, title, imageUrl, everything()) |>
    arrange(title, imageUrl)

  return(df)
}

process_chash_title_image <- function(extract_df, podcasts_db, clean = TRUE) {
  title_value <- unique(extract_df$title)
  image_value <- unique(extract_df$imageUrl)
  chash_value <- unique(extract_df$chash)
  df <- podcasts_db |>
    filter(chash %in% !!chash_value) |>
    filter(title %in% !!title_value) |>
    filter(imageUrl %in% !!image_value) |>
    collect()

  if (clean) {
    df <- clean_podcast_df(df)
  }

  df <- df |>
    select(podcastGuid, chash, title, imageUrl, everything()) |>
    arrange(chash, title, imageUrl)

  return(df)
}

