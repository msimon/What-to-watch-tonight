{shared{
  type key = Uid.rating Uid.uid deriving (Bson_ext)

  type t = {
    uid: key ;
    user_uid: Uid.user Uid.uid;
    movie_uid: Uid.movie Uid.uid;
    ratings: int ;
  } deriving (Bson_ext)
}}

let collection = "ratings"

let search uid =
  let uid = Uid.get_uid_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid
