type image_conf = {
  base_url : string;
  secure_base_url : string ;
  poster_sizes : string list ;
  backdrop_sizes : string list ;
  profile_sizes : string list ;
  logo_sizes : string list ;
} deriving (Json_ext)

type movidb_configuration = {
  images : image_conf ;
  change_keys : string list ;
} deriving (Json_ext)

type error = {
  status_code : string ;
  status_message: string ;
} deriving (Json_ext)

module Genre_api = struct
  type genre = {
    id: int ;
    name: string ;
  } deriving (Json_ext, Bson_ext)

  type genre_list = {
    genres : genre list;
  } deriving (Json_ext, Bson_ext)
end

module Prod_api = struct
  type production_companies = {
    id: int ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Prod_countries_api = struct
  type production_countries = {
    iso_3166_1: string ;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Lang_api = struct
  type spoken_languages = {
    iso_639_1: string;
    name: string ;
  } deriving (Json_ext, Bson_ext)
end

module Movie_api = struct
  type movie = {
    id: int ;
    adult: bool ;
    backdrop_path: string option ;
    budget: int ;
    genres: Genre_api.genre list ;
    homepage: string option ;
    imdb_id: string option ;
    original_title: string ;
    overview: string option ;
    popularity: float ;
    poster_path: string option ;
    production_companies: Prod_api.production_companies list ;
    production_countries: Prod_countries_api.production_countries list ;
    release_date: string ;
    revenue: int;
    runtime: int option;
    spoken_languages: Lang_api.spoken_languages list ;
    status: string;
    tagline: string option;
    title: string;
    vote_average: float;
    vote_count: int;
  } deriving (Json_ext, Bson_ext)
end


let fetch_moviedb_configuration config =
  lwt s = Http.build_url config ~uri:"/3/configuration" in
  Lwt.return (Json_ext_movidb_configuration.from_json (Json_ext.from_string s))

let fetch_last_movie config =
  lwt s = Http.build_url config ~uri:"/3/movie/latest" in
  Lwt.return (Movie_api.Json_ext_movie.from_json (Json_ext.from_string s))

let fetch_movie_str config uid =
  Http.build_url config ~uri:(Printf.sprintf "/3/movie/%d" uid)

let fetch_movie config uid =
  lwt s = fetch_movie_str config uid in
  let m = Movie_api.Json_ext_movie.from_json (Json_ext.from_string s) in
  Lwt.return m

let fetch_genres config =
  lwt s = Http.build_url config ~uri:"/3/genre/list" in
  let g = Genre_api.Json_ext_genre_list.from_json (Json_ext.from_string s) in
  Lwt.return g.Genre_api.genres

let movie_pool = ref []
let add_movie_to_pool m = movie_pool := m::!movie_pool
let last_call_time = ref None

module Mongo = Mongo_lwt

let insert_movie_async mongodb loop_time threads =
  let rec insert_db_in n =
    lwt _ =
      match !last_call_time with
        | None ->
          last_call_time := Some (Unix.time ());
          Lwt.return_unit
        | Some t ->
          let t_ = Unix.time () in
          lwt _ = Lwt_unix.sleep (loop_time -. (t_ -. t)) in
          last_call_time := Some (Unix.time ());
          Lwt.return_unit
    in

    Printf.printf "inserting %d movies\n%!" (List.length !movie_pool);

    List.iter (
      fun s ->
        try
          let m = Movie_api.Json_ext_movie.from_json (Json_ext.from_string s) in
          Lwt.async (fun _ -> Mongo.insert mongodb [ (Movie_api.Bson_utils_movie.to_bson m) ]);
        with exn ->
          Printf.printf "err insert movie: %s || on %s\n%!" (Printexc.to_string exn) s
    ) !movie_pool;

    movie_pool := [] ;

    begin
      match Lwt.state threads with
        | Lwt.Return _ -> Lwt.return_unit
        | _ -> insert_db_in n
    end
  in

  try_lwt
    insert_db_in 0
  with exn ->
    Printf.printf "Error %s\n%!" (Printexc.to_string exn);
    Lwt.return_unit
