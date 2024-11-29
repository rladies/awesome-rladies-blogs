library(httr2)
library(rvest)
library(jsonlite)

extract_opengraph_info <- function(url) {
  # Fetch webpage content
  response <- request(url) |>
    req_perform()
  
  # Parse the webpage content
  content <- response |> resp_body_string()
  html <- read_html(content)

  # Extract Open Graph tags
  og_tags <- html |>
    html_nodes(xpath = '//meta[starts-with(@property, "og:")]')

  # Extract the properties and their content
  og_info <- lapply(og_tags, function(tag) {
    html_attr(tag, "content")
  })
  names(og_info) <- sapply(og_tags, function(tag){
    gsub("og:", "", html_attr(tag, "property"))
  })
  og_info
}

add_og_info <- function(path){
  jsoncontent <- jsonlite::read_json(path)

  if(jsoncontent$type == "blog"){
    jsoncontent$opengraph <- extract_opengraph_info(jsoncontent$url)
    jsonlite::write_json(
      jsoncontent, 
      path, 
      auto_unbox = TRUE,
      pretty = TRUE
    )
  }
}

fileslist <- list.files(
  here::here("blogs/"), 
  pattern = "json$",
  full.names = TRUE
)

lapply(fileslist, add_og_info)
