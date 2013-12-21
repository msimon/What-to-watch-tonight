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

  let single_movie_width = lazy (Balsa_config.get_int "movie_list.single_movie_width")
  let min_movie_per_page = lazy (Balsa_config.get_int "movie_list.min_movie_per_page")

  let dom _ _ =
    let open Movie_request in

    let movie_list_ev,update_movie_list = E.create () in
    let _ =
      Balsa_paging.paginate
        ~step:100
        ~uid_of_data:(fun m -> m.uid)
        ~retrieve:(fun skip limit -> %most_popular_movie (skip,limit))
        ~append:(`Event update_movie_list)
        ~generate_dom:Dom_gen.movie_dom
    in

    let width_stl,update_width_stl = S.create "100%" in

    let movies_dom = div ~a:[ R.a_style width_stl; a_class ["movie_list_in"]] [] in

    let set_last_class () =
      let w = Manip.Attr.offsetWidth movies_dom in
      let nb_display = w / (Lazy.force single_movie_width) in

      let i = ref 0 in
      Balsa_dom.iter_on_children (
        fun el ->
          let el = Html5.Of_dom.of_element el in
          (* add the 'last' class to the last 2 movie on the line *)
          if (nb_display - (!i mod nb_display) - 1) < 2 then Html5.Manip.Class.add el "last"
          else Html5.Manip.Class.remove el "last";
          incr(i);
      ) movies_dom;
    in

    E.iter (
      fun l ->
        List.iter (
          fun el ->
            Manip.appendChild movies_dom el
        ) l;
        set_last_class ();
    ) movie_list_ev;

    (* we are listening on update_movie_list to be sure the movie list is load *)
    E.iter (
      fun _ ->
        let window_size = S.map (
            fun _ ->
              let w = Manip.Attr.offsetWidth movies_dom in
              let nb_display = w / (Lazy.force single_movie_width) in

              let movies_width = nb_display * Lazy.force single_movie_width in
              let movies_width_p1 = (nb_display + 1) * Lazy.force single_movie_width in
              let movies_width_m1 = (nb_display - 1) * Lazy.force single_movie_width in

              let page_width = Balsa_dom.get_browser_page_width () in
              if movies_width > page_width && nb_display > Lazy.force min_movie_per_page then
                update_width_stl (Printf.sprintf "width:%dpx" movies_width_m1)
              else if movies_width < page_width && movies_width_p1 < page_width then
                update_width_stl (Printf.sprintf "width:%dpx" movies_width_p1)
              else
                update_width_stl (Printf.sprintf "width:%dpx" movies_width);

              set_last_class ();
          ) Balsa_dom.window_size
        in

        let rec service_change =
          lazy (S.map (
              fun s ->
                if s <> Path.Popular_movies then begin
                  S.stop (Lazy.force service_change);
                  S.stop window_size
                end
            ) Path.service)
        in
        let _ = Lazy.force service_change in
        ()

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
