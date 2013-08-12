{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  module type M =
  sig
    val service : Path.service -> bool
    val classes : string list
    val dom : Path.service -> [ Html5_types.div_content_fun ] Eliom_content.Html5.D.elt list Lwt.t

  end

  module type Page = sig end

  module Make (M : M) : Page =
  struct

    let container = lazy (div ~a:[ a_class M.classes ] [])

    let _ =
      E.iter (
        fun _ ->
          S.iter (
            fun s ->
              if M.service s then begin
                Manip.replaceAllChild Main_client.container [ Lazy.force container ] ;
                Lwt.async (
                  fun _ ->
                    lwt d = M.dom s in
                    Manip.replaceAllChild (Lazy.force container) d;
                    Lwt.return_unit
                )
              end else ()
          ) Path.service
      ) (E.once Path.init_aux)
  end

}}
