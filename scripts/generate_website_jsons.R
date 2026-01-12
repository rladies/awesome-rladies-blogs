library(jsonlite)
library(here)

# Utility: read all JSON files from a directory and return a list
read_json_dir <- function(dir) {
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0) {
    return(list())
  }
  lapply(files, jsonlite::read_json)
}

# Utility: write a list/object to JSON, ensuring the parent directory exists
write_json <- function(obj, path) {
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    dir.create(parent, recursive = TRUE)
  }
  jsonlite::write_json(obj, path, pretty = TRUE, auto_unbox = TRUE)
}

# Aggregate a directory of JSONs into a single JSON file
aggregate_dir <- function(input_dir) {
  if (!dir.exists(input_dir)) {
    # create empty output so consumers don't break
    write_json(list(), output_file)
    return(invisible(list()))
  }

  name <- basename(input_dir)

  items <- read_json_dir(input_dir)
  write_json(
    items,
    here::here("data/website", paste0("awesome_", name, ".json"))
  )
  invisible(items)
}

# Aggregate blog JSONs
here::here("data/content") |>
  aggregate_dir()

# Aggregate package JSONs
here::here("data/packages") |>
  aggregate_dir()
