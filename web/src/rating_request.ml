type ('a,_) opt =
  | Option : ('a,'a option) opt
  | Exception : ('a,'a) opt


let get_rating : type t. (Db.Rating.t,t) opt -> Graph.Movie.key -> Graph.User.key -> t Lwt.t =
  fun opt m_uid u_uid ->
    let query = Bson.add_element "user_uid" (Graph.User.bson_uid u_uid) Bson.empty in
    let query = Bson.add_element "movie_uid" (Graph.Movie.bson_uid m_uid) query in

    lwt r = Db.Rating.query_one_no_cache query in

    let t : t =
      match opt with
        | Option -> r
        | Exception ->
          Balsa_option.case
            (fun r -> r)
            (fun _ -> raise Not_found) r
    in
    Lwt.return t

let get_rating_value : type t. (int,t) opt -> Graph.Movie.key -> Graph.User.key -> t Lwt.t =
  fun opt m_uid u_uid ->
    let t : t Lwt.t =
      match opt with
        | Option ->
          lwt r = get_rating Option m_uid u_uid in
          Lwt.return (
            Balsa_option.case
              (fun r -> Some r.Graph.Rating.rating)
              (fun _ -> None) r
          )
        | Exception ->
          lwt r = get_rating Exception m_uid u_uid in
          Lwt.return r.Graph.Rating.rating
    in
    t

let get_movies_uid ratings =
  Lwt_list.map_p (
    fun rating ->
      lwt r = Db.Rating.find rating in
      Lwt.return r.Graph.Rating.movie_uid
  ) ratings
