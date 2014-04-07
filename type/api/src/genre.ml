type t = {
  id: int ;
  name: string ;
} deriving (Yojson, Bson_ext)

type genre_list = {
  genres : t list;
} deriving (Yojson, Bson_ext)
