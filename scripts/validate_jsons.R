
files <- list.files(
  path = here::here("blogs/"), 
  pattern = "json", 
  full.names = TRUE
)

catch_error <- function(x){
  tryCatch(
    jsonvalidate::json_validate(
      x,
      error = TRUE,
      schema = here::here("scripts/.entry_schema.json")
    ),
    error = function(e) e
  )
}

k <- sapply(files, catch_error)
k <- k[!sapply(k, is.null)]
names(k) <- basename(names(k))
k <- sapply(1:length(k), 
            function(x) 
              sprintf("%s: %s", 
                      names(k)[x], 
                      k[[x]]$message
              )
)

if(length(k) > 0){
  stop(
    "Some jsons are not formatted correctly\n",
    paste(k, collapse = "\n"),
    call. = FALSE
  )
}

