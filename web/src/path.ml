{client{

  open Balsa_react

  type service =
    | Main
    | Movie of Movie_type.key
    | User of User_type.key

  let path, set_path = S.create ""
  let service,set_service = S.create Main
  let init_aux,do_init_aux = E.create ()

  let parse s =
    let no_arg f _ = f () in
    let arg_opt_uid f r = match Regexp.matched_group r 1 with
      | None -> Main
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
      "", no_arg (fun () -> Main);
      "movie/(.+)", arg_opt_uid (fun uid -> Movie uid);
      "user/(.+)", arg_opt_uid (fun uid -> User uid);
    ]

  let string_of_service = function
    | Main -> ""
    | Movie uid -> Printf.sprintf "movie/%d" (Uid.get_value uid)
    | User uid -> Printf.sprintf "user/%d" (Uid.get_value uid)

  let goto s =
    set_service s ;
    Balsa_path.change (string_of_service s)

  let _ =
    S.map (
      fun path ->
        if path <> string_of_service (S.value service) then
          match parse path with
            | None -> set_service Main
            | Some x -> set_service x
        else ()
    ) path

  let init () =
    Balsa_path.register_on_change (fun _ location _ ->  set_path location);
    set_path (Balsa_path.get ());
    do_init_aux ()
}}
