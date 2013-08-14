{server{

  let most_popular_movie =
    server_function Json.t<unit> (
      fun () -> Movie_request.most_popular ()
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let dom _ =
    let open Movie_request in

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

    Lwt.return [
      h1 [ pcdata "100 most popular movie" ] ;
      div movies_dom
    ]

  module Page_main = Page.Make(struct
      let service s = (s = Path.What_to_watch)
      let classes = []
      let dom = dom
    end)

}}
