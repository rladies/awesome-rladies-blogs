library(here)
library(jsonlite)

source(here::here("scripts", "discover_helpers.R"))

packages_dir <- here::here("data/packages")
directory_dir <- here::here("..", "directory", "data", "json")

# Inputs come from env vars set by the calling workflow. Falling back to
# commandArgs makes the script convenient to invoke locally.
env_or_arg <- function(env_name, arg_index) {
  v <- Sys.getenv(env_name, unset = "")
  if (nzchar(v)) {
    return(v)
  }
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= arg_index) args[arg_index] else ""
}

pkg_name <- trimws(env_or_arg("PKG_NAME", 1))
owner_hint <- trimws(env_or_arg("PKG_OWNER", 2))
repo_url_hint <- trimws(env_or_arg("PKG_REPO_URL", 3))

if (!nzchar(pkg_name)) {
  stop("Package name is required (env PKG_NAME or first positional arg).")
}

cat("Looking up package:", pkg_name, "\n")
if (nzchar(owner_hint)) cat("  with owner hint:", owner_hint, "\n")
if (nzchar(repo_url_hint)) cat("  with repo url hint:", repo_url_hint, "\n")

# If we got a github URL but no explicit owner, pull owner out of the URL so
# we can hit the right r-universe namespace.
if (!nzchar(owner_hint) && nzchar(repo_url_hint)) {
  owner_repo <- github_owner_repo(repo_url_hint)
  if (!is.na(owner_repo)) {
    owner_hint <- strsplit(owner_repo, "/", fixed = TRUE)[[1]][1]
    cat("  derived owner from repo URL:", owner_hint, "\n")
  }
}

dir_lookup <- build_directory_lookup(directory_dir)

cand <- NULL

# 1. R-universe (under the requested owner) is the richest source: gives us
#    the rebuilt DESCRIPTION fields plus _owner and Date/Publication.
if (nzchar(owner_hint)) {
  cat("Querying r-universe for", owner_hint, "/", pkg_name, "...\n")
  pkg <- fetch_universe_package(owner_hint, pkg_name)
  if (!is.null(pkg) && !is_blank(pkg$Package)) {
    cand <- normalise_pkg(
      pkg,
      "r-universe",
      pkg$Maintainer %||% NA_character_,
      owner_hint,
      NA_character_
    )
    cat("  found in r-universe\n")
  } else {
    cat("  not found in r-universe\n")
  }
}

# 2. CRAN fallback when r-universe didn't have it. Cheaper to call once than
#    to retry under guessed owners.
if (is.null(cand)) {
  cat("Falling back to CRAN package db...\n")
  cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
  if (!is.null(cran)) {
    hit <- which(tolower(cran$Package) == tolower(pkg_name))
    if (length(hit) > 0) {
      row <- cran[hit[1], ]
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
      cat("  found on CRAN\n")
    } else {
      cat("  not found on CRAN\n")
    }
  }
}

if (is.null(cand)) {
  stop(sprintf(
    "Could not find package '%s' in r-universe (owner: %s) or CRAN.",
    pkg_name,
    if (nzchar(owner_hint)) owner_hint else "<none>"
  ))
}

# Honour an explicit repo URL hint when r-universe/CRAN didn't surface one.
if (is_blank(cand$url) && nzchar(repo_url_hint)) {
  cand$url <- repo_url_hint
}

entry <- to_package_shape(cand, dir_lookup)
path <- write_pkg(entry, packages_dir)

cat("Wrote", path, "\n")

# The workflow reads these on stdout to drive the branch name and PR body.
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
      sprintf("package_name=%s", entry$name),
      sprintf("source=%s", cand$source)
    ),
    gha_out
  )
}
