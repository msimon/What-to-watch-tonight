type t = {
  id: int ;
  name: string ;
} deriving (Json_ext, Bson_ext)

type genre_list = {
  genres : t list;
} deriving (Json_ext, Bson_ext)
