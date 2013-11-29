module User = Graph_server.Db.User (Config)
module Movie = Graph_server.Db.Movie (Config)
module Genre = Graph_server.Db.Genre (Config)
module Rating = Graph_server.Db.Rating (Config)

let as_value () =
  let user_db = (module User : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in
  let movie_db = (module Movie : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let genre_db = (module Genre : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in
  let rating_db = (module Rating : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in

  (user_db,movie_db,genre_db,rating_db)
