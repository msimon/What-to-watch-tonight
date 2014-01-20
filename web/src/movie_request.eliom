{shared{
  type movie = {
    uid: Graph.Movie.key ;
    title: string ;
    overview : string option ;
    poster_path : string option ;
    release_date: string ;
    tagline : string option ;
    vote_average : float ;
    vote_count : int ;
    genres : Genre_request.genre list ;
  }
}}

{client{
  module M =
    struct
      type client_t = movie
    end
}}

module M =
struct
  type db_t = Graph.Movie.t
  type uid = Graph.Movie.key
  type client_t = movie

  let to_client m =
    lwt genres = Genre_request.list_of_uid m.Graph.Movie.genres in

    Lwt.return ({
        uid = m.Graph.Movie.uid ;
        title = m.Graph.Movie.title ;
        overview = m.Graph.Movie.overview ;
        poster_path = m.Graph.Movie.poster_path ;
        release_date = m.Graph.Movie.release_date ;
        tagline = m.Graph.Movie.tagline ;
        vote_average = m.Graph.Movie.vote_average ;
        vote_count = m.Graph.Movie.vote_count ;
        genres;
      })

  let find = Db.Movie.find

  let find_all () = Db.Movie.query ~full:true Bson.empty

end

module DB_r = Db_request.Make (M)
include DB_r

let most_popular ?skip ?(limit=100) () =
  (* order by vote average and vote_count *)
  let orderBy =
    let q = Bson.add_element "vote_average" (Bson.create_int32 (-1l)) Bson.empty in
    let q = Bson.add_element "vote_count" (Bson.create_int32 (-1l)) q in
    q
  in

  let query = MongoMetaOp.orderBy orderBy Bson.empty in
  (* limit to vote_average that are higher than 3.5 *)
  let query = MongoMetaOp.min (Bson.add_element "vote_average" (Bson.create_double 3.5) Bson.empty) query in

  lwt l = Db.Movie.query ?skip ~limit ~full:true query in
  list_to_client l


let rate : Graph.Movie.key -> Graph.User.key -> int -> unit Lwt.t =
  fun m_uid u_uid rating ->
  (*
     m_n = ((n - 1) * m_n-1 + rating) / n
     => m_n = m_n-1 * (rating - m_n-1) / n (less floating point error)
  *)
    let incremental_mean om oc rating =
      let oc = float_of_int oc in
      let rating = float_of_int rating in
      om +. (rating -. om) /. (oc +. 1.)
    in
    (* remove a rating from the average *)
    let old_mean mean c rating =
      let c = float_of_int c in
      let rating = float_of_int rating in

      (mean *. c -. rating) /. (c -. 1.)
    in

    let rating =
      if rating < 0 then 0
      else if rating > Balsa_config.get_int "max_rating_value" then Balsa_config.get_int "max_rating_value"
      else rating
    in

    lwt old_rating = Rating_request.get_rating Rating_request.Option m_uid u_uid in

    let update_movie =
      lwt _ =
        Db.Movie.find_and_update m_uid (
          fun m ->
            let open Graph.Movie in

            let vote_average,vote_count =
              match old_rating with
                | Some old_rating ->
                  let om = old_mean m.vote_average m.vote_count old_rating.Graph.Rating.rating in
                  incremental_mean om (m.vote_count - 1) rating, m.vote_count
                | None ->
                  incremental_mean m.vote_average m.vote_count rating, m.vote_count + 1
            in

            {
              m with
                vote_average ;
                vote_count ;
            }
        )
      in
      Lwt.return_unit
    in

    let rating =
      Balsa_option.case (
        fun r -> { r with Graph.Rating.rating }
      ) (fun _ ->
          {
            Graph.Rating.uid = Graph.Uid.fresh_uid Graph.Uid.Rating ;
            movie_uid = m_uid ;
            user_uid = u_uid ;
            rating ;
          }
        ) old_rating
    in

    let insert_rating =
      Balsa_option.case
        (fun old_rating -> Db.Rating.update rating)
        (fun _ -> Db.Rating.insert rating)
        old_rating
    in

    let update_user =
      lwt _ =
        Db.User.find_and_update u_uid (
          fun u ->
            Graph.User.({
                u with
                  ratings = Balsa_list.cons_u rating.Graph.Rating.uid u.ratings;
              })
        )
      in
      Lwt.return_unit
    in

    lwt _ =
      Lwt.join [
        update_movie ;
        update_user ;
        insert_rating ;
      ]
    in

    lwt u = Db.User.find u_uid in
    let rating_nb = List.length u.Graph.User.ratings in
    lwt _ =
      if rating_nb = Balsa_config.get_int "minimum_rating_for_suggestion" then begin
        Balsa_log.warning "Starting learning for user %d\n" (Graph.Uid.get_value u_uid);
        let config = Config.web_to_tools () in
        let (user_db,movie_db,genre_db,rating_db) = Db.as_value () in
        lwt _ = Learning.Main.batch_user config genre_db movie_db user_db rating_db u_uid in
        Balsa_log.warning "Finished learning for user %d\n" (Graph.Uid.get_value u_uid);
        Lwt.return_unit
      end else
        Lwt.return_unit
    in

    Lwt.return_unit


