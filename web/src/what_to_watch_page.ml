{server{

  let what_to_watch =
    server_function Json.t<unit> (
      fun _ ->
        lwt u_uid_opt = Connection.get_uid () in
        Movie_request.what_to_watch u_uid_opt
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react


  let dom _ _ =
    lwt res = %what_to_watch () in

    let container = div [] in

    List.iter (
      fun (genre,movie_list) ->
        let movie_list =
          List.fold_left (
            fun acc m ->
              (Dom_gen.movie_dom m)::acc
          ) [] (List.rev movie_list)
        in

        let movie_prev = div ~a:[ a_class ["movie_list_nav"; "movie_prev"; "websymbols"]; a_style "display:none" ] [ pcdata "<" ]  in
        let movie_next = div ~a:[ a_class ["movie_list_nav"; "movie_next"; "websymbols"]; a_style "display:none" ] [ pcdata ">" ] in
        let movie_list_width = (Balsa_config.get_int "movie_list.single_movie_width") * List.length movie_list in
        let movie_list =
          div ~a:[
            a_class ["movie_list"];
            a_style (Printf.sprintf "width:%dpx\n" movie_list_width)
          ] movie_list
        in

        let movie_list_container = div [
            movie_prev ;
            movie_next ;
            movie_list ;
          ]
        in

        Balsa_dom.toggle_mouse_over movie_list_container (
          fun _ ->
            Balsa_dom.display movie_prev ;
            Balsa_dom.display movie_next ;
        ) (fun _ ->
            Balsa_dom.hide movie_prev ;
            Balsa_dom.hide movie_next ;
          );

        let slide_thread = ref Lwt.return_unit in
        let slide side =
          let rec slide_in =
            function
              | `Left ->
                let left = try Manip.Css.leftPx movie_list with _ -> 0 in
                if left = 0 then Lwt.return_unit
                else begin
                  Manip.SetCss.leftPx movie_list (left + 2);
                  lwt _ = Lwt_js.sleep 0.007 in
                  slide_in `Left
                end
              | `Right ->
                let left = try Manip.Css.leftPx movie_list with _ -> 0 in
                let container_width = Manip.Attr.offsetWidth movie_list_container in
                if left + (movie_list_width - container_width) < 0 then Lwt.return_unit
                else begin
                  Manip.SetCss.leftPx movie_list (left - 2);
                  lwt _ = Lwt_js.sleep 0.007 in
                  slide_in `Right
                end
          in

          slide_thread := slide_in side
        in

        Balsa_dom.toggle_mouse_over movie_prev (
          fun _ ->
            slide `Left
        ) (fun _ ->
            Lwt.cancel !slide_thread
          );

        Balsa_dom.toggle_mouse_over movie_next (
          fun _ ->
            slide `Right
        ) (fun _ ->
            Lwt.cancel !slide_thread
          );


        let d = div ~a:[ a_class [ "genre_movie_list" ] ] [
            h2 [ pcdata genre.Genre_request.name ];
            movie_list_container ;
          ]
        in

        Manip.appendChild container d
    ) res ;

    Lwt.return [container]


  module Page_what_to_watch = Page.Make(struct
      let service s = (s = Path.What_to_watch)
      let dom = dom
      let classes = [ "wtw_page" ]
    end)
}}
