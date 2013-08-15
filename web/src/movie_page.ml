{server{

  let fetch_movie =
    server_function Json.t<Movie_type.key> (
      fun m_uid ->
        Movie_request.of_uid m_uid
    )

  let rate =
    server_function Json.t<Movie_type.key * int> (
      fun (m_uid,rating) ->
        match_lwt Connection.get_uid () with
          | Some u_uid ->
            Movie_request.rate m_uid u_uid rating
          | None ->
            raise Connection.Not_connected
    )

  let user_rating =
    server_function Json.t<Movie_type.key> (
      fun m_uid ->
        match_lwt Connection.get_uid () with
          | Some u_uid ->
            lwt r = Rating_request.get_rating Rating_request.Exception m_uid u_uid in
            Lwt.return r.Rating_type.rating
          | None ->
            raise Connection.Not_connected
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let dom s =
    let open Movie_request in

    let rating,update_rating = S.create None in
    let uid_of_service = function
      | Path.Movie uid -> uid
      | _ -> assert false
    in

    let m_uid = uid_of_service s in
    lwt m = %fetch_movie m_uid in

    S.iter (
      function
        | Some _ ->
          Lwt.async (
            fun _ ->
              lwt r = %user_rating m_uid in
              update_rating (Some r);
              Lwt.return_unit
          );
        | None -> ()
    ) Connection.connected;

    let pict_dom =
      match m.Movie_request.poster_path with
        | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W342 ~src ()
        | None -> Img_gen.default_movie_img ~alt:m.title ()
    in

    let desc_dom =
      let tagline =
        Balsa_option.default_f
          (fun tagline -> p [ pcdata tagline ])
          (p ~a:[a_style "display_none"] []) m.tagline
      in
      let overview =
        Balsa_option.default_f
          (fun overview -> p [ pcdata overview ])
          (p ~a:[a_style "display_none"] []) m.overview
      in

      let rating_dom =
        R.node (
          S.map (
            fun r ->
              let onclick n =
                a_onclick (
                  fun _ ->
                    update_rating (Some n);
                    Lwt.async (fun _ -> %rate (m_uid,n));
                    false
                )
              in
              let selected n =
                if r = Some n then [ "selected" ]
                else []
              in

              div ~a:[ a_class ["ratings"]] [
                span ~a:[ onclick 1; a_class (selected 1) ] [ pcdata "1" ];
                span ~a:[ onclick 2; a_class (selected 2) ] [ pcdata "2" ];
                span ~a:[ onclick 3; a_class (selected 3) ] [ pcdata "3" ];
                span ~a:[ onclick 4; a_class (selected 4) ] [ pcdata "4" ];
                span ~a:[ onclick 5; a_class (selected 5) ] [ pcdata "5" ];
              ]
          ) rating
        )
      in

      div [
        h1 [ pcdata m.title ];
        rating_dom ;
        div [
          div [
            span [
              pcdata (
                Printf.sprintf "Average of %d rating%s %.1f stars"
                  m.vote_count
                  (if m.vote_count > 1 then "s" else "")
                  m.vote_average
              )
            ]
          ];
          tagline ;
          overview ;
        ]
      ]
    in

    let d = [
      pict_dom ;
      desc_dom ;
    ] in

    Lwt.return d

  module Page_movie = Page.Make(struct
      let service s =
        match s with
          | Path.Movie _ -> true
          | _ -> false

      let dom = dom
      let classes = [ "movie_page" ]
    end)

}}
