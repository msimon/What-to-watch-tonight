{shared{
  type key = Uid.user Uid.uid deriving (Bson_ext)

  type facebook = {
    facebook_uid : string ;
    facebook_access_token : string ;
    facebook_access_token_expire_on : int64 ;
  } deriving (Bson_ext)

  type t = {
    uid: key ;
    name: string ;
    ratings: Uid.rating Uid.uid list ;
    facebook : facebook option ;
    vector : Param.t list ;
  } deriving (Bson_ext)
}}

let collection = "users"
let uid_field = "uid"
type uid_typ = Uid.user
let uid_typ = Uid.User

let search uid =
  let uid = Uid.get_value uid in
  Bson.add_element "uid" (Bson.create_int64 (Int64.of_int uid)) Bson.empty

let key t = t.uid

let indexes () =
  let uid = (["uid"],[ Mongo_lwt.Unique true ]) in
  let fb_uid = (["facebook.facebook_uid"],[ Mongo_lwt.Unique true ]) in

  [ uid; fb_uid ]

let bson_uid (key : Uid.user Uid.uid) =
  Bson.create_int64 (Int64.of_int (Uid.get_value key))
