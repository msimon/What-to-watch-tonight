{server{

  let most_popular_movie =
    server_function Json.t<unit> (
      fun () -> Movie_db_request.most_popular_movie ()
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  let main_dom () =
    lwt movies = %most_popular_movie () in

    let movies_dom =
      List.map (
        fun m ->
          let movie_cover =
            match m.Movie_db_request.poster_path with
              | Some src -> Img_gen.movie_cover ~alt:m.Movie_db_request.title ~size:`W185 ~src ()
              | None -> Img_gen.default_movie_img ~alt:m.Movie_db_request.title ()
          in

          div ~a:[ a_class ["movie"]] [
            div [ movie_cover ];
            div [
              span [ pcdata m.Movie_db_request.title ];
              span [ pcdata (Printf.sprintf "(%.f)" m.Movie_db_request.vote_average)]
            ];
          ]
      ) movies
    in

    let d =
      div [
        h1 [ pcdata "100 most popular movie" ] ;
        div movies_dom
      ]
    in

    Lwt.return d

  let init _ =
    let setup () =
      lwt _ = Config.init () in
      lwt d = main_dom () in
      Manip.appendToBody d;
      Lwt.return_unit
    in

    Lwt.async setup

}}
