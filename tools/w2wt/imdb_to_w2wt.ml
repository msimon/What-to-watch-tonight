open Config

module Mongo = Mongo_lwt
module Graph = Graph_server

(* module Genre_api = struct *)
(*   type genre = { *)
(*     id: int ; *)
(*     name: string ; *)
(*   } deriving (Json_ext, Bson_ext) *)
(* end *)

(* module Genre_w2wt = struct *)
(*   type genre = { *)
(*     uid: Uid.genre Uid.uid ; *)
(*     name: string ; *)
(*   } deriving (Bson_ext) *)
(* end *)

(* module Movie_api = struct *)
(*   type movie = { *)
(*     id: int ; *)
(*     adult : bool ; *)
(*     title: string; *)
(*     original_title: string ; *)
(*     overview: string option ; *)
(*     poster_path: string option ; *)
(*     release_date: string ; *)
(*     tagline: string option; *)
(*     genres: Api.Genre.genre list ; *)
(*     vote_average: float ; *)
(*     vote_count: int; *)
(*   } deriving (Json_ext, Bson_ext) *)
(* end *)

(* module Movie_w2wt = struct *)
(*   type param = { *)
(*     genre_uid : int ; *)
(*     value : float ; *)
(*   } deriving (Bson_ext) *)

(*   type movie = { *)
(*     uid: Uid.movie Uid.uid ; *)
(*     title: string ; *)
(*     title_search: string list ; *)
(*     original_title : string option ; *)
(*     overview : string option ; *)
(*     poster_path : string option ; *)
(*     release_date: string ; *)
(*     tagline : string option ; *)
(*     vote_average : float ; *)
(*     vote_count: int ; *)
(*     genres : Uid.genre Uid.uid list ; *)
(*     vector : param list ; *)
(*     imdb_uid: int ; *)
(*   } deriving (Bson_ext) *)
(* end *)

(* module Rating_w2wt = struct *)
(*   type rating = { *)
(*     uid: Uid.rating Uid.uid ; *)
(*     user_uid: Uid.user Uid.uid; *)
(*     movie_uid: Uid.movie Uid.uid; *)
(*     rating: int ; *)
(*   } deriving (Bson_ext) *)
(* end *)

(* module User_w2wt = struct *)
(*   type param = { *)
(*     genres_uid : Uid.genre Uid.uid ; *)
(*     value : float ; *)
(*   } deriving (Bson_ext) *)

(*   type facebook = { *)
(*     facebook_uid : string ; *)
(*     facebook_access_token : string ; *)
(*     facebook_access_token_expire_on : int ; *)
(*   } deriving (Bson_ext) *)

(*   type user = { *)
(*     uid : Uid.user Uid.uid ; *)
(*     name: string ; *)
(*     facebook : facebook option ; *)
(*     ratings: Uid.rating Uid.uid list ; *)
(*     vector : param list ; *)
(*   } deriving (Bson_ext) *)
(* end *)

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

(* remove dic for now*)
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

let setup_uid mongodb t =
  let query = Bson.empty in
  let query = MongoMetaOp.orderBy (Bson.add_element "uid" (Bson.create_int32 (-1l)) Bson.empty) query in
  lwt r = Mongo.find_q_s_one mongodb query (Bson.add_element "uid" (Bson.create_int32 1l) Bson.empty) in
  try
    let e = List.nth (MongoReply.get_document_list r) 0 in
    let uid = Int32.to_int (Bson.get_int32 (Bson.get_element "uid" e)) in
    Graph.Uid.set_uid t (Graph.Uid.unsafe uid);
    Lwt.return_unit
  with _ -> Lwt.return_unit


