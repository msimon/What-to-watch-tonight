{shared{
  type key = Uid.user Uid.uid deriving (Bson_ext)

  (* n size vector, n = # gender in our case *)
  type param = {
    gender_uid : int ;
    value : float ;
  } deriving (Bson_ext)

  type t = {
    uid: key ;
    name: string ;
    ratings: int list ;
    vector : param list ;
  } deriving (Bson_ext)
}}

let collection = "users"

let search uid =
  let uid = Uid.get_uid_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid
