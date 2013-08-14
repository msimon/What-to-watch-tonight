
open Eliom_service
open Eliom_parameter

let main = service [ "" ] any ()
let movie = service [ "movie" ] (suffix_prod (int "uid") any) ()
let profile = service [ "profile" ] any ()
let what_to_watch = service [ "what_to_watch" ] any ()
let taste_profile = service [ "taste_profile" ] any ()
let popular_movie = service [ "popular_movies" ] any ()
