exception Reload_cache

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

  (* string list: for multi-index only. When we want ONE index on several fields *)
  (* i.e: ([ "user_uid"; "movie_uid" ], [ Mongo_lwt.Unique true ]) mean that the couple
     user_uid and movie_uid must be unique, but not user_uid or movie_uid as themself.
  *)
  val indexes: unit -> (string list * (Mongo_lwt.index_option list)) list

end

module type C =
sig
  val cache_lifetime : float
  val cache_size: int
  val db_ip: string
  val db_port: int
  val db_name: string
  val query_cache_lifetime: int
end

module type Sig = sig
  type t deriving (Bson_ext)
  type key

  val find: key -> t Lwt.t

  val query_one_no_cache : Bson.t -> t option Lwt.t
  val query_no_cache : ?skip:int -> ?limit:int -> ?full:bool -> Bson.t -> t list Lwt.t

  val query_one : ?force:bool -> Bson.t -> t option Lwt.t
  val query : ?force:bool -> ?skip:int -> ?limit:int -> ?full:bool -> Bson.t -> t list Lwt.t

  val insert: t -> unit Lwt.t
  val update: t -> unit Lwt.t
  val delete: t -> unit Lwt.t

  val find_and_update: key -> (t -> t) -> t Lwt.t

  val count : ?skip: int -> ?limit: int -> ?query:Bson.t -> unit -> int Lwt.t

end

module type Make =
  functor (M : M) -> functor (C : C) -> Sig with type t = M.t with type key = M.key

module Make (M : M) (C : C) : Sig with type t = M.t with type key = M.key =
struct

  type t = M.t deriving (Bson_ext)
  type key = M.key

  module Cache = Ocsigen_cache.Make (struct
      type key = M.key
      type value = t
    end)

  (* mongo is Lwt.t lazy.t*)
  (* let mongo = lazy ( *)
  (*   Balsa_config.(Mongo_lwt.create (get_string "db.ip") (get_int "db.port") (get_string "db.name")  M.collection) *)
  (* ) *)
  let mongo = Mongo_lwt.create C.db_ip C.db_port C.db_name  M.collection

  let ready,set_ready = Lwt.task ()

  let _ =
    Lwt.async (
      fun _ ->
        lwt mongo = mongo in

        (* get the last uid, and set it in Uid.uid*)
        let q = MongoMetaOp.orderBy (Bson.add_element M.uid_field (Bson.create_int32 (-1l)) Bson.empty) Bson.empty in
        let s = Bson.add_element M.uid_field (Bson.create_int32 1l) Bson.empty in

        lwt r = Mongo_lwt.find_q_s_one mongo q s in

        let _ = match MongoReply.get_document_list r with
          | [] -> ()
          | h::_ ->
            let n = Bson.get_int64 (Bson.get_element M.uid_field h) in
            Uid.set_uid M.uid_typ (Uid.unsafe (Int64.to_int n)) ;
        in

        (* add index *)
        lwt _ =
          Lwt_list.iter_p (
            fun (fields, options) ->
              Mongo_lwt.ensure_multi_simple_index ~options mongo fields
          ) (M.indexes ());
        in

        (* notify that this collection is ready *)
        Lwt.wakeup set_ready ();
        Lwt.return_unit
    )


  let find_in_db key =
    lwt mongo = mongo in
    let bson_search = M.search key in

    lwt r = Mongo_lwt.find_q_one mongo bson_search in

    let d = match MongoReply.get_document_list r with
      | [] -> raise Not_found
      | h::_ -> h
    in

    Lwt.return (Bson_utils_t.from_bson d)

  (* let cache = Balsa_config.(new Cache.cache find_in_db ~timer:(get_float "cache.cache_lifetime") (get_int "cache.cache_size")) *)
  let cache = new Cache.cache find_in_db ~timer:C.cache_lifetime C.cache_size

  let find key =
    cache#find key

  let query_one_no_cache bson_t =
    lwt mongo = mongo in
    lwt r = Mongo_lwt.find_q_one mongo bson_t in

    match MongoReply.get_document_list r with
      | [ ] -> Lwt.return_none
      | h::_ -> Lwt.return (Some (Bson_utils_t.from_bson h))


  let query_no_cache ?skip ?limit ?(full=false) bson_t =
    lwt mongo = mongo in
    lwt r =
      match limit with
        | Some l -> Mongo_lwt.find_q_of_num ?skip mongo bson_t l
        | None -> Mongo_lwt.find_q ?skip mongo bson_t
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

  let query_one_htbl = Hashtbl.create 100
  let query_htbl = Hashtbl.create 100

  let query_one ?(force=false) bson_t =
    try
      if force then raise Reload_cache ;

      let (r,t) = Hashtbl.find query_one_htbl bson_t in
      let n = int_of_float (Unix.time ()) in

      if n > t then (raise Reload_cache)
      else Lwt.return r

    with Not_found | Reload_cache ->
      lwt r = query_one_no_cache bson_t in
      let t = int_of_float (Unix.time ()) + C.query_cache_lifetime in (* Balsa_config.get_int "db.query_cache_lifetime") in *)
      Hashtbl.replace query_one_htbl bson_t (r,t);

      Balsa_option.iter (
        fun t ->
          cache#remove (M.key t) ;
          cache#add (M.key t) t;
      ) r;

      Lwt.return r


  let query ?(force=false) ?skip ?limit ?(full=false) bson_t =
    try
      if force then raise Reload_cache ;

      let (r,t) = Hashtbl.find query_htbl (skip,limit,full,bson_t) in
      let n = int_of_float (Unix.time ()) in

      if n > t then (raise Reload_cache)
      else Lwt.return r

    with Not_found | Reload_cache ->
      lwt r = query_no_cache ?skip ?limit ~full bson_t in
      let t = int_of_float (Unix.time ()) + C.query_cache_lifetime (* (Balsa_config.get_int "db.query_cache_lifetime")  *)in
      Hashtbl.replace query_htbl (skip,limit,full,bson_t) (r,t);
      Lwt.return r

  (* insert/update/delete must wait for the db to be ready *)

  let insert t =
    lwt _ = ready in
    lwt mongo = mongo in
    lwt _ = Mongo_lwt.insert mongo [ Bson_utils_t.to_bson t ] in

    cache#add (M.key t) t;

    Lwt.return_unit

  let update t =
    lwt _ = ready in
    lwt mongo = mongo in
    lwt _ = Mongo_lwt.update_one mongo ((M.search (M.key t)),(Bson_utils_t.to_bson t)) in

    cache#remove (M.key t) ;
    cache#add (M.key t) t;

    Lwt.return_unit

  let delete t =
    lwt _ = ready in
    lwt mongo = mongo in
    lwt _ = Mongo_lwt.delete_one mongo (M.search (M.key t)) in

    cache#remove (M.key t) ;

    Lwt.return_unit


  (* This function assure that the data in DB will not be modify by another thread,
     between the find and the update
  *)
  let find_and_update =
    let mutex = Lwt_mutex.create () in
    (fun key update_fun ->
       lwt _ = Lwt_mutex.lock mutex in
       lwt d = find key in
       try_lwt
         let d = update_fun d in
         lwt _ = update d in
         Lwt_mutex.unlock mutex;
         Lwt.return d
       with
         | exn ->
           Lwt_mutex.unlock mutex;
           raise exn
    )

  let count ?skip ?limit ?query () =
    lwt mongo = mongo in
    Mongo_lwt.count ?skip ?limit ?query mongo

end

module User = Make (User)
module Movie = Make (Movie)
module Genre = Make (Genre)
module Rating = Make (Rating)
