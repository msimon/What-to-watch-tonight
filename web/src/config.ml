exception Incorrect_response

let _ =
  Lwt.async_exception_hook := (
    fun exn ->
      Printf.printf "Async exp: %s\n%!" (Printexc.to_string exn)
  )

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
  fetch_moviedb_configuration ()
)

let get_moviedb_conf =
  server_function Json.t<unit> (
    fun () ->
      lwt moviedb_conf = Lazy.force lazy_config_moviedb in
      Lwt.return (moviedb_conf)
  )


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
