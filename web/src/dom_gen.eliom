{server{
  let rate_nb =
    server_function Json.t<unit> (
      fun _ ->
        lwt u_uid = Connection.get_uid () in
        lwt u = Db.User.find u_uid in

        if (List.length u.Graph.User.ratings < Balsa_config.get_int "minimum_rating_for_suggestion") then
          lwt movies_uid = Rating_request.get_movies_uid u.Graph.User.ratings in
          Lwt.return (Some (movies_uid))
        else
          Lwt.return None
    )

  let user_rating : (Graph.Movie.key, [ `Average | `Predicted of float | `Rating of int ]) Eliom_pervasives.server_function =
    server_function Json.t<Graph.Movie.key> (
      fun m_uid ->
        lwt u_uid = Connection.get_uid_opt () in
        match_lwt Connection.get_uid_opt () with
          | Some u_uid -> begin
              match_lwt Rating_request.get_rating_value Rating_request.Option m_uid u_uid with
                | Some r ->
                  Lwt.return (`Rating r)
                | None ->
                  lwt u = Db.User.find u_uid in
                  lwt m = Db.Movie.find m_uid in
                  let pr = Learning.Main.predicted_rating u m in
                  Lwt.return (`Predicted pr)
            end
          | None ->
            Lwt.return `Average
    )

  let rate =
    server_function Json.t<Graph.Movie.key * int> (
      fun (m_uid,rating) ->
        lwt u_uid = Connection.get_uid () in
        Movie_request.rate m_uid u_uid rating
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  (*** MISSING RATINGS INFO POPUP **)

  let missing_rating, missing_rating_u = Balsa_react.S.create None
  let add_missing_rating m_uid =
    match S.value missing_rating with
      | Some ratings ->
        if not (List.mem m_uid ratings) then
          missing_rating_u (Some (m_uid::ratings));
      | _ -> ()

  let _ =
    E.iter (
      fun _ ->
        Lwt.async (
          fun _ ->
            lwt ratings = %rate_nb () in
            missing_rating_u ratings ;
            Lwt.return_unit
        )
    ) (E.once Path.init_aux)

  let missing_rating_popup () =
    let min_rate = Balsa_config.get_int "minimum_rating_for_suggestion" in
    R.node (
      S.map (
        function
          | Some ratings when (List.length ratings) < min_rate ->
            div ~a:[ a_class ["missing_cover"]] [
              div [
                p [
                  span [ pcdata "A least" ];
                  span ~a:[ a_class ["number"]] [ pcdata (string_of_int (min_rate - (List.length ratings))) ];
                  span [ pcdata "rating or more are required for suggestions" ]
                ]
              ]
            ]
          | _ ->
            div ~a:[ a_style "display:none" ] []
      ) missing_rating
    )

  (*** RATING STARS **)

  let rating_dom ?lazy_ev m_uid =
    let rating,update_rating = S.create (`Rating 0) in
    let over_rating,update_over_rating = S.create None in

    let fetch_rating () =
      S.iter (
        function
          | Some _ ->
            Lwt.async (
              fun _ ->
                lwt rating = %user_rating m_uid in
                update_rating rating;
                Lwt.return_unit
            );
          | None -> ()
      ) Connection.connected;
    in

    begin match lazy_ev with
      | Some e ->
        E.iter (
          fun _ -> fetch_rating ()
        )(E.once e)
      | None ->
        fetch_rating ()
    end;


    let rating_dom =
      R.node (
        S.l2 (
          fun rating over_r ->
            match rating with
              | `Rating _
              | `Predicted _ ->
                let onclick n =
                  a_onclick (
                    fun _ ->
                      update_rating (`Rating n);
                      Lwt.async (fun _ -> %rate (m_uid,n));
                      add_missing_rating m_uid ;
                      raise Eliom_lib.False
                  )
                in
                let rating_classes, rating_style =
                  match over_r, rating with
                    | Some r, _ ->
                      Balsa_log.debug "over_r : %d" r;
                      ["ratings"; "rated"; (Printf.sprintf "rated_%s" (string_of_int r)) ], ""
                    | None, `Rating r ->
                      Balsa_log.debug "rating : %d" r;
                      [ "ratings"; "rated"; (Printf.sprintf "rated_%s" (string_of_int r)) ], ""
                    (* each rating star are 20% of the width *)
                    | None, `Predicted r ->
                      Balsa_log.debug "predicted : %.2f" r;
                      [ "ratings"; "predicted" ], (Printf.sprintf "width:%f%%" (r *. 20.))
                    | _ -> [], ""
                in

                div [
                  div ~a:[ a_class ["ratings" ] ] [
                  ];
                  div ~a:[ a_class rating_classes; a_style rating_style ] [
                  ];
                  div ~a:[ a_class ["ratings_btn"]; a_onmouseout (fun _ -> update_over_rating None) ] [
                    div ~a:[ onclick 1; a_onmouseover (fun _ -> update_over_rating (Some 1)) ] [ pcdata " " ];
                    div ~a:[ onclick 2; a_onmouseover (fun _ -> update_over_rating (Some 2)) ] [ pcdata " " ];
                    div ~a:[ onclick 3; a_onmouseover (fun _ -> update_over_rating (Some 3)) ] [ pcdata " " ];
                    div ~a:[ onclick 4; a_onmouseover (fun _ -> update_over_rating (Some 4)) ] [ pcdata " " ];
                    div ~a:[ onclick 5; a_onmouseover (fun _ -> update_over_rating (Some 5)) ] [ pcdata " " ];
                  ]
                ]
              | `Average ->
                div ~a:[ a_class ["ratings_container"]] [
                  p [ pcdata "todo: display average" ]
                ]
        ) rating over_rating
      )
    in
    div ~a:[ a_class ["ratings_container"]; a_onmouseout (fun _ -> update_over_rating None) ] [
      rating_dom
    ]


  (*** MOVIE LIST ELEMENT **)

  let movie_dom m =
    let open Movie_request in

    let movie_cover =
      match m.poster_path with
        | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W185 ~src ()
        | None -> Img_gen.default_movie_img ~alt:m.title ()
    in

    let lazy_ev,u_lazy_ev = E.create () in

    div ~a:[ a_class ["movie_in_list"]] [
      div ~a:[ a_onmouseover (fun _ -> u_lazy_ev ())] [
        div ~a:[ a_class ["movie_cover"]] [
          Path.a ~service:(Path.Movie m.uid) [
            div [ movie_cover ];
          ]
        ];
        div ~a:[ a_class ["movie_info"]] [
          div [
            div ~a:[ a_class ["movie_title"]] [
              h3 [
                Path.a ~service:(Path.Movie m.uid) [ pcdata m.title ]
              ]
            ] ;
            Balsa_option.default_f (
              fun overview ->
                div ~a:[ a_class ["movie_description"]] [
                  pcdata (Balsa_string.sub ~max:300 overview);
                  pcdata " ";
                  Path.a ~service:(Path.Movie m.uid) ~a:[ a_class ["more_info_link"]] [ pcdata "More Info"]
                ]
            ) (div ~a:[ a_style "display:none" ] []) m.overview;
            rating_dom ~lazy_ev m.uid
          ]
        ]
      ]
    ]
}}
