{server{

  let fetch_movie =
    server_function Json.t<Graph.Movie.key> (
      fun m_uid ->
        Movie_request.of_uid m_uid
    )

}}

{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  let dom s _ =
    let open Movie_request in

     let uid_of_service = function
      | Path.Movie uid -> uid
      | _ -> assert false
    in

    let m_uid = uid_of_service s in
    lwt m = %fetch_movie m_uid in

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

      div [
        h1 [ pcdata m.title ];
        Dom_gen.rating_dom m_uid ;
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
