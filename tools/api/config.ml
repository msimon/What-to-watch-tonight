type database = {
  ip: string ;
  name: string ;
  collection: string ;
  port: int;
} deriving (Json_ext)

type local_configuration = {
  api_url : string ;
  mock_api : string ;
  api_key : string ;
  max_connections : int ;
  request_per_second : int ;
  database: database ;
  movie_loop_time: float;
  sleep_time: float ;
} deriving (Json_ext)


let init () =
  let config_file =
    if Array.length Sys.argv < 3 then "config.json"
    else Sys.argv.(2)
  in

  Json_utils_local_configuration.of_file config_file