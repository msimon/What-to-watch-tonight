open Config_t

module Mongo = Mongo_lwt

let load_movies config mongodb action =
  lwt latest_movie_api = Db_api.fetch_last_movie config in

  lwt from_id,to_uid =
    match action with
      | `Complete ->
        let query = Bson.empty in
        let query = MongoMetaOp.orderBy (Bson.add_element "id" (Bson.create_int32 (-1l)) Bson.empty) query in
        lwt r = Mongo.find_q_one mongodb query in

        let max_id =
          try
            let e = List.nth (MongoReply.get_document_list r) 0 in
            let m = Api.Movie.Bson_utils_t.from_bson e in
            m.Api.Movie.id
          with _ -> 0
        in
        Printf.printf "Complete from %d to %d\n%!" max_id latest_movie_api.Api.Movie.id ;

        Lwt.return (max_id,latest_movie_api.Api.Movie.id)
      | `Reload ->
        lwt _ = Mongo.drop_collection mongodb in
        Lwt.return (0,latest_movie_api.Api.Movie.id)
      | `Retry ->
        let query = Bson.empty in
        let query = MongoMetaOp.orderBy (Bson.add_element "id" (Bson.create_int32 (-1l)) Bson.empty) query in
        lwt r = Mongo.find_q_one mongodb query in
        let max_id =
          try
            let e = List.nth (MongoReply.get_document_list r) 0 in
            let m = Api.Movie.Bson_utils_t.from_bson e in
            m.Api.Movie.id
          with _ -> 0
        in

        Printf.printf "retry from 0 to %d\n%!" max_id ;

        Lwt.return (0,max_id)
      | _ -> assert false
  in

  let thread_pool = Lwt_pool.create config.max_connections (fun _ -> Lwt.return_unit) in

  let uid = ref from_id in
  let next_uid () =
    incr(uid);
    !uid
  in

  let rec fetch_in () =
    let uid = next_uid () in
    let call () =
      Printf.printf "query : %d\n%!" uid;
      lwt m = Db_api.fetch_movie_str config uid in
      Db_api.add_movie_to_pool m;
      Lwt.return_unit
    in

    if uid > to_uid then Lwt.return_unit
    else begin
      lwt _ =
        Lwt_pool.use thread_pool (
          fun _ ->
            try_lwt
              match action with
                | `Retry ->
                  (* check if id is in movie collection *)
                  let query = Bson.add_element "id" (Bson.create_int32 (Int32.of_int uid)) Bson.empty in
                  lwt r = Mongo.find_q_one mongodb query in
                  if MongoReply.get_num_returned r = 0l then begin
                    call ()
                  end else begin
                    Lwt.return_unit
                  end
                | _ -> call ()
            with _ ->
              Lwt.return_unit
        ) in
      fetch_in ()
    end
  in

  let rec generate_thread n acc =
    if n > config.max_connections then acc
    else
      generate_thread (n + 1) (fetch_in ()::acc)
  in

  (* we join all connection thread together *)
  let threads = Lwt.join (generate_thread 1 []) in

  (* then we join the insertion, and thread together so insert doesn't end before connection threads*)
  Lwt.join [
    Db_api.insert_movie_async mongodb config.movie_loop_time threads;
    threads;
  ]

let load_genres config mongodb =
  let mongodb = Mongo.change_collection mongodb "genres" in
  lwt _ = Mongo.drop_collection mongodb in
  lwt genres = Db_api.fetch_genres config in

  Printf.printf "inserting %d genres\n%!" (List.length genres);

  List.iter (
    fun g ->
      try
        Lwt.async (fun _ -> Mongo.insert mongodb [ (Api.Genre.Bson_utils_t.to_bson g) ]);
      with exn ->
        Printf.printf "err insert genres: %s || on %s\n%!" (Printexc.to_string exn) (Api.Genre.Yojson_t.to_string g)
  ) genres;

  Lwt.return_unit

let run config action =
  lwt mongodb = Mongo.create config.api_db.ip config.api_db.port config.api_db.name config.api_db.collection in

  lwt _ =
    Mongo.ensure_simple_index ~options:[ Mongo.Unique true; Mongo.DropDups true ] mongodb "id"
  in

  lwt md_conf = Db_api.fetch_moviedb_configuration config in
  lwt _ =
    match action with
      | `Genres_only ->
        load_genres config mongodb
      | _ ->
        lwt _ = load_genres config mongodb in
        load_movies config mongodb action
  in

  lwt _ = Mongo.destory mongodb in
  Lwt.return ()
