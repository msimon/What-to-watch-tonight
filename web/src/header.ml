{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let header =
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
          input ~input_type:`Text ~a:[ a_placeholder "Search for movies"; a_class ["search"]] ();
          span ~a:[ a_class ["websymbols"; "search_icon"]] [ pcdata "L" ];
          span ~a:[ a_class ["vertical_sep"]] []
        ];
        profile_section;
      ]
    ]
}}
