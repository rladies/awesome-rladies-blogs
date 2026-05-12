library(here)

source(here::here("scripts", "discover_helpers.R"))

packages_dir <- here::here("data/packages")
directory_dir <- Sys.getenv(
  "DIRECTORY_DIR",
  here::here("..", "directory", "data", "json")
)

# --- candidate parsing -------------------------------------------------------

# Strip trailing parentheticals like "(maintainer)" or "(contributor)" so the
# core package name(s) survive: "TEQC (maintainer)" -> "TEQC".
strip_parentheticals <- function(s) {
  trimws(gsub("\\s*\\([^)]*\\)", "", s))
}

# Tokens that occasionally show up in keys but are clearly not packages.
non_package_tokens <- c(
  "i", "a", "an", "the", "and", "or", "of", "for", "to", "with",
  "package", "packages", "developed", "called", "co-author", "coauthor",
  "contributor", "maintainer", "author", "co-developer", "developer",
  "core", "team", "part", "many", "related", "personal", "functions",
  "from", "on", "in", "is", "by", "as", "my", "via", "via", "at",
  "rrlogo", "etc", "cran", "github", "bioconductor", "bioc"
)

# Extract package-name tokens out of a free-text key. Splits on commas, " and ",
# semicolons, and slashes, then keeps tokens that look like an R package name
# (alpha-led, alphanumeric+dot, length 2-40), aren't generic stopwords, and
# aren't URLs.
candidate_names_from_text <- function(s) {
  if (is_blank(s)) {
    return(character(0))
  }
  s <- strip_parentheticals(s)
  s <- gsub("\\bhttps?://\\S+", " ", s)
  parts <- unlist(strsplit(s, "\\s*(,| and | & |;|/)\\s*", perl = TRUE))
  tokens <- unlist(lapply(parts, function(p) {
    p <- trimws(p)
    if (!nzchar(p)) return(character(0))
    # If part looks like a clean package name on its own, keep it.
    if (grepl("^[A-Za-z][A-Za-z0-9._]{1,39}$", p)) return(p)
    # Otherwise pull every word-like token out and filter heuristically.
    toks <- regmatches(p, gregexpr("[A-Za-z][A-Za-z0-9._]{1,39}", p))[[1]]
    toks
  }))
  tokens <- unique(tokens)
  tokens <- tokens[!tolower(tokens) %in% non_package_tokens]
  # Drop pure lowercase common-English words by requiring either:
  # - at least one uppercase letter, or a dot, or a digit, OR
  # - the token came from a single-token key (handled above by direct return).
  # Here we keep all tokens; the r-universe/CRAN lookup self-filters bad ones.
  tokens
}

# Pull github owner and repo from a URL value. Owner is useful as an
# r-universe sub-domain hint; repo is a candidate package name.
parse_url_hints <- function(url) {
  if (is_blank(url)) {
    return(list(owners = character(0), repos = character(0), cran = character(0)))
  }
  urls <- unlist(regmatches(url, gregexpr("https?://\\S+", url)))
  owners <- character(0)
  repos <- character(0)
  cran <- character(0)
  for (u in urls) {
    gh <- regmatches(u, regexec("github\\.com/([^/]+)(?:/([^/?#]+))?", u))[[1]]
    if (length(gh) >= 2 && nzchar(gh[2])) {
      owners <- c(owners, sub("\\.git$", "", gh[2]))
    }
    if (length(gh) >= 3 && nzchar(gh[3])) {
      repos <- c(repos, sub("\\.git$", "", gh[3]))
    }
    cm <- regmatches(u, regexec("cran\\.r-project\\.org/(?:web/)?packages?[/=]([A-Za-z0-9._]+)", u))[[1]]
    if (length(cm) >= 2 && nzchar(cm[2])) {
      cran <- c(cran, cm[2])
    }
    rum <- regmatches(u, regexec("([A-Za-z0-9-]+)\\.r-universe\\.dev", u))[[1]]
    if (length(rum) >= 2 && nzchar(rum[2])) {
      owners <- c(owners, rum[2])
    }
  }
  list(owners = unique(owners), repos = unique(repos), cran = unique(cran))
}

extract_candidates <- function(r_packages) {
  out <- list()
  if (length(r_packages) == 0) return(out)
  for (key in names(r_packages)) {
    val <- r_packages[[key]]
    hints <- parse_url_hints(val)
    names_from_key <- candidate_names_from_text(key)
    candidate_set <- unique(c(names_from_key, hints$repos, hints$cran))
    candidate_set <- candidate_set[nzchar(candidate_set)]
    for (cand in candidate_set) {
      out[[length(out) + 1]] <- list(
        package = cand,
        owner_hints = hints$owners,
        url = val,
        raw_key = key
      )
    }
  }
  out
}

