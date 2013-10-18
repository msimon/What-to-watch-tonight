type ('a,_) opt =
  | Option : ('a,'a option) opt
  | Exception : ('a,'a) opt


let get_rating : type t. (Graph_server.Db.Rating.t,t) opt -> Graph_server.Movie.key -> Graph_server.User.key -> t Lwt.t  =
  fun opt m_uid u_uid ->
    let query = Bson.add_element "user_uid" (Graph_server.User.bson_uid u_uid) Bson.empty in
    let query = Bson.add_element "movie_uid" (Graph_server.Movie.bson_uid m_uid) query in

    lwt r = Graph_server.Db.Rating.query_one_no_cache query in

    let t : t =
      match opt with
        | Option ->
          Balsa_option.case
            (fun r -> Some r)
            (fun _ -> None) r
        | Exception ->
          Balsa_option.case
            (fun r -> r)
            (fun _ -> raise Not_found) r
    in
    Lwt.return t

let get_rating_value : type t. (int,t) opt -> Graph_server.Movie.key -> Graph_server.User.key -> t Lwt.t =
  fun opt m_uid u_uid ->
    let t : t Lwt.t =
      match opt with
        | Option ->
          lwt r = get_rating Option m_uid u_uid in
          Lwt.return (
            Balsa_option.case
              (fun r -> Some r.Graph_server.Rating.rating)
              (fun _ -> None) r
          )
        | Exception ->
          lwt r = get_rating Exception m_uid u_uid in
          Lwt.return r.Graph_server.Rating.rating
    in
    t
