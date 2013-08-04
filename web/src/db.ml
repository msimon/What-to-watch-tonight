module type M =
sig

  type t deriving (Bson_ext)
  type key deriving (Bson_ext)

  val collection : string

  val search: key -> Bson.t
  val key: t -> key

end


module type Db =
sig
  type t deriving (Bson_ext)

  val find: t -> t Lwt.t
  (* val query : Bson.t -> t list Lwt.t *)
  val insert: t -> unit Lwt.t
  val update: t -> unit Lwt.t
  val delete: t -> unit Lwt.t
end


module Make (M : M) : Db =
struct

  type t = M.t deriving (Bson_ext)

  module Cache = Ocsigen_cache.Make (struct
      type key = M.key
      type value = t
    end)

  let config = Config.get ()
  (* mongo is Lwt.t lazy.t*)
  let mongo = lazy (Config.(Mongo_lwt.create config.db.ip config.db.port config.db.name M.collection))

  let find_in_db key =
    lwt mongo = Lazy.force mongo in
    let bson_search = M.search key in

    lwt r = Mongo_lwt.find_q_one mongo bson_search in
    let r = List.nth (MongoReply.get_document_list r) 0 in

    Lwt.return (Bson_utils_t.from_bson r)


  let cache = Config.(new Cache.cache find_in_db ~timer:config.cache.cache_timer config.cache.cache_size)

  let find t =
    cache#find (M.key t)

  (* let query bson_t = *)

  let insert t =
    lwt mongo = Lazy.force mongo in
    lwt _ = Mongo_lwt.insert mongo [ Bson_utils_t.to_bson t ] in

    cache#add (M.key t) t;

    Lwt.return_unit


  let update t =
    lwt mongo = Lazy.force mongo in
    lwt _ = Mongo_lwt.update_one mongo ((M.search (M.key t)),(Bson_utils_t.to_bson t)) in

    cache#remove (M.key t) ;
    cache#add (M.key t) t;

    Lwt.return_unit

  let delete t =
    lwt mongo = Lazy.force mongo in
    lwt _ = Mongo_lwt.delete_one mongo (M.search (M.key t)) in

    cache#remove (M.key t) ;

    Lwt.return_unit

end


module User = Make (User_type)
module Movie = Make (Movie_type)
module Gender = Make (Gender_type)
module Rating = Make (Rating_type)
