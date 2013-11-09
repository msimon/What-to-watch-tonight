let _ =
  let user_db = (module Db.User : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in
  let movie_db = (module Db.Movie : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let genre_db = (module Db.Genre : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in
  let rating_db = (module Db.Rating : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in
  let config = Config.get () in

  Lwt_main.run (Learning.Main.all config user_db movie_db genre_db rating_db)
