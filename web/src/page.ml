{client{

  open Eliom_content
  open Html5
  open D

  open Balsa_react

  module type M =
  sig
    val service : Path.service -> bool
    val classes : string list
    val dom : Path.service -> unit Balsa_react.event -> [ Html5_types.div_content_fun ] Eliom_content.Html5.D.elt list Lwt.t
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
                let e,u_e = Balsa_react.E.create () in
                Lwt.async (
                  fun _ ->
                    lwt d = M.dom s e in
                    Manip.replaceAllChild (Lazy.force container) d;
                    (* once we are sure the dom has been inserted, we update the event *)
                    u_e ();
                    Lwt.return_unit
                )
              end else
                Manip.replaceAllChild (Lazy.force container) []
          ) Path.service
      ) (E.once Path.init_aux)
  end

}}
