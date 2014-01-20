open Config_t

module Graph = Graph_server

(*

- query db to get most popular movies (1000)
- create 100 users with 100 ratings for these movies

*)

let rate m_uid u_uid rating =
  let incremental_mean om oc rating =
    let oc = float_of_int oc in
    let rating = float_of_int rating in
    om +. (rating -. om) /. (oc +. 1.)
  in

  let rating =
    if rating < 0 then 0
    else if rating > Balsa_config.get_int "max_rating_value" then Balsa_config.get_int "max_rating_value"
    else rating
  in

  let update_movie =
    lwt _ =
      Db.Movie.find_and_update m_uid (
        fun m ->
          let open Graph.Movie in

          let vote_average,vote_count =
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

  let rating = {
    Graph.Rating.uid = Graph.Uid.fresh_uid Graph.Uid.Rating ;
    movie_uid = m_uid ;
    user_uid = u_uid ;
    rating ;
  }
  in

  let insert_rating = Db.Rating.insert rating in

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

  Lwt.join [
    update_movie ;
    update_user ;
    insert_rating ;
  ]

let create_new_user () =
  let uid = Graph.Uid.fresh_uid Graph.Uid.User in
  let user = {
    Graph.User.uid;
    name = Printf.sprintf "user-%d" (Graph.Uid.get_value uid) ;
    ratings = [];
    facebook = Some {
        Graph.User.facebook_uid = string_of_int (Graph.Uid.get_value uid) ;
        facebook_access_token = "" ;
        facebook_access_token_expire_on = 0L ;
      } ;
    vector = [];
    top_movies = [];
  }
  in

  lwt _ = Db.User.insert user in
  Lwt.return uid

let popular_movie () =
  let orderBy =
    let q = Bson.add_element "vote_average" (Bson.create_int32 (-1l)) Bson.empty in
    let q = Bson.add_element "vote_count" (Bson.create_int32 (-1l)) q in
    q
  in

  let query = MongoMetaOp.orderBy orderBy Bson.empty in

  (* limit to vote_average that are higher than 3.5 *)
  let query = MongoMetaOp.min (Bson.add_element "vote_average" (Bson.create_double 3.5) Bson.empty) query in
  lwt l = Db.Movie.query ~limit:1000 ~full:true query in

  Lwt.return (Array.of_list l)

let populate movies max =
  let populate_rating user_uid =
    let rec rate_in n =
      if n >= max then Lwt.return_unit
      else begin
        let rand = Random.int (Array.length movies) in
        let rating = Random.int ((Balsa_config.get_int "max_rating_value") + 1) in
        let m_uid = movies.(rand).Graph.Movie.uid in
        lwt _ = rate m_uid user_uid rating in

        rate_in (n + 1)
      end
    in

    rate_in 0
  in

  let rec populate_in n =
    if (n >= max) then Lwt.return_unit
    else begin
      Balsa_log.info "creating user %d" n;
      lwt user_uid = create_new_user () in
      lwt _ = populate_rating user_uid in
      populate_in (n + 1)
    end
  in

  populate_in 0


let main () =
  lwt movies = popular_movie () in
  lwt _ = populate movies 100 in

  Lwt.return_unit

let _ =
  Random.self_init ();
  Lwt_main.run (main ())
