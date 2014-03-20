open Config_t

module Mongo = Mongo_lwt
module Graph = Graph_server

let remove_useless_space =
  let rex1 = Pcre.regexp " +"  in
  let rex2 = Pcre.regexp "^ | $" in
  let itempl_empty = Pcre.subst "" in
  let itempl_space = Pcre.subst " " in
  (fun s ->
     let s = Pcre.replace ~rex:rex1 ~itempl:itempl_space s in
     let s = Pcre.replace ~rex:rex2 ~itempl:itempl_empty s in
     s)

let split ch s =
  let s = remove_useless_space s in
  let s = Printf.sprintf "%s%c" s ch in
  let x = ref [] in
  let i = ref 0 in
  let l = String.length s in
  while !i < l do
    let pos = String.index_from s !i ch in
    x := (String.sub s !i (pos - !i))::!x;
    i:=pos+1
  done;
  List.rev (!x)

(* remove dic for now since it break exact sentence search... *)
let remove_useless_word =
  (* let dic = [ "an"; "a"; "of"; "to"; "the"; "in"; "on"; "-"; "_"; "+"; "and"; "for"; "is"; "are" ] in *)
  (fun l ->
     List.fold_left (
       fun acc s ->
         let s = String.lowercase s in
         s::acc
         (* if List.mem s dic then acc *)
         (* else s::acc *)
     ) [] l
  )

let movie_update api_m w2wt_m =
  let open Api.Movie in

  let release_date =
    if (api_m.release_date != "") then begin
      Some (int_of_string (String.sub api_m.release_date 0 4))
    end else None
  in

  let tagline =
    Balsa_option.bind (
      fun t ->
        if t = "" then None
        else Some t
    ) api_m.tagline
  in

  {
    w2wt_m with
      Graph.Movie.title = api_m.title ;
      Graph.Movie.title_search = remove_useless_word (split ' ' api_m.title) ;
      Graph.Movie.original_title =
        if api_m.title = api_m.original_title then None
        else Some api_m.original_title ;
      overview = api_m.overview ;
      poster_path = api_m.poster_path ;
      release_date = release_date;
      tagline = tagline ;
  }