# --- lookup pipeline ---------------------------------------------------------

# For self-listed packages, the directory member's slug is authoritative — but
# the package's Author field may use a longer/different name variant (e.g.
# "Leila Marvian Mashhad" vs the directory's "Leila Marvian"), which the
# default by-name lookup misses. Stamp the slug onto the author whose name
# overlaps the directory entry's name by at least two tokens or by substring.
stamp_self_directory_id <- function(authors, slug, dir_name) {
  if (is_blank(slug) || is_blank(dir_name) || length(authors) == 0) {
    return(authors)
  }
  for (a in authors) {
    if (identical(a$directory_id, slug)) return(authors)
  }
  for (i in seq_along(authors)) {
    if (!is.null(authors[[i]]$directory_id)) next
    if (name_in(dir_name, authors[[i]]$name) ||
        name_in(authors[[i]]$name, dir_name) ||
        names_match(dir_name, authors[[i]]$name)) {
      authors[[i]]$directory_id <- slug
      return(authors)
    }
  }
  ntoks <- strsplit(tolower(ascii(dir_name)), "\\s+")[[1]]
  ntoks <- ntoks[nzchar(ntoks)]
  for (i in seq_along(authors)) {
    if (!is.null(authors[[i]]$directory_id)) next
    atoks <- strsplit(tolower(ascii(authors[[i]]$name)), "\\s+")[[1]]
    atoks <- atoks[nzchar(atoks)]
    if (length(intersect(ntoks, atoks)) >= 2) {
      authors[[i]]$directory_id <- slug
      return(authors)
    }
  }
  authors
}

# Self-listed authorship is looser than the broad sweep: the directory member
# explicitly claimed the package, so any aut/cre/ctb attribution counts, and
# we use first/last-token name matching to handle middle-name variants
# (e.g. "Ana Nieto" matching "Ana Belen Nieto Librero").
is_self_listed_authorship <- function(name, author_text, maintainer_text) {
  combined <- paste(maintainer_text %||% "", author_text %||% "")
  if (name_in(name, combined)) return(TRUE)
  parsed <- parse_authors(author_text %||% "")
  for (a in parsed) {
    if (names_match(name, a$name)) return(TRUE)
  }
  m <- parse_maintainer_str(maintainer_text %||% "")
  if (!is.na(m$name) && names_match(name, m$name)) return(TRUE)
  FALSE
}

# Evaluate Authors@R safely in a sandboxed env where `person` and `c` are
# defined, then format each entry into "Given Family <email> [role1, role2]
# (ORCID: 0000-...)" so the existing parse_authors / roles_for / Maintainer
# parsing handles it identically to a normal `Author:` field.
parse_authors_at_r <- function(code) {
  if (is_blank(code)) return(list(author = "", maintainer = ""))
  expr <- tryCatch(
    parse(text = code), error = function(e) NULL
  )
  if (is.null(expr)) return(list(author = "", maintainer = ""))
  env <- new.env(parent = emptyenv())
  env$c <- function(...) list(...)
  env$person <- function(given = NULL, family = NULL, email = NULL,
                         role = NULL, comment = NULL, ...) {
    list(
      given = given, family = family, email = email,
      role = role, comment = comment
    )
  }
  ppl <- tryCatch(eval(expr, envir = env), error = function(e) NULL)
  if (is.null(ppl)) return(list(author = "", maintainer = ""))
  if (!is.null(ppl$given) || !is.null(ppl$family)) ppl <- list(ppl)
  flat <- function(x) {
    if (is.null(x)) return(character(0))
    if (is.list(x) && !is.null(x$given)) return(list(x))
    if (is.list(x)) return(unlist(lapply(x, flat), recursive = FALSE))
    character(0)
  }
  ppl <- flat(ppl)
  fmt_one <- function(p) {
    name <- trimws(paste(c(p$given, p$family), collapse = " "))
    if (!nzchar(name)) return("")
    parts <- name
    if (!is.null(p$email) && nzchar(p$email)) {
      parts <- paste0(parts, " <", p$email, ">")
    }
    if (!is.null(p$role) && length(p$role) > 0) {
      parts <- paste0(parts, " [", paste(p$role, collapse = ", "), "]")
    }
    orcid <- NULL
    if (!is.null(p$comment)) {
      cmt <- p$comment
      if (is.list(cmt) && !is.null(cmt$ORCID)) orcid <- cmt$ORCID
      if (is.character(cmt)) {
        m <- regmatches(cmt, regexpr("\\d{4}-\\d{4}-\\d{4}-\\d{3}[0-9X]", cmt))
        if (length(m)) orcid <- m
      }
    }
    if (!is.null(orcid)) {
      parts <- paste0(parts, " (ORCID: ", orcid, ")")
    }
    parts
  }
  pieces <- vapply(ppl, fmt_one, character(1))
  pieces <- pieces[nzchar(pieces)]
  author <- paste(pieces, collapse = ",\n  ")
  maintainer <- ""
  for (p in ppl) {
    if ("cre" %in% p$role && !is.null(p$email)) {
      maintainer <- sprintf(
        "%s <%s>",
        trimws(paste(c(p$given, p$family), collapse = " ")),
        p$email
      )
      break
    }
  }
  list(author = author, maintainer = maintainer)
}

