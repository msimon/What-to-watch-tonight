{shared{
  type genre = {
    uid: Genre_type.key ;
    name: string ;
  }
}}

{client{

  module M =
    struct
      type client_t = genre
    end

}}

module M =
struct
  type db_t = Genre_type.t
  type uid = Genre_type.key
  type client_t = genre

  let to_client g =
    Lwt.return {
      uid = g.Genre_type.uid ;
      name = g.Genre_type.name ;
    }

  let find = Db.Genre.find

  let find_all () = Db.Genre.query ~full:true Bson.empty

end

module DB_r = Db_request.Make (M)
include DB_r