let movie config u genre_db movie_db rating_db =
  let module Genre_db = (val genre_db : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in
  let module Movie_db = (val movie_db : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let module Rating_db = (val rating_db : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in

  lwt mg_api = Mongo.create config.api_db.ip config.api_db.port config.api_db.name "movies" in

  let rec add_movie acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt movies =
        Lwt_list.fold_left_s (
          fun acc d ->
            let m = Api.Movie.Bson_utils_t.from_bson d in

            (* remove adult and erotic movies *)
            if m.Api.Movie.adult then Lwt.return acc
            else begin
              try_lwt
                lwt genres =
                  Lwt_list.map_p (
                    fun api_g ->
                      if String.lowercase api_g.Api.Genre.name = "erotic" then (failwith "Erotic movie") ;

                      let bson = Bson.add_element "name" (Bson.create_string api_g.Api.Genre.name) Bson.empty in
                      match_lwt Genre_db.query_one_no_cache bson with
                        | None ->
                          let new_genre = {
                            Graph.Genre.uid = Graph.Uid.fresh_uid Graph.Uid.Genre;
                            name = api_g.Api.Genre.name;
                          } in
                          lwt _ = Genre_db.insert new_genre in
                          Lwt.return new_genre.Graph.Genre.uid
                        | Some g ->
                          Lwt.return g.Graph.Genre.uid
                  ) m.Api.Movie.genres
                in

                (* if the movie does not have enough rating we ignore it
                   TODO: update is necessary to be able to check that value correctly:
                   A new movie that just be had could have no rating when checking but hundreds a day later.
                *)
                if m.Api.Movie.vote_count < config.minimal_vote_count then (failwith "no enough rating");

                let check_movie = Bson.add_element "imdb_uid" (Bson.create_int32 (Int32.of_int m.Api.Movie.id)) Bson.empty in
                match_lwt Movie_db.query_one_no_cache check_movie with
                  | Some _ -> (failwith "already inserted")
                  | None ->
                    (* if everything seems good, create the new movie and rating by themovieDB user
                       TODO: when implementing the update
                    *)
                    let movie_uid = Graph.Uid.fresh_uid Graph.Uid.Movie in

                    let rating = {
                      Graph.Rating.uid = Graph.Uid.fresh_uid Graph.Uid.Rating ;
                      user_uid = u.Graph.User.uid ;
                      movie_uid ;
                      rating = int_of_float ((m.Api.Movie.vote_average /. 2.) +. 0.5);
                    } in

                    lwt _ = Rating_db.insert rating in

                    let release_date =
                      if (m.Api.Movie.release_date != "") then begin
                        Some (int_of_string (String.sub m.Api.Movie.release_date 0 4))
                      end else None
                    in

                    let tagline =
                      Balsa_option.bind (
                        fun t ->
                          if t = "" then None
                          else Some t
                      ) m.Api.Movie.tagline
                    in

                    Lwt.return ({
                        Graph.Movie.uid = movie_uid ;
                        title = m.Api.Movie.title ;
                        title_search = remove_useless_word (split ' ' m.Api.Movie.title) ;
                        original_title =
                          if m.Api.Movie.title = m.Api.Movie.original_title then None
                          else Some m.Api.Movie.original_title ;
                        overview = m.Api.Movie.overview ;
                        poster_path = m.Api.Movie.poster_path ;
                        release_date ;
                        tagline ;
                        vote_average = float_of_int (rating.Graph.Rating.rating) ;
                        vote_count = 1 (* m.Api.Movie.vote_count *) ;
                        genres ;
                        vector = [] ;
                        imdb_uid = m.Api.Movie.id;
                        last_time_fetch = None;
                      }::acc)

              with _ ->
                Lwt.return acc
            end
        ) acc ds
      in

      lwt r = Mongo.get_more mg_api (MongoReply.get_cursor r) in
      try_lwt
        add_movie movies r
      with exn ->
        raise Not_found
    end
  in

  lwt r = Mongo.find mg_api in
  lwt movies = add_movie [] r in
  lwt _ = Mongo.destory mg_api in

  Balsa_log.info "Number of movies added : %d" (List.length movies);

  lwt _ =
    Lwt_list.iter_p (
      fun m ->
        Movie_db.insert m
    ) movies
  in

  Mongo.destory mg_api


let genre config genre_db =
  let module Genre_db = (val genre_db : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in

  lwt mg_api = Mongo.create config.api_db.ip config.api_db.port config.api_db.name "genres" in

  let rec add_genre acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt genres =
        Lwt_list.fold_left_s (
          fun acc d ->
            let g = Api.Genre.Bson_utils_t.from_bson d in
            (* check if genre exist, if it does raise "genre exist" *)
            let bson = Bson.add_element "name" (Bson.create_string g.Api.Genre.name) Bson.empty in
            match_lwt Genre_db.query_one_no_cache bson with
              | Some _ -> Lwt.return acc
              | None ->
                Lwt.return ({
                    Graph.Genre.uid = Graph.Uid.fresh_uid Graph.Uid.Genre ;
                    name = g.Api.Genre.name ;
                  }::acc)
        ) acc ds
      in

      lwt r = Mongo.get_more mg_api (MongoReply.get_cursor r) in

      add_genre genres r
    end
  in

  lwt r = Mongo.find mg_api in
  lwt genres = add_genre [] r in
  lwt _ = Mongo.destory mg_api in

  Balsa_log.info "Number of genres added : %d" (List.length genres);

  lwt _ =
    Lwt_list.iter_p (
      fun g ->
        Genre_db.insert g
    ) genres
  in

  Lwt.return_unit


let user config user_db =
  let module User_db = (val user_db : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in

  let check_user = Bson.add_element "name" (Bson.create_string "themoviedb") Bson.empty in
  lwt moviedb_user =
    match_lwt User_db.query_one_no_cache check_user with
      | None ->
        let moviedb_user = {
          Graph.User.uid = Graph.Uid.fresh_uid Graph.Uid.User ;
          name = "themoviedb" ;
          facebook = None ;
          ratings = [] ;
          vector = [] ;
          top_movies = [];
          last_time_fetch = None;
        } in

        lwt _ = User_db.insert moviedb_user in
        Lwt.return moviedb_user
      | Some u ->
        Lwt.return u
  in
  Lwt.return moviedb_user

let convert config user_db movie_db genre_db rating_db =
  let run () =
    lwt _ = genre config genre_db in
    lwt u = user config user_db in
    lwt _ = movie config u genre_db movie_db rating_db in

    Lwt.return_unit
  in

  run ()
