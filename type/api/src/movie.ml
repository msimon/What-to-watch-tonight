type t = {
  id: int ;
  adult: bool ;
  backdrop_path: string option ;
  budget: int ;
  genres: Genre.t list ;
  homepage: string option ;
  imdb_id: string option ;
  original_title: string ;
  overview: string option ;
  popularity: float ;
  poster_path: string option ;
  production_companies: Info.Prod_api.production_companies list ;
  production_countries: Info.Prod_countries_api.production_countries list ;
  release_date: string ;
  revenue: int;
  runtime: int option;
  spoken_languages: Info.Lang_api.spoken_languages list ;
  status: string;
  tagline: string option;
  title: string;
  vote_average: float;
  vote_count: int;
} deriving (Yojson, Bson_ext)
