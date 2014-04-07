{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let container = div ~a:[ a_class ["container"]] []

  let init _ =
    let setup () =
      lwt _ = Config.init () in
      (* facebook may not need to be sync, remove async if problem occured *)
      Lwt.async (fun _ ->
          Balsa_facebook.load_facebook_sdk (Balsa_config.get_string "fb.app-id")
        );

      let b = Bson.add_element "test" (Bson.create_string "works?") Bson.empty in

      Balsa_log.debug "json: %s" (Bson.to_simple_json b);

      Manip.appendToBody (
        div ~a:[ a_class ["full_container"]] [
          div ~a:[ a_class ["fixed_header_hide"]] [];
          Header.header () ;
          Dom_gen.missing_rating_popup ();
          Dom_gen.connect_required_popup ();
          container;
        ]);
      Path.init ();

      (* Check if session value should be update *)
      lwt _ = Connection.check () in

      Lwt.return_unit
    in

    Lwt.async setup

}}
