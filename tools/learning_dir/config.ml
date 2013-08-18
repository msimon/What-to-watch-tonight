type database = {
  ip: string ;
  name: string ;
  port: int;
} deriving (Json_ext)

type local_configuration = {
  mutable alpha : float ;
  lambda : float ;
  w2wt: database ;
} deriving (Json_ext)


let init () =
  (* Random.self_init (); *)
  let config_file =
    if Array.length Sys.argv < 2 then "config.json"
    else Sys.argv.(1)
  in

  Json_utils_local_configuration.of_file config_file
