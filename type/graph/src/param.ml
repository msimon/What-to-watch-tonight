{shared{
  (* n size vector, n = # gender in our case *)
  type t = {
    genre_uid : Uid.genre Uid.uid ;
    value : float ;
  } deriving (Bson_ext)

}}