let movie config mongo_genre u =
  (* set movie uid here *)
  lwt mongo = Mongo.create config.api_db.ip config.api_db.port config.api_db.name "movies" in
  lwt mongo_ratings = Mongo.create config.w2wt_db.ip config.w2wt_db.port config.w2wt_db.name "ratings" in
  lwt _ = Mongo.ensure_simple_index mongo_ratings ~options:[ Mongo.Unique true ] "uid" in

  lwt mongo_w2wt_movie = Mongo.create config.w2wt_db.ip config.w2wt_db.port config.w2wt_db.name "movies" in
  lwt _ = setup_uid mongo Graph.Uid.Movie in

  let rec add_movie acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt movies =
        Lwt_list.fold_left_s (
          fun acc d ->
            let m = Api.Movie.Bson_utils_t.from_bson d in

            if m.Api.Movie.adult then Lwt.return acc
            else begin
              try_lwt
                lwt genres =
                  Lwt_list.map_p (
                    fun g ->
                      if String.lowercase g.Api.Genre.name = "erotic" then (failwith "Erotic movie") ;

                      let bson = Bson.add_element "name" (Bson.create_string g.Api.Genre.name) Bson.empty in

                      lwt r = Mongo.find_q_one mongo_genre bson in
                      if MongoReply.get_num_returned r = 0l then begin
                        let new_genre = {
                          Graph.Genre.uid = Graph.Uid.fresh_uid Graph.Uid.Genre;
                          name = g.Api.Genre.name;
                        } in

                        lwt _ = Mongo.insert mongo_genre [ Graph.Genre.Bson_utils_t.to_bson new_genre ] in
                        Lwt.return new_genre.Graph.Genre.uid
                      end else begin
                        let d = List.nth (MongoReply.get_document_list r) 0 in
                        let g_ = Graph.Genre.Bson_utils_t.from_bson d in

                        Lwt.return g_.Graph.Genre.uid
                      end
                  ) m.Api.Movie.genres
                in

                (* Check if movies exist, if it does raise "already inserted" ? *)

                let check_movie = Bson.add_element "imdb_uid" (Bson.create_int32 (Int32.of_int m.Api.Movie.id)) Bson.empty in
                lwt r = Mongo.find_q_one mongo_w2wt_movie check_movie in
                if MongoReply.get_num_returned r = 0l then begin

                  let rating = int_of_float ((m.Api.Movie.vote_average /. 2.) +. 0.5) in

                  if rating = 0 then (failwith "no enough rating");
                  let movie_uid = Graph.Uid.fresh_uid Graph.Uid.Movie in

                  let rating = {
                    Graph.Rating.uid = Graph.Uid.fresh_uid Graph.Uid.Rating ;
                    user_uid = u.Graph.User.uid ;
                    movie_uid ;
                    rating ;
                  } in


                  lwt _ = Mongo.insert mongo_ratings [ Graph.Rating.Bson_utils_t.to_bson rating ] in

                  Lwt.return ({
                      Graph.Movie.uid = movie_uid ;
                      title = m.Api.Movie.title ;
                      title_search = remove_useless_word (split ' ' m.Api.Movie.title) ;
                      original_title =
                        if m.Api.Movie.title = m.Api.Movie.original_title then None
                        else Some m.Api.Movie.original_title ;
                      overview = m.Api.Movie.overview ;
                      poster_path = m.Api.Movie.poster_path ;
                      release_date = m.Api.Movie.release_date ;
                      tagline = m.Api.Movie.tagline ;
                      vote_average = float_of_int (rating.Graph.Rating.rating) ;
                      vote_count = 1 (* m.Api.Movie.vote_count *) ;
                      genres ;
                      vector = [] ;
                      imdb_uid = m.Api.Movie.id;
                    }::acc)
                end else Lwt.return acc
              with _ ->
                Lwt.return acc
            end
        ) acc ds
      in

      lwt r = Mongo.get_more mongo (MongoReply.get_cursor r) in
      try_lwt
        add_movie movies r
      with exn ->
        raise Not_found
    end
  in

  lwt r = Mongo.find mongo in
  lwt movies = add_movie [] r in
  lwt _ = Mongo.destory mongo in

  lwt _ =
    Lwt_list.iter_p (
      fun m ->
        Mongo.insert mongo_w2wt_movie [ Graph.Movie.Bson_utils_t.to_bson m ]
    ) movies
  in

  lwt _ = Mongo.destory mongo_genre in
  Mongo.destory mongo


let genre config =
  lwt mongo = Mongo.create config.api_db.ip config.api_db.port config.api_db.name "genres" in

  lwt mongo_w2wt_genre = Mongo.create config.w2wt_db.ip config.w2wt_db.port config.w2wt_db.name "genres" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in

  lwt _ = setup_uid mongo Graph.Uid.Genre in

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

            lwt r = Mongo.find_q_one mongo_w2wt_genre bson in
            if MongoReply.get_num_returned r = 0l then begin
              Lwt.return ({
                  Graph.Genre.uid = Graph.Uid.fresh_uid Graph.Uid.Genre ;
                  name = g.Api.Genre.name ;
                }::acc)
            end else Lwt.return acc
        ) acc ds
      in

      lwt r = Mongo.get_more mongo (MongoReply.get_cursor r) in

      add_genre genres r
    end
  in

  lwt r = Mongo.find mongo in
  lwt genres = add_genre [] r in
  lwt _ = Mongo.destory mongo in

  let genres_bson =
    List.map (
      fun g ->
        Graph.Genre.Bson_utils_t.to_bson g
    ) genres
  in

  lwt _ = Mongo.insert mongo_w2wt_genre genres_bson in

  (* Mongo.destory mongo *)
  Lwt.return mongo_w2wt_genre


let user config =
  lwt mongo = Mongo.create config.w2wt_db.ip config.w2wt_db.port config.w2wt_db.name "users" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in

  (* search themoviedb user do not add the user if it exist. Should it be removed ? *)
  let check_user = Bson.add_element "name" (Bson.create_string "themoviedb") Bson.empty in
  lwt r = Mongo.find_q_one mongo check_user in

  lwt moviedb_user =
    if MongoReply.get_num_returned r = 0l then begin
      let moviedb_user = {
        Graph.User.uid = Graph.Uid.fresh_uid Graph.Uid.User ;
        name = "themoviedb" ;
        facebook = None ;
        ratings = [] ;
        vector = [] ;
      } in

      let bson_user = Graph.User.Bson_utils_t.to_bson moviedb_user in
      lwt _ = Mongo.insert mongo [ bson_user ] in
      Lwt.return moviedb_user
    end else begin
      let d = List.nth (MongoReply.get_document_list r) 0 in
      let moviedb_user = Graph.User.Bson_utils_t.from_bson d in
      Lwt.return moviedb_user
    end
  in

  lwt _ = Mongo.destory mongo in

  Lwt.return moviedb_user


let run () =
  let config = Config.init () in
  lwt mongo_genre = genre config in
  lwt u = user config in
  lwt _ = movie config mongo_genre u in

  Lwt.return_unit


let _ =
  Lwt_main.run (run ())
