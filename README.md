<!-- badges: start -->
<a href="https://podcastindex.org"><img src="assets/img/pc20badgeblue.png" width="100" alt="Podcasting 2.0" /></a>
<a href="https://www.repostatus.org/#experimental"><img src="https://www.repostatus.org/badges/latest/experimental.svg" alt="The project is in active development and unstable." /></a>
<a href="https://opensource.org/license/mit/"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
<!-- badges: end -->

## Podcast Index Database Explorer

This repository contains a very preliminary attempt at leveraging a custom chat bot (based on LLMs) to help the user explore the Podcast Index Database. Bugs are abound!

## Background and Motivation

The [Podcast Index](https://podcastindex.org) is an independent and open catalog of podcasts feeds serving as the backbone of what is referred to as the Podcasting 2.0 initiative. The data contained in the Podcast Index is available through a robust [REST API](https://podcastindex-org.github.io/docs-api/#overview--libraries) as well as a [SQLite database](https://public.podcastindex.org/podcastindex_feeds.db.tgz) updated every week. 

I have created the [PodcastIndex Database Dashboard](https://rpodcast.github.io/pod-db-dash/) as a way to help users assess podcast records that are duplicated across the database, as well as viewing a custom set of database quality checks. The calculatikons and quality checks are pre-computed on a weekly basis. The database explorer project is focused solely on helping users explore the database contents in an intuitive way.
