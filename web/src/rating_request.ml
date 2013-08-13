type _ opt =
  | Option : Rating_type.t option opt
  | Exception : Rating_type.t opt

let get_rating : type t. t opt -> Movie_type.key -> User_type.key -> t Lwt.t =
  fun opt m_uid u_uid ->
    let query = Bson.add_element "user_uid" (User_type.bson_uid u_uid) Bson.empty in
    let query = Bson.add_element "movie_uid" (Movie_type.bson_uid m_uid) query in

    lwt r = Db.Rating.query_one_no_cache query in

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
