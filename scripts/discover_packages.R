library(jsonlite)
library(here)

content_dir <- here::here("data/content")
packages_dir <- here::here("data/packages")
directory_dir <- here::here("..", "directory", "data", "json")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

ascii <- function(x) {
  if (length(x) == 0) return(character(0))
  iconv(x, to = "ASCII//TRANSLIT", sub = "")
}

is_blank <- function(x) {
  is.null(x) || length(x) == 0 || all(is.na(x)) || !nzchar(trimws(paste(x, collapse = "")))
}

read_authors <- function(dir) {
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  out <- list()
  for (f in files) {
    blog <- jsonlite::read_json(f)
    for (a in blog$authors %||% list()) {
      sm <- a$social_media[[1]] %||% list()
      out[[length(out) + 1]] <- list(
        name = a$name,
        github = sm$github %||% NA_character_,
        orcid = sm$orcid %||% NA_character_,
        blog = blog$url
      )
    }
  }
  out
}

# Build a name/handle -> directory slug lookup from the sibling rladies/directory
# repo. The slug (filename minus .json) is the canonical directory_id.
build_directory_lookup <- function(dir) {
  if (!dir.exists(dir)) {
    message("Directory repo not found at ", normalizePath(dir, mustWork = FALSE),
            " — directory_id lookup will be skipped.")
    return(list(by_handle = list(), by_name = list()))
  }
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  by_handle <- list()
  by_name <- list()
  for (f in files) {
    entry <- tryCatch(jsonlite::read_json(f), error = function(e) NULL)
    if (is.null(entry)) next
    id <- sub("\\.json$", "", basename(f))
    gh <- entry$social_media$github
    if (!is_blank(gh)) by_handle[[tolower(trimws(gh))]] <- id
    if (!is_blank(entry$name)) {
      by_name[[tolower(trimws(ascii(entry$name)))]] <- id
    }
  }
  message("Loaded ", length(files), " directory entries from ", dir)
  list(by_handle = by_handle, by_name = by_name)
}

lookup_directory_id <- function(name, github, dir_lookup) {
  if (!is_blank(github)) {
    h <- tolower(trimws(github))
    if (!is.null(dir_lookup$by_handle[[h]])) return(dir_lookup$by_handle[[h]])
  }
  if (!is_blank(name)) {
    n <- tolower(trimws(ascii(name)))
    if (!is.null(dir_lookup$by_name[[n]])) return(dir_lookup$by_name[[n]])
  }
  NA_character_
}

to_iso_date <- function(s) {
  if (is_blank(s)) return(NA_character_)
  m <- regmatches(s, regexpr("\\d{4}-\\d{2}-\\d{2}", s))
  if (length(m) == 0) NA_character_ else m
}

universe_url <- function(handle) {
  sprintf(
    "https://%s.r-universe.dev/api/packages?fields=Package,Title,Description,URL,BugReports,Maintainer,Author,_owner,Date/Publication,_published",
    tolower(handle)
  )
}

fetch_universe <- function(handle) {
  url <- universe_url(handle)
  con <- curl::curl(url)
  on.exit(close(con), add = TRUE)
  resp <- tryCatch(readLines(con, warn = FALSE), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  txt <- paste(resp, collapse = "\n")
  if (!nzchar(txt) || startsWith(txt, "{")) return(NULL)
  tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
           error = function(e) NULL)
}

