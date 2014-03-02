{shared{
  type key = Uid.movie Uid.uid deriving (Json, Bson_ext)

  type t = {
    uid: key ;
    title: string ;
    original_title : string option ;
    overview : string option ;
    poster_path : string option ;
    release_date: int option ;
    tagline : string option ;
    vote_average : float ;
    vote_count : int ;
    title_search: string list ; (* title_search is only present here for the database, not for direct use *)
    genres : Uid.genre Uid.uid list ;
    vector : Param.t list ;
    imdb_uid: int ;
  } deriving (Bson_ext)
}}

let collection = "movies"
let uid_field = "uid"
type uid_typ = Uid.movie
let uid_typ = Uid.Movie

let forbiden_update = [
  "vector";
  "title_search"
]

let search uid =
  let uid = Uid.get_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid

let indexes () =
  let uid = (["uid"],[ Mongo_lwt.Unique true ]) in
  let imdb_uid = (["imdb_uid"], [Mongo_lwt.Unique true; Mongo_lwt.DropDups true]) in
  let vote_average = (["vote_average"],[]) in
  let vote_count = (["vote_count"],[]) in
  let title_index = (["title_search"], []) in

  [ uid; imdb_uid; vote_average; vote_count; title_index ]

let bson_uid (key : key) =
  Bson.create_int64 (Int64.of_int (Uid.get_value key))

let uid_to_int = Uid.get_value
