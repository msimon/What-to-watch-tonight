type genre_list = {
  genres : Api.Genre.t list;
} deriving (Json_ext, Bson_ext)

let fetch_moviedb_configuration config =
  lwt s = Http.build_url config ~uri:"/3/configuration" in
  Lwt.return (Api.Misc.Json_ext_movidb_configuration.from_json (Json_ext.from_string s))

let fetch_last_movie config =
  lwt s = Http.build_url config ~uri:"/3/movie/latest" in
  Lwt.return (Api.Movie.Json_ext_t.from_json (Json_ext.from_string s))

let fetch_movie_str config uid =
  Http.build_url config ~uri:(Printf.sprintf "/3/movie/%d" uid)

let fetch_movie config uid =
  lwt s = fetch_movie_str config uid in
  let m = Api.Movie.Json_ext_t.from_json (Json_ext.from_string s) in
  Lwt.return m

let fetch_genres config =
  lwt s = Http.build_url config ~uri:"/3/genre/list" in
  let g = Json_ext_genre_list.from_json (Json_ext.from_string s) in
  Lwt.return g.genres

let movie_pool = ref []
let add_movie_to_pool m = movie_pool := m::!movie_pool
let last_call_time = ref None

module Mongo = Mongo_lwt

let insert_movie_async mongodb loop_time threads =
  let rec insert_db_in n =
    lwt _ =
      match !last_call_time with
        | None ->
          last_call_time := Some (Unix.time ());
          Lwt.return_unit
        | Some t ->
          let t_ = Unix.time () in
          lwt _ = Lwt_unix.sleep (loop_time -. (t_ -. t)) in
          last_call_time := Some (Unix.time ());
          Lwt.return_unit
    in

    Printf.printf "inserting %d movies\n%!" (List.length !movie_pool);

    List.iter (
      fun s ->
        try
          let m = Api.Movie.Json_ext_t.from_json (Json_ext.from_string s) in
          Lwt.async (fun _ -> Mongo.insert mongodb [ (Api.Movie.Bson_utils_t.to_bson m) ]);
        with exn ->
          Printf.printf "err insert movie: %s || on %s\n%!" (Printexc.to_string exn) s
    ) !movie_pool;

    movie_pool := [] ;

    begin
      match Lwt.state threads with
        | Lwt.Return _ -> Lwt.return_unit
        | _ -> insert_db_in n
    end
  in

  try_lwt
    insert_db_in 0
  with exn ->
    Printf.printf "Error %s\n%!" (Printexc.to_string exn);
    Lwt.return_unit
