{shared{
  type genre = {
    uid: Genre_type.key ;
    name: string ;
  }
}}

let genre_to_client g =
  Lwt.return ({
    uid = g.Genre_type.uid ;
    name = g.Genre_type.name ;
  })

let genre_list_to_client l =
  Lwt_list.map_s genre_to_client l

let genre_of_uid uid =
  lwt g = Db.Genre.find uid in
  genre_to_client g

let genre_list_of_uid uids =
  Lwt_list.map_s genre_of_uid uids
