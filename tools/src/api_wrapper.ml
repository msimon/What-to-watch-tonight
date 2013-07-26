open Config

exception Incorrect_response
exception Replay_request

type image_conf = {
  base_url : string;
  secure_base_url : string ;
  poster_sizes : string list ;
  backdrop_sizes : string list ;
  profile_sizes : string list ;
  logo_sizes : string list ;
} deriving (Json_ext)

type movidb_configuration = {
  images : image_conf ;
  change_keys : string list ;
} deriving (Json_ext)

type error = {
  status_code : string ;
  status_message: string ;
} deriving (Json_ext)

module Genre_api = struct
  type genre = {
    id: int ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Prod_api = struct
  type production_companies = {
    id: int ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Prod_countries_api = struct
  type production_countries = {
    iso_3166_1: string ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Lang_api = struct
  type spoken_languages = {
    iso_639_1: string;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Movie_api = struct
  type movie = {
    id: int ;
    adult: bool ;
    backdrop_path: string option ;
    budget: int ;
    genres: Genre_api.genre list ;
    homepage: string option ;
    imdb_id: string option ;
    original_title: string ;
    overview: string option ;
    popularity: float ;
    poster_path: string option ;
    production_companies: Prod_api.production_companies list ;
    production_countries: Prod_countries_api.production_countries list ;
    release_date: string ;
    revenue: int;
    runtime: int option;
    spoken_languages: Lang_api.spoken_languages list ;
    status: string;
    tagline: string option;
    title: string;
    vote_average: float;
    vote_count: int;
  } deriving (Json_ext, Bson_ext)
end

let build_url =
  let call_nb = ref 1 in
  let first_time = ref None in
  let sleep_time = 1.3 in
  let retry_after = ref 0 in

  let rec build_url_in ?(params=[]) config ~uri =
    incr(call_nb);
    let call_nb = !call_nb in

    lwt _ =
      match !first_time with
        | None ->
          first_time := Some (Unix.gettimeofday ());
          Lwt.return_unit
        | Some t ->
          let t_ = Unix.gettimeofday () in

          let n = call_nb / config.request_per_second in
          let waiting_time = (float_of_int n) *. sleep_time +. (float_of_int !retry_after) in

          if (t_ -. t < waiting_time) then begin
            Lwt_unix.sleep (waiting_time -. (t_ -. t))
          end else Lwt.return_unit
    in

    let url = Printf.sprintf "%s%s?api_key=%s" config.mock_api uri config.api_key in
    let headers = [
      "Accept", "application/json"
    ] in

    let url =
      List.fold_left (
        fun s (k,v) ->
          s ^ (Printf.sprintf "&%s=%s" k v)
      ) url params
    in

    lwt s,h = Http.get_url ~headers url () in

    if call_nb mod 30 = 0 && call_nb != 0 then Printf.printf "c: %d; t = %f\n%!" call_nb (Unix.gettimeofday ());

    lwt s =
      Ocsigen_http_frame.Http_header.(
        match h.mode with
          | Answer i when i = 200 || i = 304 -> Lwt.return s
          | Answer i when i = 429 ->
            let n = get_headers_value h (Http_headers.name "Retry-After") in
            Printf.printf "retry-after : %s\n%!" n;
            lwt _ = Lwt_unix.sleep (float_of_string n) in
            lwt s = build_url_in ~params config ~uri in
            retry_after := !retry_after + (((int_of_string n) + config.max_connections) / config.max_connections);
            Lwt.return s
          | Answer i when i = 404 ->
            raise Not_found
          | _ ->
            Printf.printf "ir2: %d: %s\n%!" call_nb s;
            raise Incorrect_response
      )
    in


    Lwt.return s
  in
  build_url_in


let fetch_moviedb_configuration config =
  lwt s = build_url config ~uri:"/3/configuration" in
  Lwt.return (Json_ext_movidb_configuration.from_json (Json_ext.from_string s))

let fetch_last_movie config =
  lwt s = build_url config ~uri:"/3/movie/latest" in
   Lwt.return (Movie_api.Json_ext_movie.from_json (Json_ext.from_string s))


let fetch_movie_str config uid =
  build_url config ~uri:(Printf.sprintf "/3/movie/%d" uid)

let fetch_movie config uid =
  lwt s = fetch_movie_str config uid in
  let m = Movie_api.Json_ext_movie.from_json (Json_ext.from_string s) in
  Lwt.return m

let load_movies config mongodb =
  lwt latest_movie = fetch_last_movie config in
  let pool = Lwt_pool.create config.max_connections (fun _ -> Lwt.return_unit) in

  let movie_poll = ref [] in
  let last_call_time = ref None in

  let insert_db () =
    let rec insert_db_in n =
      lwt _ =
        match !last_call_time with
          | None ->
            last_call_time := Some (Unix.time ());
            Lwt.return_unit
          | Some t ->
            let t_ = Unix.time () in
            lwt _ = Lwt_unix.sleep (10. -. (t_ -. t)) in
            last_call_time := Some (Unix.time ());
            Lwt.return_unit
      in

      Printf.printf "inserting %d movies\n%!" (List.length !movie_poll);

      List.iter (
        fun s ->
          try
            let m = Movie_api.Json_ext_movie.from_json (Json_ext.from_string s) in
          (* Printf.printf "Saving : %d\n%!" m.Movie_api.id; *)
            Mongo.insert mongodb [ (Movie_api.Bson_utils_movie.to_bson m) ];
          with exn ->
            Printf.printf "err insert: %s || on %s\n%!" (Printexc.to_string exn) s
      ) !movie_poll;

      (* check if there was any value in movie_poll *)
      let n =
        match !movie_poll with
          | h::_ -> 0
          | _ -> n + 1
      in

      movie_poll := [] ;

      if n < 10 then
        insert_db_in n
      else Lwt.return_unit
    in

    try_lwt
      insert_db_in 0
    with exn ->
      Printf.printf "Error %s\n%!" (Printexc.to_string exn);
      Lwt.return_unit
  in

  let rec fetch_in uid =
    if uid = 0 then Lwt.return_unit
    else begin
      lwt _ =
        Lwt_pool.use pool (
          fun _ ->
            try_lwt
              lwt m = fetch_movie_str config uid in
              movie_poll := m::!movie_poll ;
              (* let m = Movie_api.Bson_utils_movie.to_bson m in *)
              (* Mongo.insert mongodb [ m ]; *)
              Lwt.return_unit
            with _ ->
              Lwt.return_unit
        ) in
      fetch_in (uid - config.max_connections)
    end
  in

  let rec generate_thread n acc =
    if n = 0 then acc
    else
      generate_thread (n - 1) (fetch_in (latest_movie.Movie_api.id - (n - 1))::acc)
  in

  let threads = generate_thread config.max_connections [] in

  Lwt.join ((insert_db ())::threads)


let run config mongodb =
  lwt md_conf = fetch_moviedb_configuration config in
  lwt _ = load_movies config mongodb in
  Mongo.destory mongodb ;
  Lwt.return ()

let _ =
  let config = Config.init () in
  let mongodb = Mongo.create config.database.ip 27017 config.database.name config.database.collection in

  Lwt_main.run (run config mongodb)
