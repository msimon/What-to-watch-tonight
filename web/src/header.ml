{server{

  let search =
    server_function Json.t<string> (
      fun prefix ->
        Movie_request.search prefix
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let header () =
    let profile_section =
      R.node (
        S.map (
          function
            | Some u ->
              Path.a ~service:Path.Profile [
                div [
                  Img_gen.profile_picture u ;
                  span [ pcdata u.User_request.name ];
                  span ~a:[ a_class ["vertical_sep"]] [];
                ]
              ]
            | None ->
              div [
                button ~button_type:`Button ~a:[ a_onclick (fun _ -> Lwt.async (fun _ -> Connection.facebook_connect ()); false) ] [ pcdata "facebook connect" ];
              ]
        ) Connection.connected
      )
    in

    let links =
      R.node (
        S.map (
          fun p ->
            let selected p_ =
              if p = p_ then [ "selected" ]
              else []
            in
            ul [
              li [
                Path.a ~service:Path.What_to_watch ~a:[ a_class (selected Path.What_to_watch) ] [
                  pcdata "What to Watch ?"
                ];
                span ~a:[ a_class ["vertical_sep"]] []
              ];
              li [
                Path.a ~service:Path.Popular_movies ~a:[ a_class (selected Path.Popular_movies) ] [
                  pcdata "Most Popular Movies"
                ];
                span ~a:[ a_class ["vertical_sep"]] []
              ];
              li [
                Path.a ~service:Path.Taste_profile ~a:[ a_class (selected Path.Taste_profile) ] [
                  pcdata "Taste Profile"
                ];
                span ~a:[ a_class ["vertical_sep"]] []
              ];
            ];
        ) Path.service
      )
    in

    let movie_search  =
      let handle_confirmation_selected m =
        Path.goto (Path.Movie m.Movie_request.uid)
      in

      let handle_confirmation_noselection s =
        Balsa_log.debug "go to search page: %s" s
      in

      let create_suggestion_li m = [ pcdata m.Movie_request.title ],[] in

      Balsa_autocomplete.create
        ~handle_confirmation_selected
        ~handle_confirmation_noselection
        ~create_suggestion_li
        ~retrieve_suggestions:(fun prefix -> %search prefix)
        ~select_is_confirm:true
        ~display_no_result:(pcdata "No result")
        ~placeholder:"Search for movies"
        ~a:[ a_class ["search"]]
        ~string_of_value:(fun m -> m.Movie_request.title)
        ()
    in

    div ~a:[ a_class ["header"; "connected"]] [
      div ~a:[ a_class ["logo"]] [
        Path.a ~service:Path.main_service [
          pcdata "W2WT"
        ];
        span ~a:[ a_class ["vertical_sep"]] []
      ];
      div ~a:[ a_class ["section"]] [
        links ;
      ];
      div ~a:[ a_class ["last"]] [
        div [
          Balsa_autocomplete.node movie_search ;
          span ~a:[ a_class ["websymbols"; "search_icon"]] [ pcdata "L" ];
          span ~a:[ a_class ["vertical_sep"]] []
        ];
        profile_section;
      ]
    ]
}}
