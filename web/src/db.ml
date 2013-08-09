module type M =
sig

  type t deriving (Bson_ext)
  type key deriving (Bson_ext)

  val collection : string

  val search: key -> Bson.t
  val key: t -> key

end

module type Make =
  functor (M : M) ->
  sig
    type t = M.t deriving (Bson_ext)
    type key = M.key

    val find: key -> t Lwt.t
    val query : ?limit:int -> ?full:bool -> Bson.t -> t list Lwt.t
    val insert: t -> unit Lwt.t
    val update: t -> unit Lwt.t
    val delete: t -> unit Lwt.t
end

module Make (M : M) =
struct

  type t = M.t deriving (Bson_ext)

  module Cache = Ocsigen_cache.Make (struct
      type key = M.key
      type value = t
    end)

  (* mongo is Lwt.t lazy.t*)
  let mongo = lazy (
    Balsa_config.(Mongo_lwt.create (get_string "db.ip") (get_int "db.port") (get_string "db.name")  M.collection)
  )

  let find_in_db key =
    lwt mongo = Lazy.force mongo in
    let bson_search = M.search key in

    lwt r = Mongo_lwt.find_q_one mongo bson_search in
    let d = List.nth (MongoReply.get_document_list r) 0 in

    Lwt.return (Bson_utils_t.from_bson d)

  let cache = Balsa_config.(new Cache.cache find_in_db ~timer:(get_float "cache.cache_timer") (get_int "cache.cache_size"))

  let find key =
    cache#find key

  let query ?limit ?(full=false) bson_t =
    lwt mongo = Lazy.force mongo in
    lwt r =
      match limit with
        | Some l -> Mongo_lwt.find_q_of_num mongo bson_t l
        | None -> Mongo_lwt.find_q mongo bson_t
    in

    let fetch_one_batch ?(acc=[]) r =
      let ds = MongoReply.get_document_list r in
      List.fold_left (
        fun acc d ->
          (Bson_utils_t.from_bson d)::acc
      ) acc ds
    in

    let rec fetch_all acc r =
      if MongoReply.get_num_returned r = 0l then Lwt.return acc
      else begin
        let acc = fetch_one_batch ~acc r in
        lwt r = Mongo_lwt.get_more mongo (MongoReply.get_cursor r) in
        fetch_all acc r
      end
    in

    lwt l =
      if full then fetch_all [] r
      else Lwt.return (fetch_one_batch r)
    in

    Lwt.return (List.rev l)

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

let _ =
  Balsa_config.init ()

module User = Make (User_type)
module Movie = Make (Movie_type)
module Genre = Make (Genre_type)
module Rating = Make (Rating_type)
