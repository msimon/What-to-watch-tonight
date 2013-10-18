open Ocamlbuild_plugin
open Command

let split s ch =
  let s = Printf.sprintf "%s%c" s ch in
  let x = ref [] in
  let i = ref 0 in
  let l = String.length s in
  while !i < l do
    let pos = String.index_from s !i ch in
    x := (String.sub s !i (pos - !i))::!x;
    i:=pos+1
  done;
  List.rev (!x)

let split_nl s = split s '\n'

let read_lines file =
  let chan = open_in file in
  let rec aux l =
    try
      let s=input_line chan in
      if s="" then aux l
      else aux (s::l)
    with End_of_file -> l in
  aux []

let _ =
  let derive_file_list ext =
    rule ("my derive "^" "^ext)
      ~dep:("%(name)"-.-ext)
      ~prod:("%(name)_%(suffix:<*> and not <*_*>)"-.-ext)
      (fun env build ->
	      let name = env "%(name)" in
	      let l = read_lines (name-.-ext) in
	      let init = List.fold_left (fun acc pkg ->
            let aux acc pkg =
              let dir = Pathname.normalize (Filename.dirname pkg) in
              let x = dir^"/"^(env "%(suffix)")^"/"^(Filename.basename pkg)^"\n" in

              if List.mem x acc then acc
              else x::acc
            in
            aux acc pkg) [] l
       in
       Echo (init,(env ("%(name)_%(suffix)"-.-ext)))
      )
  in
  List.iter derive_file_list [ "mlpack"; "mllib" ]

let copy_with_header src prod =
  let dir = Filename.dirname prod in
  let mkdir = Cmd (Sh ("mkdir -p " ^ dir)) in
  let contents = Pathname.read src in
  let header = "# 1 \""^src^"\"\n" in
  (* Printf.printf "copy %s -> %s\n" src prod; *)
  Seq [mkdir;Echo ([header;contents],prod)]

let copy_rule_with_header ?(deps=[]) src prod =
  let name = Printf.sprintf "%s -> %s" src prod in
  (* Printf.printf "copy %s -> %s\n" src prod; *)
  rule name ~deps:(src::deps) ~prod
    (fun env _ ->
      let prod = env prod in
      let src = env src in
      copy_with_header src prod)


(**** .TYPE_MLI ****)

let infer_interface ml type_mli env build =
  let ml = env ml and mli = env type_mli in
  let tags = tags_of_pathname ml++"ocaml" in
  Ocamlbuild_pack.Ocaml_compiler.prepare_compile build ml;
  Cmd(S[!Options.ocamlc; Ocamlbuild_pack.Ocaml_utils.ocaml_ppflags tags; Ocamlbuild_pack.Ocaml_utils.ocaml_include_flags ml; A"-i";
        T(tags++"infer_interface"); P ml; Sh ">"; Px mli])

let derive_infer_interface =
  rule ("derive infer_interface: type_mli")
    ~deps:["src/%(name).ml"]
    ~prod:("src/type_mli/%(name: <*> and not <*.*>).type_mli")
    (fun env build ->
      ignore(build [[env ("src/type_mli/%(name).ml.depends")]]);
      Seq [
        Cmd(S[Sh "mkdir"; P "-p"; P "src/type_mli" ]);
	      infer_interface
	        (* (env ("src/type_mli/%(name).ml")) (\* We find the type from the original file *\) *)
	        (env ("src/type_mli/%(name).ml")) (* We take the env from the server *)
	        (env ("src/type_mli/%(name).type_mli"))
	        env
 	        build
      ]
    )

(* camlp4 special cmd *)

let add_camlp4_pkg pkg =
  let s = Printf.sprintf "ocamlfind query -predicates preprocessor,syntax -r -format \"-I %%d %%A\" %s" (String.concat " " pkg) in
  let p = Ocamlbuild_pack.My_unix.run_and_read s in
  List.map (function
    | "" -> N
    | x -> A x ) (List.rev (List.flatten (List.map (fun s -> split s ' ') (split_nl p))))

let camlp4 ?(default=A"camlp4o") ?tag i o env build =
  let ml = env i in
  let tags = tags_of_pathname ml++"ocaml"++"camlp4o"++"compile"++"byte" in
  let tags = match tag with
    |  None -> tags
    | Some t -> tags++(env t) in
  let _ = Ocamlbuild_pack.Rule.build_deps_of_tags build tags in
  let pp = Command.reduce (Ocamlbuild_pack.Flags.of_tags tags) in
  let pp =
    let rec aux acc inc pkg l =
      match l with
        | [] -> (List.rev (add_camlp4_pkg pkg)) @ (List.rev inc) @(List.rev acc)
        | (A"-ppopt")::x::xs -> aux (x::acc) inc pkg xs
        | (A"-I")::x::xs -> aux acc inc pkg xs
        | (A"-package")::(A x)::xs -> (aux acc inc ((split x ',')@pkg) xs)
        (*   | (A x)::xs when String.length x > 3 && String.sub x 0 3 = "pa_" -> aux ((A x)::acc) inc pkg xs *)
        | _::xs -> aux acc inc pkg xs
    in match pp with
      | S xs -> S (aux [] [] [] xs)
      | x -> x
  in
  let output =
    match o with
      | Some x ->
        let pp_ml = env x in
        [ A"-o"; Px pp_ml]
      | None -> []
  in
  Cmd(S( default :: pp :: (P ml):: (A"-printer"):: (A"o") :: output));;


let _ =
  rule "mypreprocess: ml -> pp.ml"
    ~dep:"%.ml"
    ~prod:"%.pp.ml"
    ~insert:`top
    (camlp4 "%.ml" (Some"%.pp.ml"));

  rule "mypreprocess: ml -> pp.ml.o"
    ~dep:"%.ml"
    ~prod:"%.pp.ml.o"
    ~insert:`top
    (camlp4 "%.ml" None)


let _ = Options.use_ocamlfind := true
let _ = Options.make_links := false

let _ =
  dispatch begin function
    | After_rules ->
      copy_rule_with_header "src/%(name).ml" "src/server/%(name:<*>).ml" ;
      copy_rule_with_header "src/%(name).ml" "src/client/%(name:<*>).ml" ;

      ()

    | _ -> ()
  end
