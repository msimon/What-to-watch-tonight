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
  type db_t = Movie_type.t
  type uid = Movie_type.key
  type client_t = movie

  let to_client m =
    lwt genres = Genre_request.list_of_uid m.Movie_type.genres in
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

  let find = Db.Movie.find

end

module DB_r = Db_request.Make (M)
include DB_r

let most_popular () =
  (* order by vote average and vote_count *)
  let orderBy =
    let q = Bson.add_element "vote_average" (Bson.create_int32 (-1l)) Bson.empty in
    let q = Bson.add_element "vote_count" (Bson.create_int32 (-1l)) q in
    q
  in

  let query = MongoMetaOp.orderBy orderBy Bson.empty in
  (* limit to vote_average that are higher than 3.5 *)
  let query = MongoMetaOp.min (Bson.add_element "vote_average" (Bson.create_double 3.5) Bson.empty) query in

  lwt l = Db.Movie.query ~limit:100 ~full:true query in
  list_to_client l


let rate : Movie_type.key -> User_type.key -> int -> unit Lwt.t =
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
    Db.Movie.find_and_update m_uid (
      fun m ->
        let open Movie_type in

        let vote_average,vote_count =
          match old_rating with
            | Some old_rating ->
              let om = old_mean m.vote_average m.vote_count old_rating.Rating_type.rating in
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

  let rating =
    Balsa_option.case (
      fun r -> { r with Rating_type.rating }
    ) (fun _ ->
        {
          Rating_type.uid = Uid.fresh_uid Uid.Rating ;
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
    Db.User.find_and_update u_uid (
      fun u ->
        User_type.({
            u with
              ratings = Balsa_list.cons_u rating.Rating_type.uid u.ratings;
          })
    )
  in

  Lwt.join [
    update_movie ;
    update_user ;
    insert_rating ;
  ]
