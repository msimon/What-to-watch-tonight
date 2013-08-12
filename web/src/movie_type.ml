{shared{
  type key = Uid.movie Uid.uid deriving (Bson_ext)

  (* n size vector, n = # gender in our case *)
  type param = {
    genres_uid : Uid.genre Uid.uid ;
    value : float ;
  } deriving (Bson_ext)

  type t = {
    uid: key ;
    title: string ;
    original_title : string option ;
    overview : string option ;
    poster_path : string option ;
    release_date: string ;
    tagline : string option ;
    vote_average : float ;
    vote_count : int ;
    genres : Uid.genre Uid.uid list ;
    vector : param list ;
  } deriving (Bson_ext)
}}

let collection = "movies"
let uid_field = "uid"
type uid_typ = Uid.movie
let uid_typ = Uid.Movie

let search uid =
  let uid = Uid.get_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid

let indexes () =
  let uid = ("uid",[ Mongo_lwt.Unique true ]) in
  let vote_average = ("vote_average",[]) in
  let vote_count = ("vote_count",[]) in

  [ uid; vote_average; vote_count ]
