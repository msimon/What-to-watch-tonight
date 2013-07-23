open Ocamlbuild_plugin
open Command

let _ = Options.use_ocamlfind := true
let _ = Options.make_links := false

let _ =
  dispatch begin function
    | After_rules ->
      copy_rule "tools lib" "src/api_wrapper.native" "src/setup_api"

    | _ -> ()
  end
