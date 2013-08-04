type database = {
  ip: string ;
  name: string ;
  collection: string ;
  port: int;
} deriving (Json_ext)

type local_configuration = {
  database: database ;
  w2wt: database ;
} deriving (Json_ext)


let init () =
  let config_file =
    if Array.length Sys.argv < 2 then "config.json"
    else Sys.argv.(1)
  in

  Json_utils_local_configuration.of_file config_file
