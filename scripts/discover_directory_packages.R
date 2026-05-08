library(here)
library(jsonlite)

source(here::here("scripts", "discover_helpers.R"))

content_dir <- here::here("data/content")
packages_dir <- here::here("data/packages")
pending_dir <- here::here("data/packages_pending")
directory_dir <- here::here("..", "directory", "data", "json")

limit <- suppressWarnings(as.integer(Sys.getenv("LIMIT", "0")))
if (is.na(limit)) limit <- 0L

cre_threshold <- suppressWarnings(as.integer(
  Sys.getenv("CRE_ONLY_THRESHOLD", "5")
))
if (is.na(cre_threshold) || cre_threshold < 1) cre_threshold <- 5L

cat("Loading already-opted-in handles from", content_dir, "\n")
blog_authors <- read_authors(content_dir)
opted_in <- vapply(
  blog_authors,
  function(a) {
    g <- a$github %||% NA_character_
    if (is_blank(g)) NA_character_ else tolower(trimws(g))
  },
  character(1)
)
opted_in <- unique(opted_in[!is.na(opted_in) & nzchar(opted_in)])
cat("  ", length(opted_in), "handles already covered via blogs\n")

cat("Loading directory entries from", directory_dir, "\n")
entries <- read_directory_entries(directory_dir)
cat("  ", length(entries), "with github handles\n")

new_entries <- Filter(
  function(e) !(tolower(e$github) %in% opted_in),
  entries
)
cat("  ", length(new_entries), "after dropping already-opted-in handles\n")

if (limit > 0L && length(new_entries) > limit) {
  cat("  capping to LIMIT =", limit, "\n")
  new_entries <- new_entries[seq_len(limit)]
}

existing_pkgs <- tolower(sub(
  "\\.json$",
  "",
  list.files(packages_dir, pattern = "\\.json$")
))

dir_lookup <- build_directory_lookup(directory_dir)

cat("Fetching CRAN package db...\n")
cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
if (!is.null(cran)) {
  cat("  ", nrow(cran), "CRAN packages\n")
}

dir.create(pending_dir, recursive = TRUE, showWarnings = FALSE)
# Wipe previous outputs (per-author folders + generated files) but preserve
# user-curated files like _keep.txt.
for (item in list.files(pending_dir, full.names = TRUE, no.. = TRUE)) {
  if (utils::file_test("-d", item)) {
    unlink(item, recursive = TRUE)
  } else if (basename(item) %in% c("_manifest.json", "_open_prs.sh")) {
    unlink(item)
  }
}

discover_for <- function(e) {
  cands <- list()

  pkgs <- fetch_universe(e$github)
  if (!is.null(pkgs)) {
    for (p in pkgs) {
      is_owner <- owner_match(p, e$github)
      name_hit <- name_in(e$name, p$Maintainer) || name_in(e$name, p$Author)
      if (!is_owner && !name_hit) {
        next
      }
      if (!is_owner && !is_authorship(e$name, p$Author, p$Maintainer)) {
        next
      }
      roles <- roles_for(e$name, p$Author)
      if (length(roles) == 0) {
        roles <- "owner"
      }
      cands[[length(cands) + 1]] <- normalise_pkg(
        p,
        "r-universe",
        e$name,
        e$github,
        paste(roles, collapse = ",")
      )
    }
  }

  if (!is.null(cran)) {
    hits <- which(
      vapply(cran$Author, function(s) name_in(e$name, s), logical(1)) |
        vapply(cran$Maintainer, function(s) name_in(e$name, s), logical(1))
    )
    for (i in hits) {
      row <- cran[i, ]
      if (!is_authorship(e$name, row$Author, row$Maintainer)) {
        next
      }
      roles <- paste(roles_for(e$name, row$Author), collapse = ",")
      cands[[length(cands) + 1]] <- list(
        package = row$Package,
        title = row$Title,
        description = trimws(gsub("\\s+", " ", row$Description %||% "")),
        repo_owner = NA_character_,
        url = row$URL,
        bug_reports = row$BugReports,
        maintainer = row$Maintainer,
        last_updated = to_iso_date(row[["Date/Publication"]]),
        authors = parse_authors(row$Author),
        matched_author = e$name,
        matched_handle = e$github,
        matched_roles = roles,
        source = "cran"
      )
    }
  }

  if (length(cands) == 0) {
    return(cands)
  }

  keys <- vapply(cands, function(x) tolower(x$package %||% ""), character(1))
  cands[!duplicated(keys) & nzchar(keys)]
}

