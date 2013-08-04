{shared{
  type key = Uid.gender Uid.uid deriving (Bson_ext)

  type t = {
    uid: key ;
    name: string ;
  } deriving (Bson_ext)
}}

let collection = "gender"

let search uid =
  let uid = Uid.get_uid_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid
