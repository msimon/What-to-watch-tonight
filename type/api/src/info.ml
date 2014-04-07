module Prod_api = struct
  type production_companies = {
    id: int ;
    name: string ;
  } deriving (Yojson, Bson_ext)
end

module Prod_countries_api = struct
  type production_countries = {
    iso_3166_1: string ;
    name: string ;
  } deriving (Yojson, Bson_ext)
end

module Lang_api = struct
  type spoken_languages = {
    iso_639_1: string;
    name: string ;
  } deriving (Yojson, Bson_ext)
end
