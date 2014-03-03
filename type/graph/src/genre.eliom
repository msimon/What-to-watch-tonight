{shared{
  type key = Uid.genre Uid.uid deriving (Bson_ext)

  type t = {
    uid: key ;
    name: string ;
  } deriving (Bson_ext)
}}

let collection = "genres"
let uid_field = "uid"
type uid_typ = Uid.genre
let uid_typ = Uid.Genre

let forbiden_update = []

let search uid =
  let uid = Uid.get_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid

let indexes () =
  [(["uid"],[ Mongo_lwt.Unique true ])]

let bson_uid (key : key) =
  Bson.create_int64 (Int64.of_int (Uid.get_value key))

let uid_to_int = Uid.get_value

let get_last_time_fetch _ = None
let set_last_time_fetch t _ = t
