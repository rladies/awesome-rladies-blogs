#!/usr/bin/env Rscript
# Run package discovery for a single author and write candidate package JSON
# files into data/packages_pending/<slug>/. Useful when an author replies to a
# directory PR and asks for additional packages we missed (e.g. Bioconductor
# packages, packages where they're an author but not the maintainer).
#
# Usage:
#   Rscript scripts/discover_for_author.R <slug> "<Author Name>" <github_handle>
#
# Example:
#   Rscript scripts/discover_for_author.R susan-holmes "Susan Holmes" spholmes

suppressPackageStartupMessages(library(here))
source(here::here("scripts", "discover_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop(
    "Usage: Rscript scripts/discover_for_author.R <slug> \"<Author Name>\" <github_handle>",
    call. = FALSE
  )
}
slug <- args[[1]]
author_name <- args[[2]]
github_handle <- args[[3]]

pending_dir <- here::here("data", "packages_pending", slug)
directory_dir <- here::here("..", "directory", "data", "json")

dir_lookup <- build_directory_lookup(directory_dir)

a <- list(name = author_name, github = github_handle)
candidates <- list()

cat("R-universe lookup for handle:", a$github, "\n")
pkgs <- fetch_universe(a$github)
if (!is.null(pkgs)) {
  for (p in pkgs) {
    is_owner <- owner_match(p, a$github)
    name_hit <- name_in(a$name, p$Maintainer) || name_in(a$name, p$Author)
    if (!is_owner && !name_hit) next
    if (!is_owner && !is_authorship(a$name, p$Author, p$Maintainer)) next
    roles <- roles_for(a$name, p$Author)
    if (length(roles) == 0) roles <- "owner"
    candidates[[length(candidates) + 1]] <-
      normalise_pkg(p, "r-universe", a$name, a$github, paste(roles, collapse = ","))
  }
}
cat("  ", length(candidates), "candidates after r-universe\n")

cat("CRAN lookup...\n")
cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
if (!is.null(cran)) {
  hits <- which(
    vapply(cran$Author, function(s) name_in(a$name, s), logical(1)) |
      vapply(cran$Maintainer, function(s) name_in(a$name, s), logical(1))
  )
  for (i in hits) {
    row <- cran[i, ]
    if (!is_authorship(a$name, row$Author, row$Maintainer)) next
    roles <- paste(roles_for(a$name, row$Author), collapse = ",")
    candidates[[length(candidates) + 1]] <- list(
      package = row$Package,
      title = row$Title,
      description = trimws(gsub("\\s+", " ", row$Description %||% "")),
      repo_owner = NA_character_,
      url = row$URL,
      bug_reports = row$BugReports,
      maintainer = row$Maintainer,
      last_updated = to_iso_date(row[["Date/Publication"]]),
      authors = parse_authors(row$Author),
      matched_author = a$name,
      matched_handle = a$github,
      matched_roles = roles,
      source = "cran"
    )
  }
}
cat("  ", length(candidates), "candidates after CRAN\n")

cat("Bioconductor lookup (bioc.r-universe.dev)...\n")
bioc <- tryCatch(fetch_bioc_db(), error = function(e) NULL)
if (!is.null(bioc)) {
  for (p in bioc) {
    name_hit <- name_in(a$name, p$Maintainer) || name_in(a$name, p$Author)
    if (!name_hit) next
    if (!is_authorship(a$name, p$Author, p$Maintainer)) next
    roles <- roles_for(a$name, p$Author)
    if (length(roles) == 0) roles <- "unknown"
    candidates[[length(candidates) + 1]] <-
      normalise_pkg(p, "bioconductor", a$name, a$github, paste(roles, collapse = ","))
  }
}
cat("  ", length(candidates), "candidates after Bioconductor\n")

dedup_key <- vapply(candidates, function(x) tolower(x$package %||% ""), character(1))
candidates <- candidates[!duplicated(dedup_key) & nzchar(dedup_key)]
candidates <- Filter(function(x) !(is_blank(x$title) && is_blank(x$description)), candidates)
cat("After dedupe and dropping unbuilt packages:", length(candidates), "\n")

if (!dir.exists(pending_dir)) {
  dir.create(pending_dir, recursive = TRUE)
}

for (cand in candidates) {
  entry <- to_package_shape(cand, dir_lookup)
  # Stamp the directory_id on the matched author so downstream tools can use it.
  entry$authors <- lapply(entry$authors, function(p) {
    if (names_match(p$name, author_name)) {
      p$directory_id <- slug
    }
    p
  })
  path <- write_pkg(entry, pending_dir)
  cat("  wrote", basename(path), "(source:", cand$source, ")\n")
}

cat("Done.", length(candidates), "package files in", pending_dir, "\n")
