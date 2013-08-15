{server{

  let most_popular_movie =
    server_function Json.t<int * int> (
      fun (skip,limit) -> Movie_request.most_popular ~skip ~limit ()
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let dom _ =
    let open Movie_request in

    let movies_dom = div [] in
    let _ =
      Balsa_paging.paginate
        ~step:100
        ~uid_of_data:(fun m -> m.uid)
        ~retrieve:(fun skip limit -> %most_popular_movie (skip,limit))
        ~append:(`Dom movies_dom)
        ~generate_dom:(
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
        )
    in

    Lwt.return [
      h1 [ pcdata "100 most popular movie" ] ;
      movies_dom
    ]

  module Page_main = Page.Make(struct
      let service s = (s = Path.Popular_movies)
      let classes = []
      let dom = dom
    end)

}}
