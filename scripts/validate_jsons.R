
files <- list.files(
  path = here::here("blogs/"), 
  pattern = "json", 
  full.names = TRUE
)

k <- sapply(
  X = files, 
  FUN = jsonvalidate::json_validate,
  schema = here::here("scripts/.entry_schema.json")
)

names(k) <- basename(names(k))

if(any(!k)){
  wrong <- paste(names(k)[!k], collaspse="\n")
  stop(
    "Some jsons are not formatted correctly\n",
    wrong,
    call. = FALSE
  )
}

