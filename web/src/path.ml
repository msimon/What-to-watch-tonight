{client{

  open Balsa_react

  type service =
    | Movie of Movie_type.key
    | Profile
    | What_to_watch
    | Taste_profile
    | Popular_movies

  let main_service = What_to_watch

  let path, set_path = S.create ""
  let service,set_service = S.create main_service
  let init_aux,do_init_aux = E.create ()

  let parse s =
    let no_arg f _ = f () in
    let arg_opt_uid f r = match Regexp.matched_group r 1 with
      | None -> main_service
      | Some x -> f (Uid.unsafe (int_of_string x))
    in

    let rec iter = function
      | [] -> None
      | (x,f)::tl ->
        match Regexp.string_match (Regexp.regexp ("^"^x^"$")) s 0 with
          | Some r -> (try Some (f r) with exc -> None)
          | None -> iter tl
    in

    iter [
      "", no_arg (fun () -> main_service);
      "movie/(.+)", arg_opt_uid (fun uid -> Movie uid);
      (* "profile/(.+)", arg_opt_uid (fun uid -> Profile uid); *)
      "profile", no_arg (fun () -> Profile);
      "what_to_watch", no_arg (fun () -> What_to_watch);
      "taste_profile", no_arg (fun () -> Taste_profile);
      "popular_movies", no_arg (fun () -> Popular_movies);
    ]

  let string_of_service = function
    | Movie uid -> Printf.sprintf "movie/%d" (Uid.get_value uid)
    (* | Profile uid -> Printf.sprintf "profile/%d" (Uid.get_value uid) *)
    | Profile -> "profile"
    | What_to_watch -> "what_to_watch"
    | Taste_profile -> "taste_profile"
    | Popular_movies -> "popular_movies"

  let goto s =
    set_service s ;
    Balsa_path.change (string_of_service s)

  let _ =
    S.map (
      fun path ->
        if path <> string_of_service (S.value service) then
          match parse path with
            | None -> set_service main_service
            | Some x -> set_service x
        else ()
    ) path

  let init () =
    Balsa_path.register_on_change (fun _ location _ ->  set_path location);
    set_path (Balsa_path.get ());
    do_init_aux ()


  module Link : sig

    open Eliom_content
    open Html5
    open D

    val a :
      ?a:[<Html5_types.a_attrib > `Href `OnClick] attrib list ->
      ?onclick:(#Dom_html.mouseEvent Js.t -> unit) ->
      service:service ->
      'd elt list -> [> 'd Html5_types.a ] elt

    val a_action :
      ?a:[<Html5_types.a_attrib > `OnClick] attrib list ->
      onclick:(#Dom_html.mouseEvent Js.t -> unit) ->
      'd elt list -> [> 'd Html5_types.a ] elt

    val a_extern :
      ?a:[<Html5_types.a_attrib > `Href `OnClick `Target] attrib list ->
      ?onclick:(#Dom_html.mouseEvent Js.t -> unit) ->
      href:string ->
      'd elt list -> [> 'd Html5_types.a ] elt

    val button :
      ?button_type:[< `Button | `Submit | `Reset  > `Button ] ->
      ?a:[<Html5_types.button_attrib > `OnClick `Button_Type ] attrib list ->
      ?onclick:(#Dom_html.mouseEvent Js.t -> unit) ->
      [<Html5_types.button_content] elt list -> [> Html5_types.button ] elt

  end = struct

    open Eliom_content
    open Html5
    open D

    let middleClick ev =
      match Dom_html.taggedEvent ev with
        | Dom_html.MouseEvent ev ->
          Dom_html.buttonPressed ev = Dom_html.Middle_button
          || Js.to_bool ev##ctrlKey
          || Js.to_bool ev##shiftKey
          || Js.to_bool ev##altKey
          || Js.to_bool ev##metaKey
        | _ -> false


    let a ?(a=[]) ?(onclick=(fun _ -> ())) ~service content =
      let a = (a :> [<Html5_types.a_attrib > `Href `OnClick] attrib list) in
      Raw.a ~a:([
          a_href ("/" ^ (string_of_service service));
          a_onclick (fun e ->
              middleClick e ||
              (
                onclick e;
                goto service;
                Dom_html.stopPropagation e ;
                false
              )
            )]@a) content

    let a_action ?(a=[]) ~onclick content =
      let a = (a :> [<Html5_types.a_attrib > `OnClick] attrib list) in
      Raw.a ~a:([
          a_onclick (fun e ->
              onclick e;
              Dom_html.stopPropagation e ;
              false
            )]@a) content


    let a_extern ?(a=[]) ?(onclick=(fun _ -> ())) ~href content =
      Raw.a ~a:([
          a_href href;
          a_target "_blank";
          a_onclick (fun e ->
              middleClick e ||
              (
                onclick e;
                Dom_html.stopPropagation e ;
                true
              )
            )]@a) content

    let button ?(button_type=`Button)?(a=[]) ?onclick content =
      let onclick = Balsa_option.map (fun f ->
          (fun ev ->
             Dom_html.stopPropagation ev;
             f ev;false)
        ) onclick in
      let a = match onclick with
        | None -> a
        | Some oc -> a_onclick oc :: a in
      let a = a_button_type button_type :: a in
      Raw.button ~a content
  end

  include Link

}}
