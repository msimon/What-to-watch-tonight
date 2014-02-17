{server{

  exception Not_connected

  let session = Eliom_reference.eref ~persistent:"user_connection" ~scope:Eliom_common.default_session_scope None

  let get_session () = Eliom_reference.get session
  let set_session s = Eliom_reference.set session s
  let remove_session () = Eliom_reference.unset session

  let get_uid_opt () =
    lwt s = get_session () in
    Lwt.return (
      Balsa_option.map (
        fun u -> u.User_request.uid
      ) s
    )

  let get_uid () =
    match_lwt get_uid_opt () with
      | Some u_uid ->
        Lwt.return u_uid
      | None ->
        raise Not_connected


  (** Session keep the value of the user.
     Since there is chance that the user is modify over time
     we make a check each time the app is loaded
  *)
  let check =
    server_function Json.t<unit> (
      fun _ ->
        match_lwt get_session () with
          | Some u ->
            (* Search in db and compare db value with session value *)
            lwt db_u = Db.User.find u.User_request.uid in
            lwt db_u = User_request.to_client db_u in
            if u <> db_u then begin
              lwt _ = set_session (Some db_u) in
              Lwt.return (Some db_u)
            end else Lwt.return_none
          | None ->
            Lwt.return_none
    )

  (** Seems like we don not need it anymore **)
  (* let is_connected = *)
  (*   server_function Json.t<unit> ( *)
  (*     fun _ -> *)
  (*       lwt s = Eliom_reference.get session in *)
  (*       Lwt.return (Balsa_option.is_some s) *)
  (*   ) *)

  (** Todo **)
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
    server_function Json.t<string * string> (
      fun arg ->
       lwt u = User_request.facebook_sign_in arg in
       lwt _ = set_session (Some u) in
       Lwt.return u
    )

  let debug_sign_in =
    server_function Json.t<unit> (
      fun _ ->
        lwt u = Db.User.find (Graph.Uid.unsafe 2) in
        lwt u = (User_request.to_client u) in
        lwt _ = set_session (Some u) in
        Lwt.return u
    )

  let logout =
    server_function Json.t<unit> (
      fun _ ->
        lwt _ = remove_session () in
        Lwt.return_unit
    )

}}

{client{

  open Balsa_react

  (** connected hold the current User_request.user option *)
  let connected,connect = S.create None

  (** This function should be call after page initization
     Since we use a react signal, the page will be updated by itself if a change occured.
     This way, if no change occured (which should be most of the time), we do not block page load.
  *)
  let check () =
    match_lwt %check () with
      | Some s ->
        Balsa_log.debug "Connection: Value in session table and database differ, updating session table";
        connect (Some s);
        Lwt.return_unit
      | None ->
        Balsa_log.debug "Connection: Value in session table and database are the same";
        Lwt.return_unit

  let facebook_connect () =
    try_lwt begin
      match_lwt Balsa_facebook.login ~perms:(Balsa_config.get_string "facebook.perms") with
        | Some s ->
          let fb_id = Js.to_string s##userID in
          let access_token = Js.to_string s##accessToken in
          lwt u = %facebook_sign_in (fb_id,access_token) in
          connect (Some u);
          Lwt.return_unit

        | None ->
          Balsa_log.warning "Facebook connection error";
          failwith "facebook connection abort"
    end with _ ->
      if (Balsa_config.get_bool "debug_mode") then begin
        lwt u = %debug_sign_in () in
        connect (Some u);
        Lwt.return_unit
      end  else begin
        Balsa_log.warning "Facebook connection error";
        failwith "facebook connection abort"
      end

  let logout () =
    (try
      Balsa_facebook.logout ();
    with _ -> ());
    Lwt.async (fun _ -> %logout ());
    connect (None);

}}