# Track packages staged in this run so co-authored packages don't get PR'd
# twice — first author wins.
staged_in_run <- character(0)

plan <- list()
for (e in new_entries) {
  cands <- tryCatch(
    discover_for(e),
    error = function(err) {
      message("  error for ", e$github, ": ", conditionMessage(err))
      list()
    }
  )

  cands <- Filter(
    function(x) {
      pkg <- tolower(x$package %||% "")
      if (!nzchar(pkg)) return(FALSE)
      if (is_blank(x$title) && is_blank(x$description)) return(FALSE)
      if (pkg %in% existing_pkgs) return(FALSE)
      if (pkg %in% staged_in_run) return(FALSE)
      TRUE
    },
    cands
  )

  trim_msg <- ""
  if (length(cands) > cre_threshold) {
    before <- length(cands)
    cands <- Filter(
      function(x) {
        roles <- trimws(strsplit(
          x$matched_roles %||% "",
          ",",
          fixed = TRUE
        )[[1]])
        "cre" %in% roles
      },
      cands
    )
    trim_msg <- sprintf(
      " [trimmed %d -> %d, cre-only]",
      before,
      length(cands)
    )
  }

  if (length(cands) == 0) {
    if (nzchar(trim_msg)) {
      cat("  ", e$github, "-> 0 candidates", trim_msg, "\n")
    }
    next
  }

  author_dir <- file.path(pending_dir, e$slug)
  dir.create(author_dir, recursive = TRUE, showWarnings = FALSE)

  pkg_names <- character(length(cands))
  for (i in seq_along(cands)) {
    entry <- to_package_shape(cands[[i]], dir_lookup)
    pkg_names[i] <- entry$name
    jsonlite::write_json(
      entry,
      file.path(author_dir, paste0(entry$name, ".json")),
      pretty = TRUE,
      auto_unbox = TRUE,
      na = "null"
    )
  }
  staged_in_run <- c(staged_in_run, tolower(pkg_names))

  plan[[length(plan) + 1]] <- list(
    slug = e$slug,
    name = e$name,
    github = e$github,
    packages = pkg_names
  )

  cat(
    "  ",
    e$github,
    "->",
    length(cands),
    "candidate(s)",
    trim_msg,
    ":",
    paste(pkg_names, collapse = ", "),
    "\n"
  )
}

cat(
  "\n",
  length(plan),
  "authors with candidate packages staged in",
  pending_dir,
  "\n"
)

if (length(plan) == 0) {
  cat("Nothing to PR. Exiting.\n")
  quit(status = 0)
}

manifest_for_json <- lapply(plan, function(p) {
  list(
    slug = p$slug,
    name = p$name,
    github = p$github,
    packages = I(p$packages)
  )
})
jsonlite::write_json(
  manifest_for_json,
  file.path(pending_dir, "_manifest.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)

script_path <- file.path(pending_dir, "_open_prs.sh")
write_open_prs_script(plan, script_path, "discover_directory_packages.R")

cat("Wrote manifest:", file.path(pending_dir, "_manifest.json"), "\n")
cat("Wrote PR script:", script_path, "\n")
cat("\nNext steps:\n")
cat("  1. Review", pending_dir, "/<slug>/*.json\n")
cat(
  "  2. Curate data/packages_pending/_keep.txt and run",
  "scripts/prune_pending_prs.R\n"
)
cat("     (or hand-edit", script_path, "directly)\n")
cat("  3. Run: bash", script_path, "\n")
