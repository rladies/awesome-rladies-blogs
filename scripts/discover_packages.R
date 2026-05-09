library(here)

source(here::here("scripts", "discover_helpers.R"))

content_dir <- here::here("data/content")
packages_dir <- here::here("data/packages")
directory_dir <- here::here("..", "directory", "data", "json")

cat("Loading author list from", content_dir, "\n")
authors <- read_authors(content_dir)
cat("  found", length(authors), "author entries\n")

cat("Building R-Ladies directory lookup from", directory_dir, "\n")
dir_lookup <- build_directory_lookup(directory_dir)
cat(
  "  ",
  length(dir_lookup$by_handle),
  "github handles, ",
  length(dir_lookup$by_name),
  "names indexed\n"
)

candidates <- list()

cat("Querying R-universe per author...\n")
for (a in authors) {
  if (is.na(a$github)) {
    next
  }
  pkgs <- fetch_universe(a$github)
  if (is.null(pkgs) || length(pkgs) == 0) {
    next
  }
  for (p in pkgs) {
    is_owner <- owner_match(p, a$github)
    name_hit <- name_in(a$name, p$Maintainer) || name_in(a$name, p$Author)
    if (!is_owner && !name_hit) {
      next
    }
    if (!is_owner && !is_authorship(a$name, p$Author, p$Maintainer)) {
      next
    }
    roles <- roles_for(a$name, p$Author)
    if (length(roles) == 0) {
      roles <- "owner"
    }
    candidates[[length(candidates) + 1]] <-
      normalise_pkg(
        p,
        "r-universe",
        a$name,
        a$github,
        paste(roles, collapse = ",")
      )
  }
  cat("  ", a$github, "->", length(pkgs), "in universe\n")
}

cat("Fetching CRAN package db...\n")
cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
if (!is.null(cran)) {
  cat("  ", nrow(cran), "CRAN packages\n")
  for (a in authors) {
    hits <- which(
      vapply(cran$Author, function(s) name_in(a$name, s), logical(1)) |
        vapply(cran$Maintainer, function(s) name_in(a$name, s), logical(1))
    )
    for (i in hits) {
      row <- cran[i, ]
      if (!is_authorship(a$name, row$Author, row$Maintainer)) {
        next
      }
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
}

cat("Fetching Bioconductor package db (bioc.r-universe.dev)...\n")
bioc <- tryCatch(fetch_bioc_db(), error = function(e) NULL)
if (!is.null(bioc) && length(bioc) > 0) {
  cat("  ", length(bioc), "Bioconductor packages\n")
  for (a in authors) {
    for (p in bioc) {
      name_hit <- name_in(a$name, p$Maintainer) || name_in(a$name, p$Author)
      if (!name_hit) {
        next
      }
      if (!is_authorship(a$name, p$Author, p$Maintainer)) {
        next
      }
      roles <- roles_for(a$name, p$Author)
      if (length(roles) == 0) {
        roles <- "unknown"
      }
      candidates[[length(candidates) + 1]] <-
        normalise_pkg(
          p,
          "bioconductor",
          a$name,
          a$github,
          paste(roles, collapse = ",")
        )
    }
  }
}

cat("Total raw candidate rows:", length(candidates), "\n")
dedup_key <- vapply(
  candidates,
  function(x) tolower(x$package %||% ""),
  character(1)
)
candidates <- candidates[!duplicated(dedup_key) & nzchar(dedup_key)]
cat("After dedupe by package name:", length(candidates), "\n")

# Drop entries where the package failed to build in r-universe (no title and
# no description means we have nothing usable).
candidates <- Filter(
  function(x) !(is_blank(x$title) && is_blank(x$description)),
  candidates
)
cat("After dropping unbuilt packages:", length(candidates), "\n")

cat("Writing per-package files to", packages_dir, "\n")
for (cand in candidates) {
  entry <- to_package_shape(cand, dir_lookup)
  write_pkg(entry, packages_dir)
}

cat("Enriching meetupr from rladies r-universe...\n")
mp <- fetch_universe_package("rladies", "meetupr")
if (!is.null(mp) && !is.null(mp$Package)) {
  cand_mp <- normalise_pkg(
    mp,
    "r-universe",
    "R-Ladies Global",
    "rladies",
    "cph"
  )
  entry_mp <- to_package_shape(cand_mp, dir_lookup)
  write_pkg(entry_mp, packages_dir)
  cat("  meetupr updated\n")
} else {
  cat("  could not fetch meetupr metadata\n")
}

cat(
  "Done.",
  length(candidates),
  "candidate package files written (+meetupr).\n"
)
