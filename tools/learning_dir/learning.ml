module Param =
struct
  (* n size vector, n = # gender in our case *)
  type param = {
    genre_uid : int ;
    value : float ;
  } deriving (Bson_ext)
end

module User =
struct
  type t = {
    uid: int ;
    name: string ;
    (* ratings: int list ; *)
    vector : Param.param list ;
  } deriving (Bson_ext)
end

module Movie =
struct
  type t = {
    uid: int ;
    title: string ;
    (* genres : int list ; *)
    vector : Param.param list ;
  } deriving (Bson_ext)
end

module Rating =
struct
  type t = {
    uid: int ;
    user_uid: int;
    movie_uid: int;
    rating: int ;
  } deriving (Bson_ext)
end

module Genre =
struct
  type t = {
    uid: int ;
    name: string ;
  } deriving (Bson_ext)
end

let rec db_fetch_all ?(acc=[]) mongo ~from_bson r =
  let fetch_one_batch ?(acc=[]) r =
    let ds = MongoReply.get_document_list r in
    List.fold_left (
      fun acc d ->
        (from_bson d)::acc
    ) acc ds
  in

  if MongoReply.get_num_returned r = 0l then Lwt.return acc
  else begin
    let acc = fetch_one_batch ~acc r in
    lwt r = Mongo_lwt.get_more mongo (MongoReply.get_cursor r) in
    db_fetch_all mongo ~acc ~from_bson r
  end

let user_htbl = Hashtbl.create 100
let movie_htbl = Hashtbl.create 100
let m_rating_htbl = Hashtbl.create 100
let u_rating_htbl = Hashtbl.create 100
let rating_htbl = Hashtbl.create 100
let genre_htbl = Hashtbl.create 100

(* if the vector is empty, we set random value between -1 to 1 in it*)
let init_vector =
  let rand () = (Random.float 0.01) -. 0.005 in
  (function
    | [] ->
      Hashtbl.fold (
        fun genre_uid _ acc ->
          {
            Param.genre_uid = genre_uid ;
            Param.value = rand ();
          }::acc
      ) genre_htbl []
    | v -> v)

let load_user_params config =
  let open User in
  lwt mongo = Config.(Mongo_lwt.create config.ip config.port config.name "users") in

  lwt r = Mongo_lwt.find mongo in

  lwt users = db_fetch_all mongo ~from_bson:Bson_utils_t.from_bson r in

  List.iter (
    fun u ->
      (* if u.uid > 1 then begin *)
        let u = {
          u with
            vector = init_vector u.vector
        } in
        Hashtbl.add user_htbl u.uid u
      (* end *)
  ) users;

  Printf.printf "Finished to load %d users\n%!" (Hashtbl.length user_htbl);

  Lwt.return ()


let load_movie_params config =
  let open Movie in
  lwt mongo = Config.(Mongo_lwt.create config.ip config.port config.name "movies") in

  lwt r = Mongo_lwt.find mongo in
  lwt movies = db_fetch_all mongo ~from_bson:Bson_utils_t.from_bson r in
  (* let movies,_ = *)
  (*   List.fold_left ( *)
  (*     fun (acc,n) m -> *)
  (*       if n >= 100 then (acc,n) *)
  (*       else (m::acc, n + 1) *)
  (*   ) ([],0) movies *)
  (* in *)


  List.iter (
    fun m ->
      let m = {
        m with
          vector = init_vector m.vector
      } in
      Hashtbl.add movie_htbl m.uid m
  ) movies;

  Printf.printf "Finished to load %d movies\n%!" (Hashtbl.length movie_htbl);

  Lwt.return ()


let load_rating_params config =
  let open Rating in
  lwt mongo = Config.(Mongo_lwt.create config.ip config.port config.name "ratings") in

  lwt r = Mongo_lwt.find mongo in
  lwt ratings = db_fetch_all mongo ~from_bson:Bson_utils_t.from_bson r in

  List.iter (
    fun r ->
      if (Hashtbl.mem user_htbl r.user_uid) then begin
        (try
           let user_ratings = Hashtbl.find u_rating_htbl r.user_uid in
           Hashtbl.replace u_rating_htbl r.user_uid (r::user_ratings)
         with Not_found ->
           Hashtbl.add u_rating_htbl r.user_uid [ r ]
        );
        (try
           let movie_ratings = Hashtbl.find m_rating_htbl r.movie_uid in
           Hashtbl.replace m_rating_htbl r.movie_uid (r::movie_ratings)
         with Not_found ->
           Hashtbl.add m_rating_htbl r.movie_uid [ r ]
        );
        Hashtbl.add rating_htbl r.uid r
      end else ()
  ) ratings;

  Printf.printf "Finished to load %d ratings\n%!" (Hashtbl.length rating_htbl);

  Lwt.return ()


let load_genre_params config =
  let open Genre in
  lwt mongo = Config.(Mongo_lwt.create config.ip config.port config.name "genres") in

  lwt r = Mongo_lwt.find mongo in
  lwt genres = db_fetch_all mongo ~from_bson:Bson_utils_t.from_bson r in
  (* let genres,_ = *)
  (*   List.fold_left ( *)
  (*     fun (acc,n) g -> *)
  (*       if n >= 5 then (acc,n) *)
  (*       else (g::acc, n + 1) *)
  (*   ) ([],0) genres *)
  (* in *)

  List.iter (
    fun g ->
      Hashtbl.add genre_htbl g.uid g
  ) genres;

  Printf.printf "Finished to load %d genres\n%!" (Hashtbl.length genre_htbl);

  Lwt.return ()



let cost vect rating =
  let open Param in
  (* Theta(j)' * X(i) - y(i,j) *)
  (* let u_v = (Hashtbl.find user_htbl u_uid).User.vector in *)
  (* let m_v = (Hashtbl.find movie_htbl m_uid).Movie.vector in *)

  let u_v,m_v =
    match vect with
      | `Uid (u_uid, m_uid) ->
        let u_v = (Hashtbl.find user_htbl u_uid).User.vector in
        let m_v = (Hashtbl.find movie_htbl m_uid).Movie.vector in
        u_v,m_v
      | `Vect (u_v, m_v) ->
        u_v,m_v
  in

  let v = List.fold_left2 (
      fun cost u m ->
        if (u.genre_uid <> m.genre_uid) then
          failwith "u and m have differente genre_uid..."
        else
          cost +. (u.value *. m.value)
    ) 0. u_v m_v
  in

  v -. (float_of_int rating)

let cost_function cost_fun_vect config =
  let j =
    Hashtbl.fold (
      fun _ r j ->
        let vect =
          match cost_fun_vect with
            | `CFUid -> `Uid (r.Rating.user_uid, r.Rating.movie_uid)
            | `CFVect (us_v,ms_v) ->
              let u_v = Hashtbl.find us_v r.Rating.user_uid in
              let m_v = Hashtbl.find ms_v r.Rating.movie_uid in
              `Vect (u_v,m_v)
        in

        j +. ((cost vect r.Rating.rating) ** 2.)
    ) rating_htbl 0.
  in

  let movie_req =
    Hashtbl.fold (
      fun _ m req ->
        let vect =
          match cost_fun_vect with
            | `CFUid -> m.Movie.vector
            | `CFVect (_,ms_v) ->
              Hashtbl.find ms_v m.Movie.uid
        in

        List.fold_left (
          fun req p ->
            req +. ((p.Param.value) ** 2.)
        ) req vect
    ) movie_htbl 0.
  in

  let user_req =
    Hashtbl.fold (
      fun _ u req ->
        let vect =
          match cost_fun_vect with
            | `CFUid -> u.User.vector
            | `CFVect (us_v,_) ->
              Hashtbl.find us_v u.User.uid
        in
        List.fold_left (
          fun req p ->
            req +. ((p.Param.value) ** 2.)
        ) req vect
    ) user_htbl 0.
  in

  (* Printf.printf "movie_req : %f, user_req : %f\n%!" movie_req user_req ; *)

  let j = j /. 2. +. (config.Config.learning.Config.lambda /. 2.) *. movie_req +. (config.Config.learning.Config.lambda /. 2.) *. user_req in
  Printf.printf "Final j : %f\n\n%!" j;
  j


let gradient_descent config =
  let _print_vect u_uid m_uid =
    Printf.printf "in printf vect..";
    let u_v = (Hashtbl.find user_htbl u_uid).User.vector in
    let m_v = (Hashtbl.find movie_htbl m_uid).Movie.vector in
    Printf.printf " done \n%!";

    List.iter2 (
      fun u_v m_v ->
        Printf.printf "u: %f, m: %f\n%!" u_v.Param.value m_v.Param.value;
    ) u_v m_v
  in

  let movie_cost movie k =
    (* E(r) [ Cost * Theta(u) ] *)
    let ratings =
      try Hashtbl.find m_rating_htbl movie.Movie.uid
      with _ -> []
    in
    List.fold_left (
      fun m_cost r ->
        let u = Hashtbl.find user_htbl r.Rating.user_uid in
        let u_v_k = (List.nth u.User.vector k).Param.value in

        m_cost +. ((cost (`Uid (u.User.uid, movie.Movie.uid)) r.Rating.rating) *. u_v_k)
    ) 0. ratings
  in

  let movie () =
    let vect_htbl = Hashtbl.create (Hashtbl.length movie_htbl) in
    Hashtbl.iter (
      fun m_uid movie ->
        let v = List.mapi (
            fun k m_vect ->
              let value = m_vect.Param.value
                          -. (config.Config.learning.Config.alpha *. ((movie_cost movie k) +. (config.Config.learning.Config.lambda *. m_vect.Param.value)))
              in
              {
                m_vect with
                  Param.value;
              }
          ) movie.Movie.vector
        in
        Hashtbl.add vect_htbl m_uid v
    ) movie_htbl;
    vect_htbl
  in

  let user_cost user k =
    (* E(r) [ Cost * Theta(u) ] *)
    let ratings = Hashtbl.find u_rating_htbl user.User.uid in
    (* Printf.printf "user_cost for %d : # of rating %d\n" user.User.uid (List.length ratings) ; *)

    let v = List.fold_left (
        fun u_cost r ->
          let m = Hashtbl.find movie_htbl r.Rating.movie_uid in
          let m_v_k = (List.nth m.Movie.vector k).Param.value in

          u_cost +. ((cost (`Uid (user.User.uid, m.Movie.uid)) r.Rating.rating) *. m_v_k)
      ) 0. ratings
    in
    v
  in

  let user () =
    let vect_htbl = Hashtbl.create (Hashtbl.length user_htbl) in
    Hashtbl.iter (
      fun u_uid user ->
        let v = List.mapi (
            fun k u_vect ->
              let value = u_vect.Param.value
                          -. (config.Config.learning.Config.alpha *. ((user_cost user k) +. (config.Config.learning.Config.lambda *. u_vect.Param.value)))
              in
              {
                u_vect with
                  Param.value;
              }
          ) user.User.vector
        in
        Hashtbl.add vect_htbl u_uid v
    ) user_htbl;

    vect_htbl
  in

  let rec iter prev_c n =
    if n = 0 then ()
    else begin
      (* Printf.printf "starting gradient descent on movie\n%!"; *)
      let new_movie_vect = movie () in
      (* Printf.printf "End gradient descent on movie\n%!"; *)
      let new_user_vect = user () in

      (* if cost function is lower, we replace the vector and make the step 5% higher
         if it's higher we divide the step by 50%
      *)
      let c = cost_function (`CFVect (new_user_vect,new_movie_vect)) config in

      if c <= prev_c then begin
        Hashtbl.iter (
          fun m_uid new_vect ->
            let m = Hashtbl.find movie_htbl m_uid in
            Hashtbl.replace movie_htbl m_uid {
              m with
                Movie.vector = new_vect;
            }
        ) new_movie_vect;

        Hashtbl.iter (
          fun u_uid new_vect ->
            let u = Hashtbl.find user_htbl u_uid in
            Hashtbl.replace user_htbl u_uid {
              u with
                User.vector = new_vect;
            }
        ) new_user_vect;

        Printf.printf ".%!";

        (* if c = prev_c we may have reach a minima,
           we probably do not want to raise alpha *)
        if c < prev_c then
          Config.(config.learning.alpha <- config.learning.alpha +. config.learning.alpha *. 0.05) ;

        Printf.printf "i: %d, alpha raised: %f\n\n%!" n config.Config.learning.Config.alpha ;

        iter c (n - 1)
      end else begin
        Config.(config.learning.alpha <- config.learning.alpha /. 2.);
        Printf.printf "alpha lowered: %f\n\n%!" config.Config.learning.Config.alpha ;
        if config.Config.learning.Config.alpha > 0.000005 then
          iter prev_c n;
      end
    end
  in

  let c = cost_function `CFUid config in

  iter c 20;

  Hashtbl.iter (
    fun u_uid user ->
      Printf.printf "\ndisplay: %d\n%!" u_uid;
      List.iteri (
        fun i v ->
          Printf.printf "%d: uid: %d =>  %.3f\n%!" i v.Param.genre_uid v.Param.value ;
      ) user.User.vector
  ) user_htbl


let main config =
  let database_config = config.Config.w2wt_db in
  lwt _ = load_genre_params database_config in
  lwt _ = load_movie_params database_config in

  lwt _ = Lwt.join [
      load_user_params database_config ;
      load_rating_params database_config ;
    ]
  in

  (* pretty much a random number here*)
  (* Config.(config.alpha <-  50. /. (float_of_int (Hashtbl.length movie_htbl))) ; *)

  Printf.printf "Starting gradient descent\n%!";
  gradient_descent config;
  Printf.printf "End gradient descent\n%!";

  (* test with user 2 and movie 134460, result should be close to 5 *)

  (* let u = Hashtbl.find user_htbl 2 in *)
  let m = Hashtbl.find movie_htbl 134460 in
  (* checking the movie is batman the dark knight *)
  Printf.printf "title: %s \n%!" m.Movie.title;

  let c = cost (`Uid (2,134460)) 0 in
  Printf.printf "prediction for user 2 and movie 134460 is %f\n%!" c ;
  let c = cost (`Uid (2,134219)) 0 in
  Printf.printf "prediction for user 2 and movie 134219 is %f\n%!" c ;

  let c = cost (`Uid (1,134460)) 0 in
  Printf.printf "prediction for user 1 and movie 134460 is %f\n%!" c ;


  Lwt.return_unit


let _ =
  let config = Config.init () in
  Lwt_main.run (main config)
