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

podcast_db_theme <- function() {
  reactableTheme(
    style = list(fontSize = '0.875rem')
  )
}

record_detail_table <- function(df, preprocess = TRUE, nrow = NULL, preprocessing_note = NULL) {
  if (preprocess) {
    # obtain categories df
    #cat_df <- gen_categories_df(df)

    # preprocessing
    df <- df |>
      dplyr::mutate(
        episodeCount_colors = dplyr::case_when(
          episodeCount < 1 ~ "#e00000",
          episodeCount >= 1 & episodeCount < 5 ~ "#fb9332",
          TRUE ~ '#0c7a36'
        )
      ) |>
      dplyr::mutate(
        lastHttpStatus_colors = dplyr::case_when(
          lastHttpStatus == 200 ~ "#008000",
          TRUE ~ "#e00000"
        )
      ) |>
      dplyr::mutate(
        imageUrl_clean = dplyr::case_when(
          imageUrl == "" ~ "https://podcastindex.org/images/no-cover-art.png",
          stringr::str_length(imageUrl) < 29 ~ "https://podcastindex.org/images/no-cover-art.png",
          !grepl("https|http", imageUrl) ~ "https://podcastindex.org/images/no-cover-art.png",
          .default = imageUrl
        )
      ) |>
      #dplyr::select(-newestItemPubdate, -oldestItemPubdate, -createdOn, -lastUpdate) |>
      dplyr::select(imageUrl_clean, podcastGuid, title, url, lastUpdate_p, newestEnclosureDuration, newestItemPubdate_p, oldestItemPubdate_p, episodeCount, everything())

    df <- dplyr::select(df, -any_of(c("newestItemPubdate", "oldestItemPubdate", "createdOn", "lastUpdate")))
  }

  if (!is.null(nrow)) {
    df <- dplyr::slice(df, 1:nrow)
  }
  
  tbl_object <- reactable::reactable(
    df,
    defaultColDef = colDef(vAlign = "center", headerClass = "header"),
    columns = list(
      imageUrl = colDef(show = FALSE),
      imageUrl_clean = colDef(
        name = "",
        maxWidth = 70,
        align = "center",
        sticky = "left",
        cell = reactablefmtr::embed_img(height = 40, width = 40)
      ),
      podcastGuid = colDef(
        name = "Podcast GUID",
        sticky = "left"
      ),
      title = colDef(
        name = "Title",
        sticky = "left",
        show = TRUE
      ),
      id = colDef(
        show = FALSE
      ),
      url = colDef(
        name = "URLs",
        cell = function(value, index) {
          id <- dplyr::slice(df, index) |> dplyr::pull(id)
          podindex_url <- htmltools::tags$a(href = paste0("https://podcastindex.org/podcast/", id), target = "_blank", " podcastindex ")
          url <- htmltools::tags$a(href = value, target = "_blank", " rss-feed ")
          link <- htmltools::tags$a(href = dplyr::slice(df, index) |> dplyr::pull(link), target = "_blank", " link ")
          original_url <- htmltools::tags$a(href = dplyr::slice(df, index) |> dplyr::pull(originalUrl), target = "_blank", " original url ")

          div(
            class = "podcast-urls",
            podindex_url,
            url
          )
        }
      ),
      lastUpdate_p = colDef(
        name = "Last Update",
        format = colFormat(datetime = TRUE, hour12 = NULL)
      ),
      link = colDef(
        name = "Link",
        cell = function(value) {
          htmltools::tags$a(href = value, target = "_blank", "click here")
        },
        show = FALSE
      ),
      lastHttpStatus = colDef(
        name = "HTTP Status",
        cell = reactablefmtr::color_tiles(
          df,
          color_ref = 'lastHttpStatus_colors'
        )
        # style = function(value) {
        #   if (value == 200L) {
        #     color <- "#008000"
        #   } else {
        #     color <- "#e00000"
        #   }
        # }
      ),
      dead = colDef(
        show = FALSE
      ),
      contentType = colDef(
        show = FALSE
      ),
      itunesId = colDef(
        show = FALSE
      ),
      itunesIdText = colDef(
        name = "itunesId",
        show = TRUE
      ),
      originalUrl = colDef(
        name = "Original URL",
        cell = function(value) {
          htmltools::tags$a(href = value, target = "_blank", "click here")
        },
        show = FALSE
      ),
      itunesAuthor = colDef(
        show = FALSE
      ),
      itunesOwnerName = colDef(
        show = FALSE
      ),
      explicit = colDef(
        show = FALSE
      ),
      itunesType = colDef(
        name = "itunesType",
        show = FALSE
      ),
      generator = colDef(
        name = "Generator",
        show = FALSE
      ),
      newestItemPubdate_p = colDef(
        name = "Newest Entry",
        format = colFormat(datetime = TRUE)
      ),
      language = colDef(
        name = "Language",
        show = FALSE
      ),
      oldestItemPubdate_p = colDef(
        name = "Oldest Entry",
        format = colFormat(datetime = TRUE)
      ),
      episodeCount = colDef(
        name = "Episodes",
        cell = reactablefmtr::color_tiles(
          df,
          color_ref = 'episodeCount_colors'
        )
      ),
      popularityScore = colDef(
        name = "Popularity Score",
        show = FALSE
      ),
      priority = colDef(
        show = FALSE
      ),
      createdOn_p = colDef(
        name = "CreatedOn",
        format = colFormat(datetime = TRUE),
        show = FALSE
      ),
      updateFrequency = colDef(
        name = "Update Frequency",
        style = color_scales(df),
        show = FALSE
      ),
      chash = colDef(
        show = TRUE
      ),
      host = colDef(
        name = "Host",
        show = TRUE
      ),
      newestEnclosureUrl = colDef(
        name = "Newest Enclosure URL",
        cell = function(value) {
          htmltools::tags$a(href = value, target = "_blank", "click here")
        },
        show = FALSE
      ),
      description = colDef(
        show = FALSE
      ),
      category = colDef(
        name = "Categories",
        show = FALSE
      ),
      newestEnclosureDuration = colDef(
        name = "Newest Duration",
        cell = function(value) {
          if (is.na(value)) return("NA")

          td <- lubridate::seconds_to_period(value)
          sprintf(
            '%02d:%02d:%02d',
            td@hour,
            lubridate::minute(td),
            lubridate::second(td))
        }
        #format = colFormat(separators = TRUE)
      ),
      episodeCount_colors = colDef(
        show = FALSE
      ),
      lastHttpStatus_colors = colDef(
        show = FALSE
      ),
      created_timespan_days = colDef(
        show = FALSE
      ),
      pub_timespan_days = colDef(
        show = FALSE
      )
    ),
    theme = podcast_db_theme()
  )

  return(tbl_object)
}