type change = {
  id: int;
  adult: bool option; (* adult can be null *)
} deriving (Json_ext)

type change_list = {
  results: change list ;
  page : int;
  total_pages: int;
  total_results: int;
} deriving (Json_ext)