fetch_universe_package <- function(owner, pkg) {
  url <- sprintf(
    "https://%s.r-universe.dev/api/packages/%s?fields=Package,Title,Description,URL,BugReports,Maintainer,Author,_owner,Date/Publication,_published",
    tolower(owner), pkg
  )
  con <- curl::curl(url)
  on.exit(close(con), add = TRUE)
  resp <- tryCatch(readLines(con, warn = FALSE), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  tryCatch(jsonlite::fromJSON(paste(resp, collapse = "\n"), simplifyVector = FALSE),
           error = function(e) NULL)
}

# HEAD probe pkgdown standard logo paths. Returns the first 200 URL or NA.
probe_logo_url <- function(pkdown_url) {
  if (is_blank(pkdown_url)) return(NA_character_)
  base <- sub("/+$", "", pkdown_url)
  candidates <- c(
    paste0(base, "/logo.png"),
    paste0(base, "/logo.svg"),
    paste0(base, "/reference/figures/logo.png"),
    paste0(base, "/reference/figures/logo.svg")
  )
  for (u in candidates) {
    h <- curl::new_handle()
    curl::handle_setopt(h, customrequest = "HEAD", nobody = TRUE,
                        followlocation = TRUE, timeout = 5)
    resp <- tryCatch(curl::curl_fetch_memory(u, handle = h),
                     error = function(e) NULL)
    if (!is.null(resp) && resp$status_code == 200) return(u)
  }
  NA_character_
}

owner_match <- function(pkg, handle) {
  isTRUE(tolower(pkg$`_owner` %||% "") == tolower(handle))
}

name_in <- function(needle, haystack) {
  if (is_blank(needle) || is_blank(haystack)) return(FALSE)
  grepl(tolower(ascii(needle)), tolower(ascii(haystack)), fixed = TRUE)
}

accepted_roles <- c("cre", "aut")

roles_for <- function(name, author_text) {
  if (is_blank(author_text)) return("unknown")
  hay <- tolower(ascii(author_text))
  needle <- tolower(ascii(name))
  pos <- regexpr(needle, hay, fixed = TRUE)
  if (pos == -1) return(character(0))
  tail <- substr(hay, pos + attr(pos, "match.length"), nchar(hay))
  m <- regmatches(tail, regexpr("\\s*\\[([^]]+)\\]", tail))
  if (length(m) == 0) return("unknown")
  inside <- sub("^\\s*\\[", "", sub("\\]$", "", m))
  trimws(strsplit(inside, ",")[[1]])
}

is_authorship <- function(name, author_text, maintainer_text) {
  if (name_in(name, maintainer_text)) return(TRUE)
  r <- roles_for(name, author_text)
  if (identical(r, "unknown")) return(TRUE)
  any(r %in% accepted_roles)
}

split_author_entries <- function(text) {
  s <- gsub("\\s+", " ", text)
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  if (length(chars) == 0) return(character(0))
  depth_b <- 0L
  depth_p <- 0L
  cuts <- integer(0)
  for (i in seq_along(chars)) {
    ch <- chars[i]
    if (ch == "[") depth_b <- depth_b + 1L
    else if (ch == "]") depth_b <- max(depth_b - 1L, 0L)
    else if (ch == "(") depth_p <- depth_p + 1L
    else if (ch == ")") depth_p <- max(depth_p - 1L, 0L)
    else if (ch == "," && depth_b == 0L && depth_p == 0L) cuts <- c(cuts, i)
  }
  starts <- c(1L, cuts + 1L)
  ends <- c(cuts - 1L, length(chars))
  parts <- vapply(seq_along(starts), function(k) {
    paste(chars[starts[k]:ends[k]], collapse = "")
  }, character(1))
  trimws(parts[nzchar(trimws(parts))])
}

parse_authors <- function(text) {
  if (is_blank(text)) return(list())
  parts <- split_author_entries(text)
  lapply(parts, function(p) {
    roles_m <- regmatches(p, regexpr("\\[([^]]*)\\]", p))
    roles <- if (length(roles_m) > 0) {
      trimws(strsplit(gsub("^\\[|\\]$", "", roles_m), ",")[[1]])
    } else {
      character(0)
    }
    orcid_m <- regmatches(p, regexpr("\\d{4}-\\d{4}-\\d{4}-\\d{3}[0-9X]", p, perl = TRUE))
    orcid <- if (length(orcid_m) > 0) orcid_m else NA_character_
    boundary <- regexpr("[\\[\\(]", p, perl = TRUE)
    name <- if (boundary > 0) trimws(substr(p, 1, boundary - 1)) else trimws(p)
    list(name = name, roles = as.list(roles), orcid = orcid)
  })
}

parse_pkg_urls <- function(url_str) {
  if (is_blank(url_str)) {
    return(list(repo_url = NA_character_, pkdown_url = NA_character_, other = list()))
  }
  parts <- trimws(unlist(strsplit(url_str, "[,\n]")))
  parts <- parts[nzchar(parts)]
  is_gh <- grepl("github\\.com|gitlab\\.com|codeberg\\.org", parts)
  list(
    repo_url = if (any(is_gh)) parts[which(is_gh)[1]] else NA_character_,
    pkdown_url = if (any(!is_gh)) parts[which(!is_gh)[1]] else NA_character_,
    other = as.list(c(parts[is_gh][-1], parts[!is_gh][-1]))
  )
}

parse_maintainer_str <- function(m) {
  if (is_blank(m)) return(list(name = NA_character_, email = NA_character_))
  email_m <- regmatches(m, regexpr("<([^>]+)>", m))
  email <- if (length(email_m) > 0) gsub("[<>]", "", email_m) else NA_character_
  name <- trimws(sub("\\s*<[^>]*>\\s*$", "", m))
  list(name = name, email = email)
}

# Build a single person entry (name, roles, orcid, directory_id). Used for
# both `authors` and `maintainers` arrays. Maintainer-specific fields like
# `email` are added by the caller.
person_entry <- function(person, dir_lookup) {
  out <- list(name = person$name)
  if (length(person$roles) > 0) out$roles <- person$roles
  if (!is_blank(person$orcid)) out$orcid <- person$orcid
  did <- lookup_directory_id(person$name, NA, dir_lookup)
  if (!is.na(did)) out$directory_id <- did
  out
}

to_package_shape <- function(cand, dir_lookup) {
  urls <- parse_pkg_urls(cand$url)
  m <- parse_maintainer_str(cand$maintainer)

  repo_url <- urls$repo_url
  if (is.na(repo_url) && !is_blank(cand$repo_owner) && !is_blank(cand$package)) {
    repo_url <- sprintf("https://github.com/%s/%s", cand$repo_owner, cand$package)
  }
  if (is.na(repo_url) && !is_blank(cand$bug_reports)) {
    repo_url <- sub("/issues/?$", "", cand$bug_reports)
  }

  parsed <- cand$authors
  # Some old DESCRIPTION fields are role-less; if we know who the maintainer is
  # from the Maintainer field but they're missing from Author, inject them.
  has_cre <- any(vapply(parsed, function(a) "cre" %in% unlist(a$roles), logical(1)))
  if (!has_cre && !is.na(m$name)) {
    parsed <- c(parsed, list(list(name = m$name, roles = list("cre"),
                                  orcid = NA_character_)))
  }

  authors <- lapply(parsed, function(a) {
    entry <- person_entry(a, dir_lookup)
    if (!is.na(m$email) && name_in(a$name, m$name)) {
      entry$email <- m$email
    }
    entry
  })

  logo_url <- probe_logo_url(urls$pkdown_url)

  list(
    name = cand$package,
    title = str_or_na(cand$title),
    description = str_or_na(cand$description),
    repo_url = str_or_na(repo_url),
    pkdown_url = str_or_na(urls$pkdown_url),
    bug_reports_url = str_or_na(cand$bug_reports),
    logo_url = str_or_na(logo_url),
    last_updated = str_or_na(cand$last_updated),
    authors = authors
  )
}

merge_pkg <- function(existing, new) {
  if (length(existing) == 0) return(new)
  scalar_fields <- c("name", "title", "description", "repo_url", "pkdown_url",
                     "bug_reports_url", "logo_url", "last_updated")
  for (f in scalar_fields) {
    if (is_blank(existing[[f]]) && !is_blank(new[[f]])) {
      existing[[f]] <- new[[f]]
    }
  }
  if (is_blank(existing$authors) && length(new$authors) > 0) {
    existing$authors <- new$authors
  }
  existing
}

write_pkg <- function(entry, dir) {
  path <- file.path(dir, paste0(entry$name, ".json"))
  existing <- if (file.exists(path)) jsonlite::read_json(path) else list()
  merged <- merge_pkg(existing, entry)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  jsonlite::write_json(merged, path, pretty = TRUE, auto_unbox = TRUE, na = "null")
}

str_or_na <- function(x) {
  if (is_blank(x)) NA_character_ else as.character(x)
}

normalise_pkg <- function(pkg, source, matched_author, handle = NA, roles = NULL) {
  desc <- str_or_na(pkg$Description)
  if (!is.na(desc)) desc <- trimws(gsub("\\s+", " ", desc))
  last_updated <- to_iso_date(pkg$`Date/Publication`) %||% to_iso_date(pkg$`_published`)
  list(
    package = str_or_na(pkg$Package),
    title = str_or_na(pkg$Title),
    description = desc,
    repo_owner = str_or_na(pkg$`_owner`),
    url = str_or_na(pkg$URL),
    bug_reports = str_or_na(pkg$BugReports),
    maintainer = str_or_na(pkg$Maintainer),
    last_updated = last_updated,
    authors = parse_authors(pkg$Author),
    matched_author = matched_author,
    matched_handle = handle,
    matched_roles = roles %||% NA_character_,
    source = source
  )
}

# ---- Pipeline ---------------------------------------------------------------

cat("Loading author list from", content_dir, "\n")
authors <- read_authors(content_dir)
cat("  found", length(authors), "author entries\n")

cat("Building R-Ladies directory lookup from", directory_dir, "\n")
dir_lookup <- build_directory_lookup(directory_dir)
cat("  ", length(dir_lookup$by_handle), "github handles, ",
    length(dir_lookup$by_name), "names indexed\n")

candidates <- list()

cat("Querying R-universe per author...\n")
for (a in authors) {
  if (is.na(a$github)) next
  pkgs <- fetch_universe(a$github)
  if (is.null(pkgs) || length(pkgs) == 0) next
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
  cat("  ", a$github, "->", length(pkgs), "in universe\n")
}

cat("Fetching CRAN package db...\n")
cran <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
if (!is.null(cran)) {
  cat("  ", nrow(cran), "CRAN packages\n")
  for (a in authors) {
    hits <- which(
      vapply(cran$Author,    function(s) name_in(a$name, s), logical(1)) |
      vapply(cran$Maintainer,function(s) name_in(a$name, s), logical(1))
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
}

cat("Total raw candidate rows:", length(candidates), "\n")
dedup_key <- vapply(candidates, function(x) tolower(x$package %||% ""), character(1))
candidates <- candidates[!duplicated(dedup_key) & nzchar(dedup_key)]
cat("After dedupe by package name:", length(candidates), "\n")

# Drop entries where the package failed to build in r-universe (no title and
# no description means we have nothing usable).
candidates <- Filter(function(x) !(is_blank(x$title) && is_blank(x$description)),
                     candidates)
cat("After dropping unbuilt packages:", length(candidates), "\n")

cat("Writing per-package files to", packages_dir, "\n")
for (cand in candidates) {
  entry <- to_package_shape(cand, dir_lookup)
  write_pkg(entry, packages_dir)
}

cat("Enriching meetupr from rladies r-universe...\n")
mp <- fetch_universe_package("rladies", "meetupr")
if (!is.null(mp) && !is.null(mp$Package)) {
  cand_mp <- normalise_pkg(mp, "r-universe", "R-Ladies Global", "rladies", "cph")
  entry_mp <- to_package_shape(cand_mp, dir_lookup)
  write_pkg(entry_mp, packages_dir)
  cat("  meetupr updated\n")
} else {
  cat("  could not fetch meetupr metadata\n")
}

cat("Done.", length(candidates), "candidate package files written (+meetupr).\n")
