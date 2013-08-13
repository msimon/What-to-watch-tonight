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
              Path.a ~service:Path.Profile [ pcdata u.User_request.name ]
            | None ->
              span [
                button ~button_type:`Button ~a:[ a_onclick (fun _ -> Lwt.async (fun _ -> Connection.facebook_connect ()); false) ] [ pcdata "facebook connect" ];
              ]
        ) Connection.connected
      )
    in

    div ~a:[ a_class ["header"; "connected"]] [
      div ~a:[ a_class ["logo"]] [
        Path.a ~service:Path.Main [
          pcdata "W2WT"
        ]
      ];
      div ~a:[ a_class ["section"]] [
        ul [
          li [
            Path.a ~service:Path.What_to_watch [
              pcdata "What to Watch ?"
            ]
          ];
          li [
            Path.a ~service:Path.Popular_movies [
              pcdata "Popular of W2wt"
            ]
          ];
          li [
            Path.a ~service:Path.Taste_profile [
              pcdata "Taste Profile"
            ]
          ];
        ];
      ];
      div ~a:[ a_class ["last"]] [
        input ~input_type:`Text ~a:[ a_class ["search"]] ();
        profile_section;
      ]
    ]
}}
