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

  let single_movie_width = lazy(Balsa_config.get_int "movie_list.single_movie_width")

  let dom _ _ =
    let open Movie_request in

    let movie_list_ev,update_movie_list = E.create () in
    let _ =
      Balsa_paging.paginate
        ~step:100
        ~uid_of_data:(fun m -> m.uid)
        ~retrieve:(fun skip limit -> %most_popular_movie (skip,limit))
        ~append:(`Event update_movie_list)
        ~generate_dom:(
          fun m ->
            let movie_cover =
              match m.poster_path with
                | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W185 ~src ()
                | None -> Img_gen.default_movie_img ~alt:m.title ()
            in

            div ~a:[ a_class ["movie"]] [
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
        )
    in

    let movies_dom = div ~a:[ a_class ["movie_list_in"]] [] in
    E.iter (
      fun l ->
        List.iter (
          fun el ->
            Manip.appendChild movies_dom el
        ) l
    ) movie_list_ev;

    (* we are listening on bottom_page_ev to be sure the movie list is load *)
    E.iter (
      fun _ ->
        S.iter (
          fun _ ->
            let w = Manip.Attr.offsetWidth movies_dom in
            let nb_display = w / (Lazy.force single_movie_width) in
            let i = ref 0 in

            Balsa_dom.iter_on_children (
              fun el ->
                let el = Html5.Of_dom.of_element el in
                if (nb_display - (!i mod nb_display) - 1) < 2 then Html5.Manip.Class.add el "last"
                else Html5.Manip.Class.remove el "last";
                incr(i);
            ) movies_dom
        ) Balsa_dom.window_size;
    ) (E.once movie_list_ev) ;

    Lwt.return [
      div ~a:[ a_class ["movie_list"]] [
        movies_dom
      ]
    ]

  module Page_main = Page.Make(struct
      let service s = (s = Path.Popular_movies)
      let classes = [ "popular_movies" ]
      let dom = dom
    end)

}}
