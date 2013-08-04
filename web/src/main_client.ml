{client{

  open Eliom_content
  open Html5
  open D

  let main_dom () =
    div [ h1 [pcdata "yess"]]

  let init _ =
    Manip.appendToBody (main_dom ())

}}
