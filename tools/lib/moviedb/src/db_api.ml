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
  let g = Api.Genre.Json_ext_genre_list.from_json (Json_ext.from_string s) in
  Lwt.return g.Api.Genre.genres

let fetch_movie_change ?start_date ?end_date ?page config =
  let string_of_date f =
    let t = Unix.localtime f in
    Printf.sprintf "%d-%d-%d" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
  in

  let start_date = Balsa_option.map string_of_date start_date in
  let end_date = Balsa_option.map string_of_date end_date in
  let page = Balsa_option.map (fun p -> string_of_int p) page in

  let params =
    List.fold_left (
      fun acc (k,v) ->
        Balsa_option.case (
          fun v ->
            (k,v)::acc
        ) (fun _ -> acc) v
    ) [] [ ("start_date", start_date); ("end_date", end_date); ("page", page) ]
  in

  lwt s = Http.build_url ~params config ~uri:"/3/movie/changes" in
  let c = Api.Movie_changes.Json_ext_change_list.from_json (Json_ext.from_string s) in
  Lwt.return c

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
