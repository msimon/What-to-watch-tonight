{client{

  open Eliom_content
  open Html5
  open D

  let size_to_string =
    function
      | `W92 -> "w92"
      | `W154 -> "w154"
      | `W185 -> "w185"
      | `W342 -> "w342"
      | `W500 -> "w500"
      | `Original -> "original"

  let movie_cover ?(alt="") ~size ~src () =
    let c = Config.get_moviedb () in
    let src = c.Config.images.Config.base_url ^ (size_to_string size)  ^ src in
    img ~src ~alt ()

  let default_movie_img ?(alt="") () =
    let src = Balsa_config.get_string "default_movie_img" in
    img ~src ~alt ()

}}
