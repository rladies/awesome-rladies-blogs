library(httr2)
library(jsonlite)
library(here)

source(here::here("scripts", "scrape_helpers.R"))

content_dir <- here::here("data/content")
packages_dir <- here::here("data/packages")
report_file <- here::here("image-check-report.md")

check_url <- function(url) {
  resp <- tryCatch(
    request(url) |>
      req_user_agent("rladies-image-sweep/1.0") |>
      req_timeout(15) |>
      req_error(is_error = function(x) FALSE) |>
      req_perform(),
    error = function(e) e
  )
  if (inherits(resp, "error")) {
    return(list(ok = FALSE, reason = paste0("network error: ", conditionMessage(resp))))
  }
  status <- resp_status(resp)
  if (status >= 400) {
    return(list(ok = FALSE, reason = paste0("HTTP ", status)))
  }
  ctype <- resp_content_type(resp)
  if (length(ctype) == 0 || !grepl("^image/", ctype, ignore.case = TRUE)) {
    shown <- if (length(ctype)) ctype else "(none)"
    return(list(ok = FALSE, reason = paste0("non-image content-type: ", shown)))
  }
  list(ok = TRUE)
}

# Try to find a working replacement by scraping og:image from the entry's
# homepage. Returns NA_character_ if no candidate is found or if the candidate
# itself doesn't resolve to an image.
suggest_replacement <- function(homepage_url) {
  if (is_blank(homepage_url)) {
    return(NA_character_)
  }
  html <- fetch_html(homepage_url)
  if (is.na(html) || !nzchar(html)) {
    return(NA_character_)
  }
  candidate <- scrape_image(html, homepage_url)
  if (is.na(candidate) || is_blank(candidate)) {
    return(NA_character_)
  }
  if (isTRUE(check_url(candidate)$ok)) {
    return(candidate)
  }
  NA_character_
}

scan_dir <- function(dir, field, homepage_field) {
  if (!dir.exists(dir)) {
    return(list())
  }
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  root <- paste0(here::here(), "/")
  out <- list()
  for (f in files) {
    entry <- tryCatch(jsonlite::read_json(f), error = function(e) NULL)
    if (is.null(entry)) next
    url <- entry[[field]]
    if (is_blank(url)) next
    res <- check_url(url)
    if (isTRUE(res$ok)) next
    cat(sprintf("  broken %s in %s — looking for og:image...\n", field, basename(f)))
    suggestion <- suggest_replacement(entry[[homepage_field]])
    out[[length(out) + 1]] <- list(
      file = sub(root, "", f, fixed = TRUE),
      url = url,
      reason = res$reason,
      suggestion = suggestion
    )
  }
  out
}

format_section <- function(title, field, items) {
  if (length(items) == 0) {
    return(character())
  }
  rows <- unlist(lapply(items, function(b) {
    head <- sprintf("- [`%s`](%s) — `%s` — %s", b$file, b$file, b$url, b$reason)
    if (is.na(b$suggestion)) {
      return(head)
    }
    c(head, sprintf("  - suggested replacement (og:image): `%s`", b$suggestion))
  }))
  c(
    sprintf("## %s (`%s`) — %d broken", title, field, length(items)),
    "",
    rows,
    ""
  )
}

cat("Scanning data/content for photo_url...\n")
content_broken <- scan_dir(content_dir, "photo_url", "url")
cat("Scanning data/packages for logo_url...\n")
packages_broken <- scan_dir(packages_dir, "logo_url", "pkdown_url")

total <- length(content_broken) + length(packages_broken)
with_suggestion <- sum(
  vapply(c(content_broken, packages_broken), function(x) !is.na(x$suggestion), logical(1))
)
ts <- format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC")

lines <- c(
  "# Image URL sweep report",
  "",
  sprintf(
    "Sweep run on %s — %d broken image URL(s) detected, %d with suggested replacements.",
    ts,
    total,
    with_suggestion
  ),
  ""
)
if (total == 0) {
  lines <- c(lines, "All image URLs resolve to images.", "")
} else {
  lines <- c(lines, format_section("Content", "photo_url", content_broken))
  lines <- c(lines, format_section("Packages", "logo_url", packages_broken))
}

writeLines(lines, report_file)
cat(paste(lines, collapse = "\n"), "\n", sep = "")
cat(sprintf("\nTotal broken: %d (%d with suggestions)\nReport written to %s\n", total, with_suggestion, report_file))
