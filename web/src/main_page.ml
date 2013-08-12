{server{

  let most_popular_movie =
    server_function Json.t<unit> (
      fun () -> Movie_db_request.most_popular ()
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let dom _ =
    let open Movie_db_request in

    lwt movies = %most_popular_movie () in

    let movies_dom =
      List.map (
        fun m ->
          let movie_cover =
            match m.poster_path with
              | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W185 ~src ()
              | None -> Img_gen.default_movie_img ~alt:m.title ()
          in

          div ~a:[ a_class ["movie"]; a_onclick (fun _ -> Path.goto (Path.Movie m.uid); false) ] [
            div [ movie_cover ];
            div [
              span [ pcdata m.title ];
              span [ pcdata (Printf.sprintf "(%.1f)" m.vote_average)]
            ];
          ]
      ) movies
    in

    let connected = R.node (
        S.map (fun s ->
            match s with
              | None -> p [ pcdata "not connected" ]
              | Some u ->
                p [ pcdata (Printf.sprintf "Connected as %s" u.User_db_request.name) ]
          ) Connection.connected
      )
    in

    Lwt.return [
      button ~button_type:`Button ~a:[ a_onclick (fun _ -> Lwt.async (fun _ -> Connection.facebook_connect ()); false) ] [ pcdata "facebook_connect" ];
      connected ;
      h1 [ pcdata "100 most popular movie" ] ;
      div movies_dom
    ]

  module Page_main = Page.Make(struct
      let service s = (s = Path.Main)
      let classes = []
      let dom = dom
    end)

}}