fetch_text <- function(url, timeout = 8) {
  h <- curl::new_handle()
  curl::handle_setopt(h, followlocation = TRUE, timeout = timeout)
  resp <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  if (is.null(resp) || resp$status_code != 200) return(NULL)
  rawToChar(resp$content)
}

# Pull DESCRIPTION from a github repo and parse as a single-row dcf. Tries
# raw.githubusercontent.com/<owner>/<repo>/HEAD/DESCRIPTION first, then main
# and master. Returns a list shaped like an r-universe / CRAN entry.
fetch_github_description <- function(owner, repo) {
  for (ref in c("HEAD", "main", "master")) {
    url <- sprintf(
      "https://raw.githubusercontent.com/%s/%s/%s/DESCRIPTION", owner, repo, ref
    )
    txt <- fetch_text(url)
    if (is.null(txt)) next
    parsed <- tryCatch(
      read.dcf(textConnection(txt)), error = function(e) NULL
    )
    if (is.null(parsed) || nrow(parsed) == 0) next
    # Use exact column lookup — `fields$Author` partial-matches to "Authors@R"
    # and silently returns the R code instead of the parsed Author string.
    get <- function(field) {
      if (!field %in% colnames(parsed)) return("")
      v <- parsed[1, field]
      if (is.na(v)) "" else as.character(v)
    }
    pkg_url <- get("URL")
    if (is_blank(pkg_url)) {
      pkg_url <- sprintf("https://github.com/%s/%s", owner, repo)
    }
    author <- get("Author")
    maintainer <- get("Maintainer")
    authors_at_r <- get("Authors@R")
    if (is_blank(author) && !is_blank(authors_at_r)) {
      pp <- parse_authors_at_r(authors_at_r)
      author <- pp$author
      if (is_blank(maintainer) && nzchar(pp$maintainer)) {
        maintainer <- pp$maintainer
      }
    }
    pkg_name <- get("Package")
    if (is_blank(pkg_name)) pkg_name <- repo
    return(list(
      Package = pkg_name,
      Title = if (nzchar(get("Title"))) get("Title") else NA_character_,
      Description = if (nzchar(get("Description"))) get("Description") else NA_character_,
      URL = pkg_url,
      BugReports = if (nzchar(get("BugReports"))) get("BugReports") else NA_character_,
      Maintainer = if (nzchar(maintainer)) maintainer else NA_character_,
      Author = author,
      `_owner` = owner,
      `Date/Publication` = NA_character_
    ))
  }
  NULL
}

# Try r-universe/<owner>/<pkg>; fall back to CRAN row; bioconductor mirror;
# finally raw github DESCRIPTION on each candidate owner. Returns the first
# hit with normalised metadata.
lookup_pkg <- function(pkg, owners, cran_db, bioc_db) {
  for (owner in owners) {
    if (is_blank(owner)) next
    p <- tryCatch(fetch_universe_package(owner, pkg), error = function(e) NULL)
    if (!is.null(p) && !is.null(p$Package) && !is_blank(p$Title)) {
      return(list(pkg = p, source = "r-universe"))
    }
  }
  if (!is.null(cran_db)) {
    idx <- which(tolower(cran_db$Package) == tolower(pkg))
    if (length(idx) > 0) {
      row <- cran_db[idx[1], ]
      return(list(pkg = list(
        Package = row$Package,
        Title = row$Title,
        Description = row$Description,
        URL = row$URL,
        BugReports = row$BugReports,
        Maintainer = row$Maintainer,
        Author = row$Author,
        `Date/Publication` = row[["Date/Publication"]]
      ), source = "cran"))
    }
  }
  if (!is.null(bioc_db) && length(bioc_db) > 0) {
    for (p in bioc_db) {
      if (tolower(p$Package %||% "") == tolower(pkg)) {
        return(list(pkg = p, source = "bioconductor"))
      }
    }
  }
  for (owner in owners) {
    if (is_blank(owner)) next
    p <- tryCatch(fetch_github_description(owner, pkg), error = function(e) NULL)
    if (!is.null(p) && !is_blank(p$Title)) {
      return(list(pkg = p, source = "github"))
    }
  }
  NULL
}

