library(jsonlite)
library(here)

# Sources fetch_universe_package, normalise_pkg, parse_authors, to_package_shape,
# write_pkg, build_directory_lookup, to_iso_date, %||%, etc. Pipeline at the
# bottom of discover_packages.R is gated by sys.nframe() and skipped when
# sourced.
source(here::here("scripts/discover_packages.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1 || !nzchar(args[1])) {
  stop(
    "Usage: Rscript scripts/add_package.R <pkg> [r-universe-handle] [author-directory-id]"
  )
}
pkg_name <- args[1]
handle <- if (length(args) >= 2 && nzchar(args[2])) args[2] else NA_character_
dir_id <- if (length(args) >= 3 && nzchar(args[3])) args[3] else NA_character_

cat("Building entry for", pkg_name,
    if (!is.na(handle)) sprintf("(handle: %s)", handle) else "(no handle)",
    "\n")

cand <- NULL

if (!is.na(handle)) {
  pkg_meta <- fetch_universe_package(handle, pkg_name)
  if (!is.null(pkg_meta) && !is.null(pkg_meta$Package)) {
    cat("Fetched from r-universe (", handle, ")\n", sep = "")
    cand <- normalise_pkg(
      pkg_meta,
      source = "r-universe",
      matched_author = NA_character_,
      handle = handle
    )
  } else {
    cat("Not found on r-universe, falling back to CRAN\n")
  }
}

if (is.null(cand)) {
  cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
  if (is.null(cran)) {
    stop("CRAN package db unreachable and no r-universe match for ", pkg_name)
  }
  row <- cran[cran$Package == pkg_name, , drop = FALSE]
  if (nrow(row) == 0) {
    stop("Package '", pkg_name, "' not found on r-universe or CRAN")
  }
  cat("Fetched from CRAN\n")
  cand <- list(
    package = row$Package,
    title = row$Title,
    description = trimws(gsub("\\s+", " ", row$Description %||% "")),
    repo_owner = NA_character_,
    url = row$URL,
    bug_reports = row$BugReports,
    maintainer = row$Maintainer,
    last_updated = to_iso_date(row[["Date/Publication"]]),
    authors = parse_authors(row$Author),
    matched_author = NA_character_,
    matched_handle = NA_character_,
    matched_roles = NA_character_,
    source = "cran"
  )
}

directory_dir <- here::here("..", "directory", "data", "json")
dir_lookup <- if (dir.exists(directory_dir)) {
  build_directory_lookup(directory_dir)
} else {
  list(by_handle = list(), by_name = list())
}

entry <- to_package_shape(cand, dir_lookup)

if (!is.na(dir_id) && length(entry$authors) > 0) {
  entry$authors[[1]]$directory_id <- dir_id
}

packages_dir <- here::here("data/packages")
write_pkg(entry, packages_dir)

out_path <- file.path(packages_dir, paste0(entry$name, ".json"))
cat("Wrote", out_path, "\n")

schema_path <- here::here("scripts/json_schema/packages.json")
if (file.exists(schema_path) && requireNamespace("jsonvalidate", quietly = TRUE)) {
  validator <- jsonvalidate::json_validator(schema_path)
  ok <- validator(out_path, verbose = TRUE, error = FALSE, greedy = TRUE)
  if (!isTRUE(ok)) {
    stop("Schema validation failed for ", out_path)
  }
  cat("Schema validation passed\n")
}
