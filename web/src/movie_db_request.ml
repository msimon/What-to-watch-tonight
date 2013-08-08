{shared{
  type movie = {
    uid: Movie_type.key ;
    title: string ;
    overview : string option ;
    poster_path : string option ;
    release_date: string ;
    tagline : string option ;
    vote_average : float ;
    vote_count : int ;
    genres : Genre_db_request.genre list ;
  }
}}


let movie_to_client m =
  lwt genres = Genre_db_request.genre_list_of_uid m.Movie_type.genres in
  Lwt.return ({
    uid = m.Movie_type.uid ;
    title = m.Movie_type.title ;
    overview = m.Movie_type.overview ;
    poster_path = m.Movie_type.poster_path ;
    release_date = m.Movie_type.release_date ;
    tagline = m.Movie_type.tagline ;
    vote_average = m.Movie_type.vote_average ;
    vote_count = m.Movie_type.vote_count ;
    genres;
  })


let movie_list_to_client l =
  Lwt_list.map_s movie_to_client l


let most_popular_movie () =
  (* order by vote average and vote_count *)
  let orderBy =

    let q = Bson.add_element "vote_average" (Bson.create_int32 (-1l)) Bson.empty in
    let q = Bson.add_element "vote_count" (Bson.create_int32 (-1l)) q in
    q
  in

  let query = MongoMetaOp.orderBy orderBy Bson.empty in
  (* limit to vote_average that are higher than 7 *)
  let query = MongoMetaOp.min (Bson.add_element "vote_average" (Bson.create_int32 7l) Bson.empty) query in

  lwt l = Db.Movie.query ~limit:100 ~full:true query in
  movie_list_to_client l
