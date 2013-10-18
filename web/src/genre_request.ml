{shared{
  type genre = {
    uid: Graph.Genre.key ;
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
  type db_t = Graph.Genre.t
  type uid = Graph.Genre.key
  type client_t = genre

  let to_client g =
    Lwt.return {
      uid = g.Graph.Genre.uid ;
      name = g.Graph.Genre.name ;
    }

  let find = Graph.Db.Genre.find

  let find_all () = Graph.Db.Genre.query ~full:true Bson.empty

end

module DB_r = Db_request.Make (M)
include DB_r
