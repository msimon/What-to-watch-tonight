{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react


  let movie_dom m =
    let open Movie_request in

    let movie_cover =
      match m.poster_path with
        | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W185 ~src ()
        | None -> Img_gen.default_movie_img ~alt:m.title ()
    in

    div ~a:[ a_class ["movie_in_list"]] [
      div [
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
            ) (div ~a:[ a_style "display:none" ] []) m.overview
          ]
        ]
      ]
    ]
}}
