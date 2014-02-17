{server{

  let what_to_watch =
    server_function Json.t<int * int> (
        fun (top_from, top_to) ->
          lwt u_uid_opt = Connection.get_uid_opt () in
          Movie_request.what_to_watch u_uid_opt top_from top_to
      )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react


  let dom _ _ =
    (* fetching step by step until the server send an empty list *)
    let get_dom () =
      let rec get_top_movie container top_from step =
        lwt res = %what_to_watch (top_from,top_from + step) in

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

            let over = ref None in
            let cancel_over () =
              match !over with
                | Some o ->
                  Lwt.cancel o;
                | None -> ()
            in
            Balsa_dom.toggle_mouse_over movie_list_container (
              fun _ ->
                cancel_over ();
                over := Some (
                    lwt _ = Lwt_js.sleep 0.100 in
                    Balsa_dom.display movie_prev ;
                    Balsa_dom.display movie_next ;
                    Lwt.return_unit
                  )
            ) (fun _ ->
                cancel_over ();
                over := Some (
                    lwt _ = Lwt_js.sleep 0.100 in
                    Balsa_dom.hide movie_prev ;
                    Balsa_dom.hide movie_next ;
                    Lwt.return_unit
                  )
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

            let genre_title =
              Balsa_option.case (
                fun g ->
                  h2 [ pcdata (Printf.sprintf "Top %s" g.Genre_request.name) ]
              ) (fun _ ->
                  R.node (
                    S.map (
                      function
                        | Some u ->
                          h2 [ pcdata (Printf.sprintf "Top 20 for %s" u.User_request.name) ]
                        | None -> h2 ~a:[ a_style "display:none" ] []
                    ) Connection.connected
                  )
                ) genre
            in
            let d = div ~a:[ a_class [ "genre_movie_list" ] ] [
                genre_title ;
                movie_list_container ;
              ]
            in

            Manip.appendChild container d
        ) res ;

        if List.length res = 0 then
          Lwt.return_unit
        else
          get_top_movie container (top_from + step) step
      in

      let container = div [] in
      Lwt.async (fun _ ->
          get_top_movie container 0 5
        );
      Lwt.return container
    in

    let container = div [] in
    S.iter (
      fun _ ->
        Lwt.async (
          fun _ ->
            lwt dom = get_dom () in
            Manip.replaceAllChild container [ dom ];
            Lwt.return_unit
        )
    ) Connection.connected;

    Lwt.return [ container ]

  module Page_what_to_watch = Page.Make(struct
      let service s = (s = Path.What_to_watch)
      let dom = dom
      let classes = [ "wtw_page" ]
    end)
}}