# --- main --------------------------------------------------------------------

cat("Reading directory entries from", directory_dir, "\n")
entries <- list()
files <- list.files(directory_dir, pattern = "\\.json$", full.names = TRUE)
for (f in files) {
  e <- tryCatch(jsonlite::read_json(f), error = function(e) NULL)
  if (is.null(e)) next
  rp <- e$activities$r_packages
  if (length(rp) == 0) next
  entries[[length(entries) + 1]] <- list(
    slug = sub("\\.json$", "", basename(f)),
    name = e$name %||% NA_character_,
    github = e$social_media$github %||% NA_character_,
    r_packages = rp
  )
}
cat("  ", length(entries), "directory entries with non-empty r_packages\n")

cat("Building directory lookup\n")
dir_lookup <- build_directory_lookup(directory_dir)

cat("Fetching CRAN package db...\n")
cran_db <- tryCatch(tools::CRAN_package_db(), error = function(e) NULL)
cat("  ", if (is.null(cran_db)) 0 else nrow(cran_db), "CRAN packages\n")

cat("Fetching Bioconductor package db (bioc.r-universe.dev)...\n")
bioc_db <- tryCatch(fetch_bioc_db(), error = function(e) NULL)
cat("  ", if (is.null(bioc_db)) 0 else length(bioc_db), "Bioconductor packages\n")

existing <- tools::file_path_sans_ext(list.files(packages_dir, pattern = "\\.json$"))
existing_lc <- tolower(existing)
cat("  ", length(existing), "packages already in data/packages/\n")

added <- list()
skipped_existing <- list()
unconfirmed <- list()
not_authored <- list()

for (e in entries) {
  cands <- extract_candidates(e$r_packages)
  if (length(cands) == 0) next
  owners_default <- if (!is_blank(e$github)) e$github else NA_character_
  for (c in cands) {
    pkg <- c$package
    if (tolower(pkg) %in% existing_lc) {
      skipped_existing[[length(skipped_existing) + 1]] <- list(
        slug = e$slug, name = e$name, package = pkg, source = "exists"
      )
      next
    }
    owners <- unique(c(c$owner_hints, owners_default))
    owners <- owners[!is.na(owners) & nzchar(owners)]
    hit <- lookup_pkg(pkg, owners, cran_db, bioc_db)
    if (is.null(hit)) {
      unconfirmed[[length(unconfirmed) + 1]] <- list(
        slug = e$slug, name = e$name, package = pkg, raw = c$raw_key
      )
      next
    }
    p <- hit$pkg
    if (!is_self_listed_authorship(e$name, p$Author %||% "", p$Maintainer %||% "")) {
      not_authored[[length(not_authored) + 1]] <- list(
        slug = e$slug, name = e$name, package = pkg,
        author = p$Author, source = hit$source
      )
      next
    }
    roles <- roles_for(e$name, p$Author %||% "")
    if (length(roles) == 0) roles <- "unknown"
    cand <- normalise_pkg(
      p, hit$source, e$name, e$github, paste(roles, collapse = ",")
    )
    entry <- to_package_shape(cand, dir_lookup)
    entry$authors <- stamp_self_directory_id(entry$authors, e$slug, e$name)
    path <- write_pkg(entry, packages_dir)
    added[[length(added) + 1]] <- list(
      slug = e$slug, name = e$name, package = entry$name,
      source = hit$source, path = path
    )
    existing_lc <- c(existing_lc, tolower(entry$name))
    cat("  + added", entry$name, "for", e$slug, "(", hit$source, ")\n")
  }
}

cat("\n--- summary ---\n")
cat("Added         :", length(added), "\n")
cat("Already in repo:", length(skipped_existing), "\n")
cat("Not found     :", length(unconfirmed), "\n")
cat("Not authored  :", length(not_authored), "\n")

write_report <- function(rows, path) {
  if (length(rows) == 0) {
    writeLines(character(0), path)
    return(invisible())
  }
  df <- do.call(rbind, lapply(rows, function(r) {
    data.frame(lapply(r, function(x) if (is.null(x)) NA else as.character(x)),
               stringsAsFactors = FALSE)
  }))
  write.table(df, path, sep = "\t", row.names = FALSE, quote = FALSE)
}

report_dir <- here::here("data/packages_pending")
if (!dir.exists(report_dir)) dir.create(report_dir, recursive = TRUE)
write_report(added, file.path(report_dir, "_listed_added.tsv"))
write_report(skipped_existing, file.path(report_dir, "_listed_skipped.tsv"))
write_report(unconfirmed, file.path(report_dir, "_listed_unconfirmed.tsv"))
write_report(not_authored, file.path(report_dir, "_listed_not_authored.tsv"))

cat("\nReports written under", report_dir, "\n")
