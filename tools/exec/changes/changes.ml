(*
   1 -> Call themoviedb, fetch movie list with page
   3 -> Save last time save
   2 -> Refetch all changes, with timeout
*)

(* let movie_db = (module Db.Movie : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in *)
(* let genre_db = (module Db.Genre : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in *)

let get_api_movie mongodb id =
  let query = Bson.add_element "id" (Bson.create_int32 (Int32.of_int id)) Bson.empty in
  lwt r = Mongo_lwt.find_q_one mongodb query in
  let d = MongoReply.get_document_list r in
  match d with
    | [] -> Lwt.return None
    | h::_ -> Lwt.return (Some (Api.Movie.Bson_utils_t.from_bson h))

let apply_change thread_pool mongodb config cs =
  Lwt_list.iter_p (
    fun c ->
      Lwt_pool.use thread_pool (
        fun _ ->
          match_lwt get_api_movie mongodb c.Api.Movie_changes.id with
            | Some api_m ->
              let id = c.Api.Movie_changes.id in
              lwt new_m = Moviedb.Db_api.fetch_movie config id in
              let query = Bson.add_element "imdb_uid" (Bson.create_int32 (Int32.of_int id)) Bson.empty in
              begin match_lwt Db.Movie.query_one_no_cache query with
                | Some w2wt_m ->
                  (* missing genre *)
                  let m = Convert.Moviedb_to_w2wt.movie_update api_m w2wt_m in
                  Db.Movie.insert m
                | None -> Lwt.return_unit
              end
            | None ->
              Lwt.return_unit
      )
  ) cs

(* 1 get last time *)
let get_last_change_fetch ?(update=false) mongodb =
  let changeDb = Mongo_lwt.change_collection mongodb "changes" in
  let last_fetch_str = "last_fetch" in
  let now = Unix.time () in

  let get_last_fetch () =
    lwt r = Mongo_lwt.find_one changeDb in
    if MongoReply.get_num_returned r = 0l then
      Lwt.return_none
    else begin
      try
        let doc = List.nth (MongoReply.get_document_list r) 0 in
        let el = Bson.get_element last_fetch_str doc in
        Lwt.return (Some (Bson.get_double el))
      with _ -> Lwt.return_none
    end
  in
  let set_up_fetch lf =
    (* if lf does not exist, the update with upsert:true will create now_doc *)
    lwt lf = lf in
    let lf = Balsa_option.case (fun f -> f) (fun _ -> 0.) lf in
    let old_doc = Bson.add_element last_fetch_str (Bson.create_double lf) Bson.empty in
    let now_doc = Bson.add_element last_fetch_str (Bson.create_double now) Bson.empty in

    Mongo_lwt.update_one ~upsert:true changeDb (old_doc, now_doc)
  in

  let lf = get_last_fetch () in
  if update then
    Lwt.async (fun _ -> set_up_fetch lf);
  (now,lf)

let get_page config =
  let open Config_t in
  lwt mongodb = Mongo_lwt.create config.api_db.ip config.api_db.port config.api_db.name config.api_db.collection in
  let thread_pool = Lwt_pool.create config.max_connections (fun _ -> Lwt.return_unit) in

  let (now,lf) = get_last_change_fetch ~update:true mongodb in
  lwt lf = lf in

  let rec get_page_in page =
    lwt cs = Moviedb.Db_api.fetch_movie_change ?start_date:lf ~end_date:now ~page config in
    lwt _ = apply_change thread_pool mongodb config cs.Api.Movie_changes.results in
    if (cs.Api.Movie_changes.page < cs.Api.Movie_changes.total_pages) then
      get_page_in (cs.Api.Movie_changes.page + 1)
    else Lwt.return_unit
  in

  lwt _ = get_page_in 1 in
  Mongo_lwt.destory mongodb

let _ =
  let config = Config.get () in
  Lwt_main.run (get_page config)
