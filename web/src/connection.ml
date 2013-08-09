{server{

  let session = Eliom_reference.eref ~persistent:"user_connection" ~scope:Eliom_common.default_session_scope false

  let is_connected =
    server_function Json.t<unit> (
      fun _ ->
        Eliom_reference.get session
    )

  (* let email_sign_in = *)
  (*   server_function Json.t<string> ( *)
  (*     fun (email,pwd) -> *)
  (*       if check then *)
  (*         lwt _ = Eliom_reference.set session true in *)
  (*         Lwt.return_true *)
  (*       else *)
  (*         Lwt.return_false *)
  (*   ) *)

  let facebook_sign_in =
    server_function Json.t<string * string>
    (fun arg ->
       lwt u = User_db_request.facebook_sign_in arg in
       lwt _ = Eliom_reference.set session true in
       Lwt.return u
    )

  let sign_out =
    server_function Json.t<unit> (
      fun _ ->
        lwt _ = Eliom_reference.set session false in
        Lwt.return_false
    )

}}

{client{

  open Balsa_react

  let connected,connect = S.create false

  let facebook_connect () =
    match_lwt Balsa_facebook.login ~perms:(Balsa_config.get_string "facebook.perms") with
      | Some s ->
        let fb_id =  Js.to_string s##userID in
        let access_token = Js.to_string s##accessToken in
        lwt u = %facebook_sign_in (fb_id,access_token) in
        connect true;
        Lwt.return u

      | None ->
        Balsa_log.warning "Facebook connection error";
        failwith "facebook connection abort"

}}
