library(httr2)

jfiles <- list.files(here::here("blogs"), "json$", full.names = TRUE)
jcontent <- lapply(jfiles, jsonlite::read_json)
names(jcontent) <- basename(jfiles)


check_image <- function(x){
  if("photo_url" %in% names(x)){
    url_info <- request(x$photo_url) |> 
      req_error(is_error = function(x){FALSE}) |> 
      req_perform()

    exists   <- resp_status(url_info) == 200
    if(!exists){
      message(sprintf("%s: photo url returns http status '%s': %s", 
        x$url, resp_status(url_info), x$photo_url))
      return(FALSE)
    }

    is_image <- grepl("image", resp_content_type(url_info))
    if(!is_image){
      message(sprintf("%s: photo url does not return an image: %s", 
        x$url, x$photo_url))
      return(FALSE)
    }

    return(all(exists, is_image))
  }
}

images <- sapply(jcontent, check_image, USE.NAMES = TRUE) |> 
  unlist()

missing_images <- images[!images]

if(any(!missing_images)){
  stop("There are images in the data that don't return correctly. See build log for more details.", call. = FALSE)
}
