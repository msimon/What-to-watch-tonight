open Config

module Mongo = Mongo_lwt

module Genre_api = struct
  type genre = {
    id: int ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Genre_w2wt = struct
  type genre = {
    uid: Uid.genre Uid.uid ;
    name: string ;
  } deriving (Bson_ext)
end

module Movie_api = struct
  type movie = {
    id: int ;
    adult : bool ;
    title: string;
    original_title: string ;
    overview: string option ;
    poster_path: string option ;
    release_date: string ;
    tagline: string option;
    genres: Genre_api.genre list ;
    vote_average: float ;
    vote_count: int;
  } deriving (Json_ext, Bson_ext)
end

module Movie_w2wt = struct
  type param = {
    genre_uid : int ;
    value : float ;
  } deriving (Bson_ext)

  type movie = {
    uid: Uid.movie Uid.uid ;
    title: string ;
    title_search: string list ;
    original_title : string option ;
    overview : string option ;
    poster_path : string option ;
    release_date: string ;
    tagline : string option ;
    vote_average : float ;
    vote_count: int ;
    genres : Uid.genre Uid.uid list ;
    vector : param list ;
    imdb_uid: int ;
  } deriving (Bson_ext)
end

module Rating_w2wt = struct
  type rating = {
    uid: Uid.rating Uid.uid ;
    user_uid: Uid.user Uid.uid;
    movie_uid: Uid.movie Uid.uid;
    rating: int ;
  } deriving (Bson_ext)
end

module User_w2wt = struct
  type param = {
    genres_uid : Uid.genre Uid.uid ;
    value : float ;
  } deriving (Bson_ext)

  type facebook = {
    facebook_uid : string ;
    facebook_access_token : string ;
    facebook_access_token_expire_on : int ;
  } deriving (Bson_ext)

  type user = {
    uid : Uid.user Uid.uid ;
    name: string ;
    facebook : facebook option ;
    ratings: Uid.rating Uid.uid list ;
    vector : param list ;
  } deriving (Bson_ext)
end

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
    Uid.set_uid t (Uid.unsafe uid);
    Lwt.return_unit
  with _ -> Lwt.return_unit


let movie config mongo_genre u =
  (* set movie uid here *)

  lwt mongo = Mongo.create config.database.ip config.database.port config.database.name "movies" in
  lwt mongo_ratings = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "ratings" in
  lwt _ = Mongo.ensure_simple_index mongo_ratings ~options:[ Mongo.Unique true ] "uid" in

  lwt mongo_w2wt_movie = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "movies" in
  lwt _ = Mongo.ensure_simple_index ~options:[ Mongo_lwt.Unique true ] mongo_w2wt_movie "uid" in
  lwt _ = Mongo.ensure_simple_index mongo_w2wt_movie "vote_average" in
  lwt _ = Mongo.ensure_simple_index mongo_w2wt_movie "vote_count" in
  lwt _ = Mongo.ensure_simple_index mongo_w2wt_movie ~options:[ Mongo.Unique true; Mongo.DropDups true ] "imdb_uid" in

  lwt _ = setup_uid mongo Uid.Movie in

  let rec add_movie acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt movies =
        Lwt_list.fold_left_s (
          fun acc d ->
            let m = Movie_api.Bson_utils_movie.from_bson d in

            if m.Movie_api.adult then Lwt.return acc
            else begin
              try_lwt
                lwt genres =
                  Lwt_list.map_p (
                    fun g ->
                      if String.lowercase g.Genre_api.name = "erotic" then (failwith "Erotic movie") ;

                      let bson = Bson.add_element "name" (Bson.create_string g.Genre_api.name) Bson.empty in

                      lwt r = Mongo.find_q_one mongo_genre bson in
                      if MongoReply.get_num_returned r = 0l then begin
                        let new_genre = {
                          Genre_w2wt.uid = Uid.fresh_uid Uid.Genre;
                          name = g.Genre_api.name;
                        } in

                        lwt _ = Mongo.insert mongo_genre [ Genre_w2wt.Bson_utils_genre.to_bson new_genre ] in
                        Lwt.return new_genre.Genre_w2wt.uid
                      end else begin
                        let d = List.nth (MongoReply.get_document_list r) 0 in
                        let g_ = Genre_w2wt.Bson_utils_genre.from_bson d in

                        Lwt.return g_.Genre_w2wt.uid
                      end
                  ) m.Movie_api.genres
                in

                (* Check if movies exist, if it does raise "already inserted" ? *)

                let check_movie = Bson.add_element "imdb_uid" (Bson.create_int32 (Int32.of_int m.Movie_api.id)) Bson.empty in
                lwt r = Mongo.find_q_one mongo_w2wt_movie check_movie in
                if MongoReply.get_num_returned r = 0l then begin
                  let movie_uid = Uid.fresh_uid Uid.Movie in

                  let rating = {
                    Rating_w2wt.uid = Uid.fresh_uid Uid.Rating ;
                    user_uid = u.User_w2wt.uid ;
                    movie_uid ;
                    rating = int_of_float ((m.Movie_api.vote_average /. 2.) +. 0.5) ;
                  } in

                  if rating.Rating_w2wt.rating = 0 then (failwith "no enough rating");

                  lwt _ = Mongo.insert mongo_ratings [ Rating_w2wt.Bson_utils_rating.to_bson rating ] in

                  Lwt.return ({
                      Movie_w2wt.uid = movie_uid ;
                      title = m.Movie_api.title ;
                      title_search = remove_useless_word (split ' ' m.Movie_api.title) ;
                      original_title =
                        if m.Movie_api.title = m.Movie_api.original_title then None
                        else Some m.Movie_api.original_title ;
                      overview = m.Movie_api.overview ;
                      poster_path = m.Movie_api.poster_path ;
                      release_date = m.Movie_api.release_date ;
                      tagline = m.Movie_api.tagline ;
                      vote_average = float_of_int (rating.Rating_w2wt.rating) ;
                      vote_count = 1 (* m.Movie_api.vote_count *) ;
                      genres ;
                      vector = [] ;
                      imdb_uid = m.Movie_api.id;
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
        Mongo.insert mongo_w2wt_movie [ Movie_w2wt.Bson_utils_movie.to_bson m ]
    ) movies
  in

  lwt _ = Mongo.destory mongo_genre in
  Mongo.destory mongo


let genre config =
  lwt mongo = Mongo.create config.database.ip config.database.port config.database.name "genres" in

  lwt mongo_w2wt_genre = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "genres" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in

  lwt _ = setup_uid mongo Uid.Genre in

  let rec add_genre acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt genres =
        Lwt_list.fold_left_s (
          fun acc d ->
            let g = Genre_api.Bson_utils_genre.from_bson d in
            (* check if genre exist, if it does raise "genre exist" *)

            let bson = Bson.add_element "name" (Bson.create_string g.Genre_api.name) Bson.empty in

            lwt r = Mongo.find_q_one mongo_w2wt_genre bson in
            if MongoReply.get_num_returned r = 0l then begin
              Lwt.return ({
                  Genre_w2wt.uid = Uid.fresh_uid Uid.Genre ;
                  name = g.Genre_api.name ;
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
        Genre_w2wt.Bson_utils_genre.to_bson g
    ) genres
  in

  lwt _ = Mongo.insert mongo_w2wt_genre genres_bson in

  (* Mongo.destory mongo *)
  Lwt.return mongo_w2wt_genre


let user config =
  lwt mongo = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "users" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in

  (* search themoviedb user do not add the user if it exist. Should it be removed ? *)

  let check_user = Bson.add_element "name" (Bson.create_string "themoviedb") Bson.empty in
  lwt r = Mongo.find_q_one mongo check_user in

  lwt moviedb_user =
    if MongoReply.get_num_returned r = 0l then begin
      let moviedb_user = {
        User_w2wt.uid = Uid.fresh_uid Uid.User ;
        name = "themoviedb" ;
        facebook = None ;
        ratings = [] ;
        vector = [] ;
      } in

      let bson_user = User_w2wt.Bson_utils_user.to_bson moviedb_user in
      lwt _ = Mongo.insert mongo [ bson_user ] in
      Lwt.return moviedb_user
    end else begin
      let d = List.nth (MongoReply.get_document_list r) 0 in
      let moviedb_user = User_w2wt.Bson_utils_user.from_bson d in
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
