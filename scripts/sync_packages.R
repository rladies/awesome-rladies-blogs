# Periodic sync: walks data/authors/*.json, queries r-universe per handle,
# verifies authorship via DESCRIPTION roles, drops anything in each author's
# package_sync.exclude list, and writes/refreshes data/packages/<pkg>.json.
#
# Stale entries (packages no longer in r-universe) are preserved by design —
# this script never deletes a package JSON. Run from a workflow that opens a
# PR rather than auto-committing.

source(here::here("scripts/discover_helpers.R"))

authors_dir <- here::here("data/authors")
packages_dir <- here::here("data/packages")
directory_dir <- here::here("..", "directory", "data", "json")

cat("Loading authors from", authors_dir, "\n")
author_files <- list.files(authors_dir, pattern = "\\.json$", full.names = TRUE)
if (length(author_files) == 0) {
  stop("No author files found in ", authors_dir,
       ". Run scripts/migrate_authors.R first.")
}

authors <- lapply(author_files, function(f) {
  entry <- jsonlite::read_json(f)
  list(
    name = entry$name,
    github = entry$github,
    directory_id = entry$directory_id %||% NA_character_,
    enabled = isTRUE(entry$package_sync$enabled),
    exclude = unlist(entry$package_sync$exclude %||% list()) %||% character(0)
  )
})
cat("  ", length(authors), "author files;",
    sum(vapply(authors, function(a) a$enabled, logical(1))),
    "have package_sync enabled\n")

cat("Building R-Ladies directory lookup from", directory_dir, "\n")
dir_lookup <- build_directory_lookup(directory_dir)

written <- 0L
skipped_excluded <- 0L
skipped_disabled <- 0L
no_universe <- character(0)

for (a in authors) {
  if (!a$enabled) {
    skipped_disabled <- skipped_disabled + 1L
    next
  }
  pkgs <- fetch_universe(a$github)
  if (is.null(pkgs) || length(pkgs) == 0) {
    no_universe <- c(no_universe, a$github)
    next
  }
  cat(sprintf("  %s: %d r-universe packages\n", a$github, length(pkgs)))
  for (p in pkgs) {
    pkg_name <- p$Package %||% ""
    if (!nzchar(pkg_name)) next
    if (pkg_name %in% a$exclude) {
      skipped_excluded <- skipped_excluded + 1L
      cat(sprintf("    skip (excluded): %s\n", pkg_name))
      next
    }
    is_owner <- owner_match(p, a$github)
    name_hit <- name_in(a$name, p$Maintainer) || name_in(a$name, p$Author)
    if (!is_owner && !name_hit) next
    if (!is_owner && !is_authorship(a$name, p$Author, p$Maintainer)) next
    roles <- roles_for(a$name, p$Author)
    if (length(roles) == 0) roles <- "owner"
    cand <- normalise_pkg(
      p,
      source = "r-universe",
      matched_author = a$name,
      handle = a$github,
      roles = paste(roles, collapse = ",")
    )
    if (is_blank(cand$title) && is_blank(cand$description)) next
    entry <- to_package_shape(cand, dir_lookup)
    write_pkg(entry, packages_dir)
    written <- written + 1L
  }
}

cat("\nSync complete.\n")
cat("  packages written/updated:", written, "\n")
cat("  skipped (in author exclude list):", skipped_excluded, "\n")
cat("  authors with package_sync disabled:", skipped_disabled, "\n")
if (length(no_universe) > 0) {
  cat("  authors with no r-universe packages:",
      paste(no_universe, collapse = ", "), "\n")
}
