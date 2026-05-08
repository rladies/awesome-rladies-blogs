library(here)
library(jsonlite)

source(here::here("scripts", "discover_helpers.R"))

pending_dir <- here::here("data/packages_pending")
manifest_path <- file.path(pending_dir, "_manifest.json")
keep_path <- file.path(pending_dir, "_keep.txt")
script_path <- file.path(pending_dir, "_open_prs.sh")

if (!file.exists(manifest_path)) {
  stop(
    "No manifest at ",
    manifest_path,
    ". Run scripts/discover_directory_packages.R first."
  )
}

if (!file.exists(keep_path)) {
  cat(
    "No _keep.txt found. Writing a starter file you can edit:\n  ",
    keep_path,
    "\n"
  )
  writeLines(
    c(
      "# One slug per line. Lines starting with # are comments.",
      "# Bare slug → keep all packages for that author.",
      "# slug: pkg1, pkg2 → keep only the listed packages for that author.",
      "#",
      "# Examples:",
      "# adriana-robles",
      "# jenny-bryan: gapminder, repurrrsive, gargle, googledrive, googlesheets4, gmailr, reprex"
    ),
    keep_path
  )
  cat(
    "Edit it, then re-run: Rscript scripts/prune_pending_prs.R\n"
  )
  quit(status = 0)
}

manifest <- jsonlite::read_json(manifest_path)
manifest_by_slug <- setNames(manifest, vapply(manifest, function(m) m$slug, character(1)))

raw_lines <- readLines(keep_path, warn = FALSE)
clean_lines <- trimws(sub("#.*$", "", raw_lines))
clean_lines <- clean_lines[nzchar(clean_lines)]

parse_keep_line <- function(line) {
  if (grepl(":", line, fixed = TRUE)) {
    halves <- trimws(strsplit(line, ":", fixed = TRUE)[[1]])
    pkgs <- trimws(strsplit(halves[2], ",", fixed = TRUE)[[1]])
    list(slug = halves[1], packages = pkgs[nzchar(pkgs)])
  } else {
    list(slug = line, packages = NULL)
  }
}

keep_specs <- lapply(clean_lines, parse_keep_line)

plan <- list()
missing <- character(0)
unknown_pkgs <- list()

for (spec in keep_specs) {
  entry <- manifest_by_slug[[spec$slug]]
  if (is.null(entry)) {
    missing <- c(missing, spec$slug)
    next
  }
  available <- unlist(entry$packages)
  if (is.null(spec$packages)) {
    selected <- available
  } else {
    selected <- intersect(spec$packages, available)
    bad <- setdiff(spec$packages, available)
    if (length(bad) > 0) {
      unknown_pkgs[[spec$slug]] <- bad
    }
  }
  if (length(selected) == 0) {
    next
  }
  plan[[length(plan) + 1]] <- list(
    slug = entry$slug,
    name = entry$name,
    github = entry$github,
    packages = selected
  )
}

if (length(missing) > 0) {
  message(
    "Slugs not in manifest (typo or already pruned?): ",
    paste(missing, collapse = ", ")
  )
}
for (slug in names(unknown_pkgs)) {
  message(
    "  ",
    slug,
    ": these packages aren't in the manifest and were dropped: ",
    paste(unknown_pkgs[[slug]], collapse = ", ")
  )
}

if (length(plan) == 0) {
  cat("No authors selected. Aborting without overwriting", script_path, "\n")
  quit(status = 0)
}

write_open_prs_script(plan, script_path, "prune_pending_prs.R")

total_pkgs <- sum(vapply(plan, function(p) length(p$packages), integer(1)))
cat(
  "Pruned to",
  length(plan),
  "author(s) /",
  total_pkgs,
  "package(s).\n"
)
cat("Wrote PR script:", script_path, "\n")
cat("Run: bash", script_path, "\n")
