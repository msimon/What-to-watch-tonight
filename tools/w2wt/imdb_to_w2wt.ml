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
    title: string;
    original_title: string ;
    overview: string option ;
    poster_path: string option ;
    release_date: string ;
    tagline: string option;
    genres: Genre_api.genre list ;
    vote_average: float ;
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
    original_title : string option ;
    overview : string option ;
    poster_path : string option ;
    release_date: string ;
    tagline : string option ;
    vote_average : float ;
    vote_count : int ;
    genres : int list ;
    vector : param list ;
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

  type user = {
    uid : Uid.user Uid.uid ;
    name: string ;
    ratings: Uid.rating Uid.uid list ;
    vector : param list ;
  } deriving (Bson_ext)
end

let movie config mongo_genre u =
  lwt mongo = Mongo.create config.database.ip config.database.port config.database.name "movies" in
  lwt mongo_ratings = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "ratings" in
  lwt _ = Mongo.ensure_simple_index mongo_ratings ~options:[ Mongo_lwt.Unique true ] "uid" in

  let rec add_movie acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      lwt movies =
        Lwt_list.fold_left_s (
          fun acc d ->
            let m = Movie_api.Bson_utils_movie.from_bson d in

            lwt genres =
              Lwt_list.map_p (
                fun g ->
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

            let movie_uid = Uid.fresh_uid Uid.Movie in

            let rating = {
              Rating_w2wt.uid = Uid.fresh_uid Uid.Rating ;
              user_uid = u.User_w2wt.uid ;
              movie_uid ;
              rating = int_of_float (m.Movie_api.vote_average +. 0.5) ;
            } in

            lwt _ = Mongo.insert mongo_ratings [ Rating_w2wt.Bson_utils_rating.to_bson rating ] in

            Lwt.return ({
              Movie_w2wt.uid = movie_uid ;
              title = m.Movie_api.title ;
              original_title =
                if m.Movie_api.title = m.Movie_api.original_title then None
                else Some m.Movie_api.original_title ;
              overview = m.Movie_api.overview ;
              poster_path = m.Movie_api.poster_path ;
              release_date = m.Movie_api.release_date ;
              tagline = m.Movie_api.tagline ;
              vote_average = float_of_int rating.Rating_w2wt.rating ;
              vote_count = 1;
              genres ;
              vector = [] ;
            }::acc)
        ) acc ds
      in

      lwt r = Mongo.get_more mongo (MongoReply.get_cursor r) in
      try_lwt
        add_movie movies r
      with exn ->
        Printf.printf "exn : %s\n%!" (Printexc.to_string exn);
        raise Not_found
    end
  in

  lwt r = Mongo.find mongo in

  lwt movies = add_movie [] r in

  lwt _ = Mongo.destory mongo in

  lwt mongo = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "movies" in
  lwt _ = Mongo.ensure_simple_index ~options:[ Mongo_lwt.Unique true ] mongo "uid" in
  lwt _ = Mongo.ensure_simple_index mongo "vote_average" in
  lwt _ = Mongo.ensure_simple_index mongo "vote_count" in


  lwt _ =
    Lwt_list.iter_p (
      fun m ->
        Mongo.insert mongo [ Movie_w2wt.Bson_utils_movie.to_bson m ]
    ) movies
  in

  lwt _ = Mongo.destory mongo_genre in
  Mongo.destory mongo


let genre config =
  lwt mongo = Mongo.create config.database.ip config.database.port config.database.name "genres" in

  let rec add_genre acc r =
    let ds = MongoReply.get_document_list r in
    if MongoReply.get_num_returned r = 0l then Lwt.return acc
    else begin
      let genres =
        List.fold_left (
          fun acc d ->
            let g = Genre_api.Bson_utils_genre.from_bson d in

            {
              Genre_w2wt.uid = Uid.fresh_uid Uid.Genre ;
              name = g.Genre_api.name ;
            }::acc
        ) acc ds
      in

      lwt r = Mongo.get_more mongo (MongoReply.get_cursor r) in

      add_genre genres r
    end
  in

  lwt r = Mongo.find mongo in
  lwt genres = add_genre [] r in

  lwt _ = Mongo.destory mongo in

  lwt mongo = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "genres" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in
  let genres_bson =
    List.map (
      fun g ->
        Genre_w2wt.Bson_utils_genre.to_bson g
    ) genres
  in

  lwt _ = Mongo.insert mongo genres_bson in

  (* Mongo.destory mongo *)
  Lwt.return mongo


let user config =
  lwt mongo = Mongo.create config.w2wt.ip config.w2wt.port config.w2wt.name "users" in
  lwt _ = Mongo.ensure_simple_index mongo ~options:[ Mongo_lwt.Unique true ] "uid" in

  let moviedb_user = {
    User_w2wt.uid = Uid.fresh_uid Uid.User ;
    name = "themoviedb" ;
    ratings = [] ;
    vector = [] ;
  } in

  let bson_user = User_w2wt.Bson_utils_user.to_bson moviedb_user in
  lwt _ = Mongo.insert mongo [ bson_user ] in
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
