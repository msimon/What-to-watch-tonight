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
      div ~a:[ a_class ["pict_dom"]] [
        match m.Movie_request.poster_path with
          | Some src -> Img_gen.movie_cover ~alt:m.title ~size:`W342 ~src ()
          | None -> Img_gen.default_movie_img ~alt:m.title ()
      ]
    in

    let desc_dom =
      let tagline =
        Balsa_option.default_f
          (fun tagline -> p ~a:[ a_class ["tagline"]] [ pcdata tagline ])
          (p ~a:[a_style "display_none"] []) m.tagline
      in
      let overview =
        Balsa_option.default_f
          (fun overview -> p ~a:[ a_class ["overview"]] [ pcdata overview ])
          (p ~a:[a_style "display_none"] []) m.overview
      in

      div ~a:[ a_class ["description_dom"]] [
        div [
          h1 ~a:[ a_style (match m.tagline with | Some t -> "margin-bottom:0" | None -> "")] [
            pcdata m.title
          ];
          tagline ;
        ];
        Dom_gen.rating_dom ~t:`Extended m ;
        div [
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
      let classes = [ "movie_page"; "clearfix" ]
    end)

}}
