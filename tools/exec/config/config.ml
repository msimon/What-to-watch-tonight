let __config = ref None
let get () =
  match !__config with
    | Some c -> c
    | None -> failwith ("no config loaded")

let _ =
  let config_file =
    if Array.length Sys.argv < 3 then "config.json"
    else Sys.argv.(2)
  in

  Balsa_config.read_configuration_file config_file;
  __config := Some (Config_t.Yojson_local_configuration.from_json (Yojson.Safe.from_file config_file))

let cache_lifetime = Balsa_config.get_float "cache.cache_lifetime"
let cache_size = Balsa_config.get_int "cache.cache_size"
let db_ip = Balsa_config.get_string "w2wt_db.ip"
let db_port = Balsa_config.get_int "w2wt_db.port"
let db_name = Balsa_config.get_string "w2wt_db.name"
let query_cache_lifetime = Balsa_config.get_float "db.query_cache_lifetime"