let search prefix =
  (* read http://docs.mongodb.org/manual/reference/operator/regex/ before changing regexp.
     /^prefix/ is the faster way to search in index
  *)
  let prefixes = Balsa_string.normalize_split prefix in
  let queries =
    List.map (
      fun prefix ->
        let prefix = "^" ^ (String.lowercase prefix) in
        let regex = Bson.add_element "$regex" (Bson.create_string prefix) Bson.empty in
        let query = Bson.add_element "title_search" (Bson.create_doc_element regex) Bson.empty in
        Bson.create_doc_element query
    ) prefixes
  in

  let query = Bson.add_element "$and" (Bson.create_list queries) Bson.empty in

  let query_ordered = MongoMetaOp.orderBy (Bson.add_element "vote_count" (Bson.create_int32 (-1l)) Bson.empty) query in
  lwt ml = Db.Movie.query ~limit:(Balsa_config.get_int "autocomplete.movie.nb_return") query_ordered in

  list_to_client ml


let what_to_watch u_uid_opt =
  let _suggestion () = () in

  let movie_genre () =
    let rec build_paralel_query acc =
      function
        | [] -> acc
        | g::t ->
          let genre_uid = g.Graph.Genre.uid in

          (* we select movie that have this genre, then sort it by vote_count and vote_average *)
          let query = Bson.add_element "genres" (Bson.create_int64 (Int64.of_int (Graph.Uid.get_value genre_uid))) Bson.empty in
          let orderby = Bson.add_element "vote_average" (Bson.create_int32 (-1l)) Bson.empty in
          let orderby = Bson.add_element "vote_count" (Bson.create_int32 (-1l)) orderby in

          let query_ordered = MongoMetaOp.orderBy orderby query in
          let query_min_ordered = MongoMetaOp.min (Bson.add_element "vote_average" (Bson.create_double 3.5) Bson.empty) query_ordered in

          let movie_query =
            lwt movie = Db.Movie.query ~limit:(Balsa_config.get_int "nb_movie_by_genre") query_min_ordered in
            Lwt.return (g, movie)
          in
          build_paralel_query (movie_query::acc) t
    in

    let rec read_queries acc queries =
      lwt (res_list, thread_list) = Lwt.nchoose_split queries in
      let res_list =
        List.filter (
          fun (_,movie_list) -> List.length movie_list > (Balsa_config.get_int "min_nb_movie_by_genre")
        ) res_list
      in

      let acc = res_list @ acc in

      if Balsa_list.is_empty thread_list then Lwt.return acc
      else
        read_queries acc thread_list
    in

    lwt genres = Db.Genre.query ~full:true Bson.empty in
    let queries = build_paralel_query [] genres in

    lwt l = read_queries [] queries in
    lwt l = Lwt_list.map_s (
      fun (g,m_l) ->
        lwt g = Genre_request.to_client g in
        lwt m_l = list_to_client m_l in
        Lwt.return (g,m_l)
    ) l in

    Lwt.return l
  in

  match u_uid_opt with
    | Some u_uid ->
      lwt u = Db.User.find u_uid in
      let rating_nb = List.length u.Graph.User.ratings in
      if rating_nb < Balsa_config.get_int "minimum_rating_for_suggestion" then
        (* load movie by genres since user didn't rate enough movie *)
        movie_genre ()
      else
        movie_genre () (* to replace by suggestion *)
    | None ->
      movie_genre ()
