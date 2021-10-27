validate_jsons <- function(files, schema){
  validate <- jsonvalidate::json_validator(
    schema)
  k <- sapply(files, validate, 
              verbose = TRUE, 
              error = TRUE, 
              greedy = TRUE)
}


#  Validate blog json
validate_jsons(
  list.files(
    path = here::here("blogs"), 
    full.names = TRUE
  ),
  here::here("scripts/.entry_schema.json")
)


