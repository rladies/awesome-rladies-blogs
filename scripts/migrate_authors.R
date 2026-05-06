library(jsonlite)
library(here)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

content_dir <- here::here("data/content")
authors_dir <- here::here("data/authors")

if (!dir.exists(authors_dir)) dir.create(authors_dir, recursive = TRUE)

content_files <- list.files(content_dir, pattern = "\\.json$", full.names = TRUE)

written <- 0L
skipped_existing <- 0L
skipped_no_handle <- 0L

for (cf in content_files) {
  blog <- jsonlite::read_json(cf)
  for (a in blog$authors %||% list()) {
    sm <- a$social_media[[1]] %||% list()
    handle <- sm$github
    if (is.null(handle) || !nzchar(handle)) {
      skipped_no_handle <- skipped_no_handle + 1L
      next
    }
    out_path <- file.path(authors_dir, paste0(handle, ".json"))
    if (file.exists(out_path)) {
      skipped_existing <- skipped_existing + 1L
      next
    }
    entry <- list(
      name = a$name,
      github = handle,
      directory_id = a$directory_id %||% NA_character_,
      orcid = sm$orcid %||% NA_character_,
      package_sync = list(
        enabled = TRUE,
        exclude = list()
      )
    )
    jsonlite::write_json(entry, out_path, pretty = TRUE,
                         auto_unbox = TRUE, na = "null")
    written <- written + 1L
    cat("wrote", basename(out_path), "\n")
  }
}

cat("\nDone.",
    "wrote =", written,
    "| skipped (already existed) =", skipped_existing,
    "| skipped (no github handle) =", skipped_no_handle, "\n")
