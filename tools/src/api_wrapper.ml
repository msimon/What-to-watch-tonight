type poster_sizes =
  | W92
  | W154
  | W185
  | W342
  | W500
  | Original
      deriving (Json_ext)

type backdrop_sizes =
  | W300
  | W780
  | W1280
  | Original
      deriving (Json_ext)

type image_conf = {
  base_url : string;
  secure_base_url : string ;
  poster_sizes : poster_sizes ;
  backdrop_sizes : backdrop_sizes ;
} deriving (Json_ext)

type movidb_configuration = {
  images : image_conf ;
} deriving (Json_ext)

let _ =
  let config = Config.init () in
  Printf.printf "api : %s, mock: %s, key: %s\n%!" config.Config.api_url config.Config.mock_api config.Config.api_key
