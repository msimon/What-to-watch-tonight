exception Incorrect_response

let _ =
  Lwt.async_exception_hook := (
    fun exn ->
      Printf.printf "Async exp: %s\n%!" (Printexc.to_string exn)
  )

type db = {
  ip: string ;
  name: string ;
  port: int;
} deriving (Json_ext)

type cache = {
  cache_timer: float ;
  cache_size: int ;
} deriving (Json_ext)

type api = {
  api_url : string;
  mock_api: string;
  api_key: string;
} deriving (Json_ext)

type conf = {
  db: db ;
  cache: cache ;
  api : api ;
} deriving (Json_ext)


let lazy_config = lazy (
  Json_utils_conf.of_file "public/config.json"
)

let get () =
  Lazy.force lazy_config


{shared{

  type client_conf = {
    default_movie_img : string ;
  } deriving (Json_ext)

  type image_conf = {
    base_url : string;
    secure_base_url : string ;
    poster_sizes : string list ;
    backdrop_sizes : string list ;
    profile_sizes : string list ;
    logo_sizes : string list ;
  } deriving (Json_ext)

  type themoviedb_conf = {
    images: image_conf
  } deriving (Json_ext)

}}


let fetch_moviedb_configuration () =
  let config = get () in
  let rec build_url () =
    let url = Printf.sprintf "%s%s?api_key=%s" config.api.mock_api "/3/configuration" config.api.api_key in
    let headers = [
      "Accept", "application/json"
    ] in

    lwt s,h = Http.get_url ~headers url () in

    Ocsigen_http_frame.Http_header.(
      match h.mode with
        | Answer i when i = 200 || i = 304 -> Lwt.return s
        | Answer i when i = 429 ->
          let n = get_headers_value h (Http_headers.name "Retry-After") in
          (* Printf.printf "retry-after : %s\n%!" n; *)
          lwt _ = Lwt_unix.sleep (float_of_string n) in
          lwt s = build_url () in
          Lwt.return s
        | Answer i when i = 404 ->
          raise Not_found
        | _ ->
          raise Incorrect_response
    )
  in

  lwt s = build_url () in
  Lwt.return (Json_ext_themoviedb_conf.from_json (Json_ext.from_string s))


let lazy_config_client = lazy (
  Json_utils_client_conf.of_file "public/config_client.json"
)
let lazy_config_moviedb = lazy (
  fetch_moviedb_configuration ()
)

let client_get_config =
  server_function Json.t<unit> (
    fun () ->
      lwt moviedb_conf = Lazy.force lazy_config_moviedb in
      let client_conf = Lazy.force lazy_config_client in
      Lwt.return (client_conf,moviedb_conf)
  )


{client{

  let client_conf = ref None
  let moviedb_conf = ref None

  let init () =
    lwt cc,mc = %client_get_config () in
    client_conf := Some cc;
    moviedb_conf := Some mc;
    Lwt.return_unit

  let get_client () =
    match !client_conf with
      | Some c -> c
      | None -> failwith "no config ???"

  let get_moviedb () =
    match !moviedb_conf with
      | Some c -> c
      | None -> failwith "no config ???"

}}
