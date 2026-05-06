# Re-probe logo URLs for existing data/packages/*.json entries that don't
# have a logo recorded yet. Uses the enhanced probe_logo_url from
# discover_packages.R (pkgdown -> raw man/figures -> README img tag).
#
# Only fills in missing logos; existing logo_url values are preserved.

library(here)

# Source only the helpers, stop before the pipeline runs.
src_lines <- readLines(here::here("scripts/discover_packages.R"))
pipeline_start <- grep("^# ---- Pipeline", src_lines)[1]
helpers <- paste(src_lines[seq_len(pipeline_start - 1)], collapse = "\n")
eval(parse(text = helpers), envir = globalenv())

packages_dir <- here::here("data/packages")
files <- list.files(packages_dir, pattern = "\\.json$", full.names = TRUE)

filled <- 0L
checked <- 0L

for (f in files) {
  entry <- jsonlite::read_json(f)
  if (!is.null(entry$logo_url) && nzchar(entry$logo_url)) next
  checked <- checked + 1L
  url <- probe_logo_url(entry$pkdown_url %||% NA_character_,
                        entry$repo_url %||% NA_character_)
  if (is.na(url)) {
    cat(sprintf("  no logo: %s\n", entry$name))
    next
  }
  cat(sprintf("  found:   %s -> %s\n", entry$name, url))
  entry$logo_url <- url
  scalar_fields <- c("name", "title", "description", "repo_url", "pkdown_url",
                     "bug_reports_url", "logo_url", "last_updated")
  for (sf in scalar_fields) {
    if (is.null(entry[[sf]])) entry[[sf]] <- NA_character_
  }
  jsonlite::write_json(entry, f, pretty = TRUE, auto_unbox = TRUE, na = "null")
  filled <- filled + 1L
}

cat("\nDone. Checked", checked, "packages without logos; filled", filled, "\n")
