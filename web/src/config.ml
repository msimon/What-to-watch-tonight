type db = {
  ip: string ;
  name: string ;
  collection: string ;
  port: int;
} deriving (Json_ext)

type cache = {
  cache_timer: float ;
  cache_size: int ;
} deriving (Json_ext)

type conf = {
  db: db ;
  cache: cache ;
} deriving (Json_ext)


let lazy_config = lazy (
  Json_utils_conf.of_file "public/config.json"
)

let get () =
  Lazy.force lazy_config
