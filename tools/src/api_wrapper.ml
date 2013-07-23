open Config

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


type movie = {
  id : int
} deriving (Json_ext)

type error = {
  status_code : string ;
  status_message: string ;
} deriving (Json_ext)

let call_nb = ref 1
let last_call_time = ref None

let build_url ?(params=[]) config ~uri =
  incr(call_nb);
  lwt _ =
    match !last_call_time with
      | Some (cn, f) when !call_nb - cn >= config.request_per_second ->
        let t = Unix.time () in
        Printf.printf "Sleeping for %f\n%!" (1.05 -. (t -. f));
        lwt _ = Lwt_unix.sleep (1.05 -. (t -. f)) in
        last_call_time := None;
        Lwt.return_unit
      | _ -> Lwt.return_unit
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

  lwt s,_ = Http.get_url ~headers url () in

  (* let h = Ocsigen_http_frame.Http_header.get_headers_value h Http_headers.status in *)
  (* Printf.printf "s: %s\n%!" h; *)

  begin match !last_call_time with
      | Some n -> ()
      | None -> last_call_time := Some (!call_nb, Unix.time ())
  end;

  Lwt.return s


let fetch_moviedb_configuration config =
  lwt s = build_url config ~uri:"/3/configuration" in
  Lwt.return (Json_ext_movidb_configuration.from_json (Json_ext.from_string s))

let fetch_last_movie config =
  lwt s = build_url config ~uri:"/3/movie/latest" in
  Lwt.return (Json_ext_movie.from_json (Json_ext.from_string s))

let fetch_movie config uid =
  lwt s = build_url config ~uri:(Printf.sprintf "/3/movie/%d" uid) in
  try_lwt
    let _ = Json_ext_movie.from_json (Json_ext.from_string s) in
    Lwt.return_unit;
  with _ ->
    Lwt.return_unit


let load_movies config =
  lwt latest_movie = fetch_last_movie config in
  let pool = Lwt_pool.create config.max_connections (fun _ -> Lwt.return_unit) in

  let rec fetch_in uid =
    Printf.printf "fetch : %d\n%!" uid;
    if uid = 0 then Lwt.return_unit
    else begin
      lwt _ =
        Lwt_pool.use pool (
          fun _ ->
            fetch_movie config uid
        ) in
      fetch_in (uid - config.max_connections)
    end
  in

  let rec generate_thread n acc =
    if n = 0 then acc
    else
      generate_thread (n - 1) (fetch_in (latest_movie.id - (n - 1))::acc)
  in

  let threads = generate_thread config.max_connections [] in

  Lwt.join threads


let run config =
  (* lwt md_conf = fetch_moviedb_configuration config in *)
  lwt _ = load_movies config in
  Lwt.return ()


let _ =
  let config = Config.init () in

  Lwt_main.run (run config)
