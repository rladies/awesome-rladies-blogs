library(here)
library(jsonlite)

source(here::here("scripts", "discover_helpers.R"))

content_dir <- here::here("data/content")
directory_dir <- here::here("..", "directory", "data", "json")

env_or_arg <- function(env_name, arg_index = NA) {
  v <- Sys.getenv(env_name, unset = "")
  if (nzchar(v)) {
    return(v)
  }
  if (is.na(arg_index)) {
    return("")
  }
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= arg_index) args[arg_index] else ""
}

content_type <- trimws(env_or_arg("CONTENT_TYPE", 1))
content_url <- trimws(env_or_arg("CONTENT_URL", 2))
override_title <- trimws(env_or_arg("CONTENT_TITLE"))
language <- trimws(env_or_arg("CONTENT_LANGUAGE"))
override_photo <- trimws(env_or_arg("CONTENT_PHOTO_URL"))
override_rss <- trimws(env_or_arg("CONTENT_RSS_FEED"))
override_description <- trimws(env_or_arg("CONTENT_DESCRIPTION"))
author_name <- trimws(env_or_arg("AUTHOR_NAME"))
author_twitter <- trimws(env_or_arg("AUTHOR_TWITTER"))
author_mastodon <- trimws(env_or_arg("AUTHOR_MASTODON"))
author_bluesky <- trimws(env_or_arg("AUTHOR_BLUESKY"))
author_github <- trimws(env_or_arg("AUTHOR_GITHUB"))
author_linkedin <- trimws(env_or_arg("AUTHOR_LINKEDIN"))
author_orcid <- trimws(env_or_arg("AUTHOR_ORCID"))
directory_ids_text <- env_or_arg("DIRECTORY_IDS")

if (!nzchar(content_type)) content_type <- "blog"
if (!nzchar(content_url)) {
  stop("Content URL is required (env CONTENT_URL).")
}
if (!nzchar(language)) {
  stop("Language is required (env CONTENT_LANGUAGE).")
}
if (!nzchar(author_name)) {
  stop("Author Name is required (env AUTHOR_NAME).")
}

normalise_url <- function(u) {
  u <- trimws(u)
  if (!grepl("^https?://", u, ignore.case = TRUE)) {
    u <- paste0("https://", u)
  }
  sub("/+$", "", u)
}

content_url <- normalise_url(content_url)
cat("Processing", content_type, "URL:", content_url, "\n")

# --- HTML fetch + scrape ---------------------------------------------------

# Decode the small set of HTML entities that crop up in scraped <title> and
# meta descriptions. Not a full decoder — just enough to clean up the
# common ones rather than letting raw `&rsquo;` end up in the JSON.
decode_html_entities <- function(s) {
  if (is_blank(s)) {
    return(s)
  }
  named <- c(
    "amp" = "&",
    "lt" = "<",
    "gt" = ">",
    "quot" = "\"",
    "apos" = "'",
    "nbsp" = " ",
    "rsquo" = "’",
    "lsquo" = "‘",
    "rdquo" = "”",
    "ldquo" = "“",
    "ndash" = "–",
    "mdash" = "—",
    "hellip" = "…"
  )
  for (n in names(named)) {
    s <- gsub(paste0("&", n, ";"), named[[n]], s, fixed = TRUE)
  }
  # Numeric entities like &#39; and &#x27;
  hex_matches <- regmatches(s, gregexpr("&#x([0-9a-fA-F]+);", s, perl = TRUE))[[1]]
  for (m in hex_matches) {
    code <- strtoi(sub("&#x([0-9a-fA-F]+);", "\\1", m, perl = TRUE), 16L)
    s <- sub(m, intToUtf8(code), s, fixed = TRUE)
  }
  dec_matches <- regmatches(s, gregexpr("&#(\\d+);", s, perl = TRUE))[[1]]
  for (m in dec_matches) {
    code <- as.integer(sub("&#(\\d+);", "\\1", m, perl = TRUE))
    s <- sub(m, intToUtf8(code), s, fixed = TRUE)
  }
  s
}

fetch_html <- function(url) {
  h <- curl::new_handle()
  curl::handle_setopt(
    h,
    followlocation = TRUE,
    timeout = 15,
    useragent = "rladies-content-bot/1.0"
  )
  resp <- tryCatch(
    curl::curl_fetch_memory(url, handle = h),
    error = function(e) NULL
  )
  if (is.null(resp) || resp$status_code >= 400) {
    return(NA_character_)
  }
  rawToChar(resp$content)
}

