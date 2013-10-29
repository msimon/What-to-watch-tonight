module Graph = Graph_server
open Convert.Moviedb_to_w2wt

let run () =
  let user_db = (module Db.User : Graph.Db.Sig with type t = Graph.User.t and type key = Graph.User.key) in
  let movie_db = (module Db.Movie : Graph.Db.Sig with type t = Graph.Movie.t and type key = Graph.Movie.key) in
  let genre_db = (module Db.Genre : Graph.Db.Sig with type t = Graph.Genre.t and type key = Graph.Genre.key) in
  let rating_db = (module Db.Rating : Graph.Db.Sig with type t = Graph.Rating.t and type key = Graph.Rating.key) in

  let config = Config.get () in

  convert config user_db movie_db genre_db rating_db
