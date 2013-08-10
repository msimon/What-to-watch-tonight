module type M =
sig

  type t deriving (Bson_ext)
  type key deriving (Bson_ext)
  type uid_typ

  val collection : string
  val uid_field : string
  val uid_typ: uid_typ Uid.typ

  val search: key -> Bson.t
  val key: t -> key

  val indexes: unit -> (string * (Mongo_lwt.index_option list)) list

end

module type Make =
  functor (M : M) ->
  sig
    type t = M.t deriving (Bson_ext)
    type key = M.key

    val find: key -> t Lwt.t
    val query_one : Bson.t -> t option Lwt.t
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

  let ready,set_ready = Lwt.task ()

  let _ =
    let indexes = M.indexes () in
    Lwt.async (
      fun _ ->
        lwt mongo = Lazy.force mongo in

        (* get the last uid, and set it in Uid.uid*)

        let q = MongoMetaOp.orderBy (Bson.add_element M.uid_field (Bson.create_int32 (-1l)) Bson.empty) Bson.empty in
        let s = Bson.add_element M.uid_field (Bson.create_int32 1l) Bson.empty in

        lwt r = Mongo_lwt.find_q_s_one mongo q s in

        let n = match MongoReply.get_document_list r with
          | [] -> 1
          | h::_ ->
            let n = Bson.get_int64 (Bson.get_element M.uid_field h) in
            (Int64.to_int n) + 1
        in
        Uid.set_uid M.uid_typ n ;

        (* add index *)
        lwt _ =
          Lwt_list.iter_p (
            fun (name, options) ->
              Mongo_lwt.ensure_simple_index ~options mongo name
          ) indexes;
        in

        (* notify that this collection is ready *)
        Lwt.wakeup set_ready ();
        Lwt.return_unit
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

  let query_one bson_t =
    lwt mongo = Lazy.force mongo in
    lwt r = Mongo_lwt.find_q_one mongo bson_t in

    match MongoReply.get_document_list r with
      | [ ] -> Lwt.return_none
      | h::_ -> Lwt.return (Some (Bson_utils_t.from_bson h))


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

  (* insert/update/delete must wait for the db to be ready *)

  let insert t =
    lwt _ = ready in
    lwt mongo = Lazy.force mongo in
    lwt _ = Mongo_lwt.insert mongo [ Bson_utils_t.to_bson t ] in

    cache#add (M.key t) t;

    Lwt.return_unit


  let update t =
    lwt _ = ready in
    lwt mongo = Lazy.force mongo in
    lwt _ = Mongo_lwt.update_one mongo ((M.search (M.key t)),(Bson_utils_t.to_bson t)) in

    cache#remove (M.key t) ;
    cache#add (M.key t) t;

    Lwt.return_unit

  let delete t =
    lwt _ = ready in
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
