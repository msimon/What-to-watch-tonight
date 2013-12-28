exception Incorrect_response

{shared{
  let _ =
    Lwt.async_exception_hook := (
      fun exn ->
        Balsa_log.warning "Error async: %s" (Printexc.to_string exn)
    )
}}

{shared{

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
  let open Balsa_config in
  let rec build_url () =
    let url = Printf.sprintf "%s%s?api_key=%s" (get_string "api.mock_api") "/3/configuration" (get_string "api.api_key") in
    let headers = [
      "Accept", "application/json"
    ] in

    lwt s,h = Balsa_http.get_url ~headers url () in

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

let lazy_config_moviedb = lazy (
  try_lwt
    fetch_moviedb_configuration ()
  with e ->
    if (Balsa_config.get_bool "allow_default_moviedb_config") then
      Lwt.return ({
          images = {
            base_url = "http://localhost";
            secure_base_url = "http://localhost" ;
            poster_sizes = [] ;
            backdrop_sizes = [] ;
            profile_sizes = [] ;
            logo_sizes = [] ;
          }
        })
    else (raise e)
)

let get_moviedb_conf =
  server_function Json.t<unit> (
    fun () ->
      lwt moviedb_conf = Lazy.force lazy_config_moviedb in
      Lwt.return (moviedb_conf)
  )

let _ =
  Balsa_config.init ()

let cache_lifetime = Balsa_config.get_float "cache.cache_lifetime"
let cache_size = Balsa_config.get_int "cache.cache_size"
let db_ip = Balsa_config.get_string "w2wt_db.ip"
let db_port = Balsa_config.get_int "w2wt_db.port"
let db_name = Balsa_config.get_string "w2wt_db.name"
let query_cache_lifetime = Balsa_config.get_float "db.query_cache_lifetime"

let web_to_tools () =
  let database = {
    Config_t.ip = "" ;
    name = "" ;
    collection = "" ;
    port = 0;
  } in

  let learning = {
    Config_t.alpha = Balsa_config.get_float "learning.alpha" ;
    lambda = Balsa_config.get_float "learning.lambda" ;
  } in

  {
    Config_t.api_url = "" ;
    mock_api = "";
    api_key = "" ;
    max_connections = 0 ;
    request_per_second = 0 ;
    api_db = database ;
    w2wt_db = database ;
    movie_loop_time = 0.;
    sleep_time = 0.;
    learning = learning;
    minimal_vote_count = Balsa_config.get_int "minimum_rating_for_suggestion";
  }


{client{

  let moviedb_conf = ref None

  let init () =
    lwt mc = %get_moviedb_conf () in
    moviedb_conf := Some mc;
    Lwt.return_unit

  let get_moviedb () =
    match !moviedb_conf with
      | Some c -> c
      | None -> failwith "no config ???"

}}
