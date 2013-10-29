type database = {
  ip: string ;
  name: string ;
  collection: string ;
  port: int;
} deriving (Json_ext)

type learning = {
  mutable alpha : float ;
  lambda : float ;
} deriving (Json_ext)

type local_configuration = {
  api_url : string ;
  mock_api : string ;
  api_key : string ;
  max_connections : int ;
  request_per_second : int ;
  api_db: database ;
  w2wt_db: database ;
  movie_loop_time: float;
  sleep_time: float ;
  learning: learning;
  minimal_vote_count: int;
} deriving (Json_ext)
