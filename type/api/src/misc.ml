type image_conf = {
  base_url : string;
  secure_base_url : string ;
  poster_sizes : string list ;
  backdrop_sizes : string list ;
  profile_sizes : string list ;
  logo_sizes : string list ;
} deriving (Json_ext)

type movidb_configuration = {
  images : image_conf ;
  change_keys : string list ;
} deriving (Json_ext)

type error = {
  status_code : string ;
  status_message: string ;
} deriving (Json_ext)
