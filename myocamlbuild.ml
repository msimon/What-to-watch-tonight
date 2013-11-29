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


module Ocamlbuild_eliom (
    Client :
    sig
      val client_exec : string option
      val dispatch_default : Ocamlbuild_plugin.hook -> unit
      val server_dir : string
      val type_dir : string
      val client_dir : string
    end) = struct

  open Ocamlbuild_plugin
  module Pack = Ocamlbuild_pack

  let copy_with_header src prod =
    let contents = Pathname.read src in
    let header = "# 1 \"" ^ src ^ "\"\n" in
    Pack.Shell.mkdir_p (Filename.dirname prod);
    Echo ([header; contents], prod)

  let copy_rule_with_header f name ?(deps=[]) src prod =
    rule name ~deps:(src :: deps) ~prod
      (fun env _ ->
         let prod = env prod in
         let src = env src in
         f env (Pathname.dirname prod) (Pathname.basename prod) prod;
         copy_with_header src prod
      )

  let flag_infer file type_inferred =
    let file_tag = "file:" ^ file in
    let tags =
      [["ocaml"; "ocamldep"; file_tag];
       ["ocaml"; "compile"; file_tag];
       ["ocaml"; "infer_interface"; file_tag];
      ]
    in
    let f tags =
      flag tags (S [A "-ppopt"; A "-type"; A "-ppopt"; P type_inferred])
    in
    List.iter f tags;
    flag ["ocaml"; "doc"; file_tag] (S [A "-ppopt"; A "-notype"])

  let copy_rule_server =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let type_inferred =
           Pathname.concat
             (Pathname.concat path Client.type_dir)
             (Pathname.update_extension "inferred.mli" name)
         in
         tag_file file
           [ "pkg_eliom.server"; "pkg_eliom.syntax.server"; "thread";
             "syntax_camlp4o";
           ];
         flag_infer file type_inferred;
         Pathname.define_context dir [path];
         Pathname.define_context path [dir];
      )

  let copy_rule_client =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let type_inferred =
           Pathname.concat
             (Pathname.concat path Client.type_dir)
             (Pathname.update_extension "inferred.mli" name)
         in
         tag_file file
           [ "pkg_eliom.client"; "pkg_eliom.syntax.client"; "thread";
             "syntax_camlp4o";
           ];
         flag_infer file type_inferred;
         Pathname.define_context dir [path];
      )

  let copy_rule_type =
    copy_rule_with_header
      (fun env dir name file ->
         let path = env "%(path)" in
         let server_dir = Pathname.concat path Client.server_dir in
         (* let server_file = Pathname.concat server_dir name in *)
         tag_file file
           ( "pkg_eliom.syntax.type" :: "thread" :: "syntax_camlp4o" :: []
           );
         Pathname.define_context dir [path; server_dir];
      )

  let js_rule () =
    let linker tags deps out =
      Cmd (S [A "js_of_eliom"; T tags;
              Command.atomize_paths deps; A "-o"; Px out])
    in
    rule "js_of_eliom: .cmo -> .js" ~dep:"%.cmo" ~prod:"%.js"
      (fun env ->
         Pack.Ocaml_compiler.link_gen
           "cmo" "cma" "cma" ["cmo"; "cmi"] linker
           (fun tags ->
              Tags.union
                (tags_of_pathname (env "%.ml"))
                (tags++"ocaml"++"link"++"byte"++"jslink"++"js_of_eliom")
           )
           "%.cmo" "%.js"
           env
      )

  let add_to_targets () =
    match Client.client_exec with
      | None -> ()
      | Some x -> Options.targets @:= [x]

  let dispatch_default hook =
    Client.dispatch_default hook;
    match hook with
      | After_options ->
        add_to_targets ();
      | After_rules ->
        js_rule ();

        (* copy_rule_server "*.ml -> **/_server/*.ml" *)
        (*   ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"] *)
        (*   "%(path)/%(name).ml" *)
        (*   ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).ml"); *)

        (* copy_rule_server "*.ml -> **/_client/*.ml" *)
        (*   ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"] *)
        (*   "%(path)/%(name).ml" *)
        (*   ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).ml"); *)

        (* copy_rule_server "*.ml -> **/_server/*.ml" *)
        (*   ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"] *)
        (*   "%(path)/%(name).ml" *)
        (*   ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).ml"); *)

        (* copy_rule_with_header "*.ml -> **/client/*.ml" "%(path)/%(name).ml" "%(path)/client/%(name:<*>).ml" ; *)
        (* copy_rule_with_header "*.ml -> **/type_mli/*.ml" "%(path)/%(name).ml" "%(path)/type_mli/%(name:<*>).ml" ; *)

        copy_rule_server "*.eliom -> **/_server/*.ml"
          ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"]
          "%(path)/%(file).eliom"
          ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).ml");
        copy_rule_server "*.eliomi -> **/_server/*.mli"
          "%(path)/%(file).eliomi"
          ("%(path)/" ^ Client.server_dir ^ "/%(file:<*>).mli");
        copy_rule_type "*.eliom -> **/_type/*.ml"
          "%(path)/%(file).eliom"
          ("%(path)/" ^ Client.type_dir ^ "/%(file:<*>).ml");
        copy_rule_type "*.eliomi -> **/_type/*.mli"
          "%(path)/%(file).eliomi"
          ("%(path)/" ^ Client.type_dir ^ "/%(file:<*>).mli");
        copy_rule_client "*.eliom -> **/_client/*.ml"
          ~deps:["%(path)/" ^ Client.type_dir ^ "/%(file).inferred.mli"]
          "%(path)/%(file).eliom"
          ("%(path)/" ^ Client.client_dir ^ "/%(file:<*>).ml");
        copy_rule_client "*.eliomi -> **/_client/*.mli"
          "%(path)/%(file).eliomi"
          ("%(path)/" ^ Client.client_dir ^ "/%(file:<*>).mli");

        copy_rule_server "*.eliom -> _server/*.ml"
          ~deps:[Client.type_dir ^ "/%(file).inferred.mli"]
          "%(file).eliom" (Client.server_dir ^ "/%(file:<*>).ml");
        copy_rule_server "*.eliomi -> _server/*.mli"
          "%(file).eliomi" (Client.server_dir ^ "/%(file:<*>).mli");
        copy_rule_type "*.eliom -> _type/*.ml"
          "%(file).eliom" (Client.type_dir ^ "/%(file:<*>).ml");
        copy_rule_type "*.eliomi -> _type/*.mli"
          "%(file).eliomi" (Client.type_dir ^ "/%(file:<*>).mli");
        copy_rule_client "*.eliom -> _client/*.ml"
          ~deps:[Client.type_dir ^ "/%(file).inferred.mli"]
          "%(file).eliom" (Client.client_dir ^ "/%(file:<*>).ml");
        copy_rule_client "*.eliomi -> _client/*.mli"
          "%(file).eliomi" (Client.client_dir ^ "/%(file:<*>).mli");
      | _ -> ()
end;;

let _ = Options.use_ocamlfind := true
let _ = Options.make_links := false

let dispatch_default =
  function
    | After_rules ->
      ocaml_lib ~extern:true ~dir:"./type/graph" "./type/graph/graph_server" ;
      ocaml_lib ~extern:true ~dir:"./type/graph" "./type/graph/graph_client" ;
      ocaml_lib ~extern:true ~dir:"./type/api" "./type/api/api" ;

      ocaml_lib ~extern:true ~dir:"./tools/lib/moviedb" "./tools/lib/moviedb/moviedb" ;
      ocaml_lib ~extern:true ~dir:"./tools/lib/convert" "./tools/lib/convert/convert" ;
      ocaml_lib ~extern:true ~dir:"./tools/lib/learning" "./tools/lib/learning/learning" ;
    | _ -> ()


module M = Ocamlbuild_eliom(struct
    let client_exec = None
    let dispatch_default = dispatch_default
    let client_dir = "client"
    let server_dir = "server"
    let type_dir = "type_mli"
  end);;

Ocamlbuild_plugin.dispatch M.dispatch_default;;