# Pull a single attribute value out of a `<meta ...>` style tag using a
# property/name predicate (e.g. property="og:title") and the attribute we want
# back (usually "content").
meta_value <- function(html, predicate_attr, predicate_value, value_attr = "content") {
  pat <- sprintf(
    "<meta\\b[^>]*\\b%s\\s*=\\s*[\"']%s[\"'][^>]*>",
    predicate_attr,
    predicate_value
  )
  m <- regmatches(html, regexpr(pat, html, ignore.case = TRUE, perl = TRUE))
  if (length(m) == 0) {
    return(NA_character_)
  }
  val_pat <- sprintf("\\b%s\\s*=\\s*[\"']([^\"']+)[\"']", value_attr)
  vm <- regmatches(m, regexpr(val_pat, m, ignore.case = TRUE, perl = TRUE))
  if (length(vm) == 0) {
    return(NA_character_)
  }
  sub(val_pat, "\\1", vm, ignore.case = TRUE, perl = TRUE)
}

scrape_title <- function(html) {
  og <- meta_value(html, "property", "og:title")
  if (!is_blank(og)) {
    return(decode_html_entities(trimws(og)))
  }
  m <- regmatches(html, regexpr("<title[^>]*>([\\s\\S]*?)</title>", html, ignore.case = TRUE, perl = TRUE))
  if (length(m) == 0) {
    return(NA_character_)
  }
  inner <- sub("<title[^>]*>([\\s\\S]*?)</title>", "\\1", m, ignore.case = TRUE, perl = TRUE)
  decode_html_entities(trimws(gsub("\\s+", " ", inner)))
}

scrape_description <- function(html) {
  og <- meta_value(html, "property", "og:description")
  if (!is_blank(og)) {
    return(decode_html_entities(trimws(og)))
  }
  md <- meta_value(html, "name", "description")
  if (!is_blank(md)) {
    return(decode_html_entities(trimws(md)))
  }
  NA_character_
}

scrape_image <- function(html, base_url) {
  og <- meta_value(html, "property", "og:image")
  if (is_blank(og)) {
    return(NA_character_)
  }
  if (grepl("^https?://", og, ignore.case = TRUE)) {
    return(og)
  }
  if (startsWith(og, "//")) {
    return(paste0("https:", og))
  }
  if (startsWith(og, "/")) {
    base_root <- sub("(https?://[^/]+).*", "\\1", base_url)
    return(paste0(base_root, og))
  }
  paste0(sub("/+$", "", base_url), "/", og)
}

# Find the first <link rel="alternate" type="application/(rss|atom)+xml" ...>
# tag and extract its href, resolving relative URLs against base_url.
scrape_feed <- function(html, base_url) {
  pat <- "<link\\b[^>]*\\brel\\s*=\\s*[\"']alternate[\"'][^>]*>"
  candidates <- regmatches(
    html,
    gregexpr(pat, html, ignore.case = TRUE, perl = TRUE)
  )[[1]]
  for (tag in candidates) {
    if (!grepl("application/(rss|atom)\\+xml", tag, ignore.case = TRUE)) {
      next
    }
    href_m <- regmatches(
      tag,
      regexpr("\\bhref\\s*=\\s*[\"']([^\"']+)[\"']", tag, perl = TRUE)
    )
    if (length(href_m) == 0) {
      next
    }
    href <- sub(".*href\\s*=\\s*[\"']([^\"']+)[\"'].*", "\\1", href_m, perl = TRUE)
    if (grepl("^https?://", href, ignore.case = TRUE)) {
      return(href)
    }
    if (startsWith(href, "//")) {
      return(paste0("https:", href))
    }
    if (startsWith(href, "/")) {
      base_root <- sub("(https?://[^/]+).*", "\\1", base_url)
      return(paste0(base_root, href))
    }
    return(paste0(sub("/+$", "", base_url), "/", href))
  }
  NA_character_
}

# YouTube channel feeds are at a stable URL keyed by the channel id, but
# vanity URLs (/c/foo, /@handle) need a page fetch to discover the id.
youtube_channel_id <- function(url, html) {
  m <- regmatches(url, regexpr("/channel/([A-Za-z0-9_-]+)", url))
  if (length(m) > 0) {
    return(sub(".*/channel/", "", m))
  }
  if (is_blank(html)) {
    return(NA_character_)
  }
  m2 <- regmatches(
    html,
    regexpr("\"channelId\"\\s*:\\s*\"(UC[A-Za-z0-9_-]+)\"", html, perl = TRUE)
  )
  if (length(m2) > 0) {
    return(sub(".*\"channelId\"\\s*:\\s*\"", "", sub("\".*", "", m2)))
  }
  m3 <- regmatches(
    html,
    regexpr("https://www\\.youtube\\.com/feeds/videos\\.xml\\?channel_id=([A-Za-z0-9_-]+)", html)
  )
  if (length(m3) > 0) {
    return(sub(".*channel_id=", "", m3))
  }
  NA_character_
}

