validate_jsons <- function(files, schema) {
  validate <- jsonvalidate::json_validator(
    schema
  )
  k <- sapply(files, validate, verbose = TRUE, error = TRUE, greedy = TRUE)
}

files <- list.files(
  path = here::here("content"),
  full.names = TRUE
)
ext <- grep("json$", files, invert = TRUE)
if (length(ext) > 0) {
  stop(
    "File has wrong extention. Please rename to end with 'json'\n",
    paste0(
      basename(files[grep("json$", files, invert = TRUE)]),
      collapse = "\n"
    ),
    call. = FALSE
  )
}

#  Validate content json
validate_jsons(
  files,
  here::here("scripts/json_schema/content.json")
)

#  Validate packages json
validate_jsons(
  files,
  here::here("scripts/json_schema/packages.json")
)
