module Graph = Graph_server

let read_params () =
  if Array.length (Sys.argv) = 1 then begin
    Balsa_log.error "%s argument required" Sys.argv.(0);
    Balsa_log.info "Usage:\n-rd : drop and reload all movies. Takes approx 2 days\n-c or --complete: load new movies into db\n-rf or --retry: try to reaload all missing id\n-g or --genres: relaod only the genres list%!";
    exit 0
  end else if Array.length (Sys.argv) > 3 then begin
    Balsa_log.error "Only one argument at a time!";
    exit 0
  end else begin
    match Sys.argv.(1) with
      | "-rd" -> `Reload
      | "--complete" | "-c" -> `Complete
      | "--retry" | "-r" -> `Retry
      | "--genres" | "-g" -> `Genres_only
      | s ->
        Balsa_log.error "Unknow parameter %s\n%!" s;
        exit 0
  end

let run () =
  let user_db = (module Db.User : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in
  let movie_db = (module Db.Movie : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let genre_db = (module Db.Genre : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in
  let rating_db = (module Db.Rating : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in

  let config = Config.get () in
  let action = read_params () in

  Balsa_log.info "Calling MovieDb Api";
  lwt _ = Moviedb.Fetch.run config action in
  Balsa_log.info "Inserting new movies in w2wtDB";
  lwt _ = Convert.Moviedb_to_w2wt.convert config user_db movie_db genre_db rating_db in
  Balsa_log.info "Start learning";
  lwt _ = Learning.Main.batch config user_db movie_db genre_db rating_db in

  lwt _ = Db.User.destory () in
  lwt _ = Db.Movie.destory () in
  lwt _ = Db.Genre.destory () in
  lwt _ = Db.Rating.destory () in

  Lwt.return_unit

let _ =
  Lwt_main.run (run ())