cat("Fetching", content_url, "...\n")
html <- fetch_html(content_url)
if (is.na(html)) {
  message("Could not fetch the URL — proceeding with form values only.")
  html <- ""
}

scraped_title <- scrape_title(html)
scraped_description <- scrape_description(html)
scraped_image <- scrape_image(html, content_url)
scraped_feed <- if (content_type == "youtube") {
  cid <- youtube_channel_id(content_url, html)
  if (!is.na(cid)) {
    sprintf("https://www.youtube.com/feeds/videos.xml?channel_id=%s", cid)
  } else {
    NA_character_
  }
} else {
  scrape_feed(html, content_url)
}

resolved <- list(
  title = if (nzchar(override_title)) override_title else scraped_title,
  description = if (nzchar(override_description)) override_description else scraped_description,
  photo_url = if (nzchar(override_photo)) override_photo else scraped_image,
  rss_feed = if (nzchar(override_rss)) override_rss else scraped_feed
)

cat("Resolved fields:\n")
for (k in names(resolved)) {
  cat("  ", k, ":", if (is.na(resolved[[k]])) "<none>" else resolved[[k]], "\n")
}

# --- Author + social media -------------------------------------------------

social <- list()
if (nzchar(author_twitter)) social$twitter <- author_twitter
if (nzchar(author_mastodon)) social$mastodon <- author_mastodon
if (nzchar(author_bluesky)) social$bluesky <- author_bluesky
if (nzchar(author_github)) social$github <- author_github
if (nzchar(author_linkedin)) social$linkedin <- author_linkedin
if (nzchar(author_orcid)) social$orcid <- author_orcid

author <- list(name = author_name)
if (length(social) > 0) {
  author$social_media <- list(social)
}

# Apply directory_id pairings to the (single) author from the form.
dir_lookup <- build_directory_lookup(directory_dir)
pairs <- parse_directory_id_pairs(directory_ids_text, dir_lookup)
if (length(pairs) > 0) {
  cat("Applying", length(pairs), "directory_id pairings\n")
  authors_after <- apply_directory_id_pairs(list(author), pairs)
  author <- authors_after[[1]]
}

# --- Assemble entry --------------------------------------------------------

entry <- list(
  title = if (is.na(resolved$title)) author_name else resolved$title,
  type = content_type,
  url = content_url,
  language = language,
  authors = list(author)
)
if (!is.na(resolved$description)) entry$description <- resolved$description
if (!is.na(resolved$photo_url)) entry$photo_url <- resolved$photo_url
if (!is.na(resolved$rss_feed)) entry$rss_feed <- resolved$rss_feed

# Filename = host (strip protocol and www.)
host <- sub("^https?://", "", content_url, ignore.case = TRUE)
host <- sub("^www\\.", "", host, ignore.case = TRUE)
host <- sub("/.*$", "", host)
filename <- paste0(host, ".json")
path <- file.path(content_dir, filename)

if (!dir.exists(content_dir)) {
  dir.create(content_dir, recursive = TRUE)
}

# Merge with any existing file so we don't overwrite manual edits.
if (file.exists(path)) {
  existing <- jsonlite::read_json(path)
  for (k in names(existing)) {
    if (k == "authors") next
    if (is_blank(entry[[k]]) && !is_blank(existing[[k]])) {
      entry[[k]] <- existing[[k]]
    }
  }
  if (!is_blank(existing$authors) && length(existing$authors) > 0) {
    entry$authors <- existing$authors
  }
}

jsonlite::write_json(
  entry,
  path,
  pretty = TRUE,
  auto_unbox = TRUE,
  na = "null"
)

cat("Wrote", path, "\n")

gha_out <- Sys.getenv("GITHUB_OUTPUT", unset = "")
if (nzchar(gha_out)) {
  rel_path <- sub(
    paste0("^", here::here(), "/?"),
    "",
    path,
    fixed = FALSE
  )
  writeLines(
    c(
      sprintf("file_path=%s", rel_path),
      sprintf("filename=%s", host),
      sprintf("content_type=%s", content_type)
    ),
    gha_out
  )
}
