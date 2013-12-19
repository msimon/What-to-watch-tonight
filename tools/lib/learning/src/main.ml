module Graph = Graph_server

open Config_t

(* if the vector is empty, we set random value between -1 to 1 in it*)
let init_vector =
  Random.self_init ();
  let rand () = (Random.float 0.01) -. 0.005 in
  (fun genre_htbl vect ->
     match vect with
       | [] ->
         Hashtbl.fold (
           fun genre_uid _ acc ->
             {
               Graph.Param.genre_uid = genre_uid ;
               Graph.Param.value = rand ();
             }::acc
         ) genre_htbl []
       | v -> v)


let load_users_params user_db user_htbl genre_htbl =
  let open Graph.User in
  let module User_db = (val user_db : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in

  lwt users = User_db.query_no_cache ~full:true Bson.empty in

  List.iter (
    fun u ->
      if u.uid = (Graph.Uid.unsafe 1) && u.name = "themoviedb" then ()
      else begin
        let u = {
          u with
            vector = init_vector genre_htbl u.vector
        } in
        Hashtbl.add user_htbl u.uid u
      end
  ) users;

  Balsa_log.info "Finished to load %d users" (Hashtbl.length user_htbl);

  Lwt.return ()


let load_movies_params movie_db movie_htbl genre_htbl =
  let open Graph.Movie in
  let module Movie_db = (val movie_db : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in

  lwt movies = Movie_db.query_no_cache ~full:true Bson.empty in

  List.iter (
    fun m ->
      let m = {
        m with
          vector = init_vector genre_htbl m.vector
      } in
      Hashtbl.add movie_htbl m.uid m
  ) movies;

  Balsa_log.info "Finished to load %d movies" (Hashtbl.length movie_htbl);

  Lwt.return ()

let load_ratings_params rating_db rating_htbl u_rating_htbl m_rating_htbl user_htbl movie_htbl =
  let open Graph.Rating in
  let module Rating_db = (val rating_db : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in

  lwt ratings = Rating_db.query_no_cache ~full:true Bson.empty in

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

  Balsa_log.info "Finished to load %d ratings" (Hashtbl.length rating_htbl);

  Lwt.return ()


let load_genres_params genre_db genre_htbl =
  let module Genre_db = (val genre_db : Graph_server.Db.Sig with type t = Graph_server.Genre.t and type key = Graph_server.Genre.key) in
  lwt genres = Genre_db.query_no_cache ~full:true Bson.empty in

  List.iter (
    fun g ->
      Hashtbl.add genre_htbl g.Graph.Genre.uid g
  ) genres;

  Balsa_log.info "Finished to load %d genres" (Hashtbl.length genre_htbl);

  Lwt.return ()


let cost u_v m_v rating =
  let open Graph in
  (* Theta(j)' * X(i) - y(i,j) *)
  let v = List.fold_left2 (
      fun cost u m ->
        if (u.Param.genre_uid <> m.Param.genre_uid) then
          failwith "u and m have differente genre_uid..."
        else
          cost +. (u.Param.value *. m.Param.value)
    ) 0. u_v m_v
  in

  v -. (float_of_int rating)


let batch config user_db movie_db genre_db rating_db =
  let module Movie_db = (val movie_db : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let module User_db = (val user_db : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in

  let user_htbl = Hashtbl.create 100 in
  let movie_htbl = Hashtbl.create 40000 in
  let m_rating_htbl = Hashtbl.create 40000 in
  let u_rating_htbl = Hashtbl.create 40000 in
  let rating_htbl = Hashtbl.create 40000 in
  let genre_htbl = Hashtbl.create 100 in

  let cost vect rating =
    let open Graph in
    (* Theta(j)' * X(i) - y(i,j) *)

    let u_v,m_v =
      match vect with
        | `Uid (u_uid, m_uid) ->
          let u_v = (Hashtbl.find user_htbl u_uid).User.vector in
          let m_v = (Hashtbl.find movie_htbl m_uid).Movie.vector in
          u_v,m_v
        | `Vect (u_v, m_v) ->
          u_v,m_v
    in

    cost u_v m_v rating
  in

  let cost_function cost_fun_vect =
    let open Graph in
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

    let movie_reg =
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

    let user_reg =
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
              req +. (p.Param.value ** 2.)
          ) req vect
      ) user_htbl 0.
    in

    let j = j /. 2. +. (config.learning.lambda /. 2.) *. movie_reg +. (config.learning.lambda /. 2.) *. user_reg in
    Balsa_log.debug "Cost : %f" j;
    j
  in

  let gradient_descent ()=
    let open Graph in
    let _print_vect u_uid m_uid =
      Balsa_log.debug "in printf vect..";
      let u_v = (Hashtbl.find user_htbl u_uid).User.vector in
      let m_v = (Hashtbl.find movie_htbl m_uid).Movie.vector in
      Balsa_log.debug " done";

      List.iter2 (
        fun u_v m_v ->
          Balsa_log.debug "u: %f, m: %f" u_v.Param.value m_v.Param.value;
      ) u_v m_v
    in

    let movie_cost movie k =
      (* E(r) [ Cost * Theta(u) ] *)
      let ratings = Hashtbl.find m_rating_htbl movie.Movie.uid in
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
                            -. (config.learning.alpha *. ((movie_cost movie k) +. (config.learning.lambda *. m_vect.Param.value)))
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
                let cost = (user_cost user k) in
                let reg = (config.learning.lambda *. u_vect.Param.value) in
                let value = u_vect.Param.value -. (config.learning.alpha *. (cost +. reg)) in
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

    let rec iter alpha prev_c n =
      if n = 0 then ()
      else begin
        let new_movie_vect = movie () in
        let new_user_vect = user () in

        (* if cost function is lower, we replace the vector and make the step 5% higher
           if it's higher we divide the step by 50%
        *)
        let c = cost_function (`CFVect (new_user_vect,new_movie_vect)) in

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

          (* if c = prev_c we may have reach a minima,
             we probably do not want to raise alpha *)
          let alpha =
            if c < prev_c then begin
              let a = alpha *. 1.05 in
              Balsa_log.info "i: %d, alpha raised: %f" n a ;
              a
            end else alpha
          in

          iter alpha c (n - 1)
        end else begin
          let alpha = alpha /. 2. in
          Balsa_log.warning "alpha lowered: %f" alpha ;
          if alpha > 0.000005 then
            iter alpha prev_c n;
        end
      end
    in

    let c = cost_function `CFUid in

    iter config.learning.alpha c 100

    (* Hashtbl.iter ( *)
    (*   fun u_uid user -> *)
    (*     Balsa_log.debug "\ndisplay: %d" (Graph.Uid.get_value u_uid); *)
    (*     List.iteri ( *)
    (*       fun i v -> *)
    (*         Balsa_log.debug "%d: uid: %d =>  %.3f" i (Graph.Uid.get_value v.Param.genre_uid) v.Param.value ; *)
    (*     ) user.User.vector *)
    (* ) user_htbl *)
  in

  let do_ () =
    (* genre must be load before since we can use it to setup inital vector *)
    lwt _ = load_genres_params genre_db genre_htbl in
    lwt _ = Lwt.join [
        load_movies_params movie_db movie_htbl genre_htbl ;
        load_users_params user_db user_htbl genre_htbl ;
      ]
    in

    lwt _ = load_ratings_params rating_db rating_htbl u_rating_htbl m_rating_htbl user_htbl movie_htbl in

    gradient_descent ();

    (* update user and movie vector in db *)
    let movies_update = Hashtbl.fold (
        fun key v acc ->
          let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) v.Graph.Movie.vector in
          let modifier = Bson.add_element "vector" vector Bson.empty in

          (Movie_db.update ~modifier v)::acc
      ) movie_htbl []
    in
    lwt _ = Lwt_list.iter_p (fun m -> lwt _ = m in Lwt.return_unit) movies_update in

    let users_update = Hashtbl.fold (
        fun key v acc ->
          let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) v.Graph.User.vector in
          let modifier = Bson.add_element "vector" vector Bson.empty in

          (User_db.update ~modifier v)::acc
      ) user_htbl []
    in

    Lwt_list.iter_p (fun m -> lwt _ = m in Lwt.return_unit) users_update
  in

  lwt _ = do_ () in
  Lwt.return_unit

let user_movie_cost user movie =
  (* to calculate the value we use cost with a rating of 0. So we got: (Theta)T * X - 0 *)
  cost user.Graph.User.vector movie.Graph.Movie.vector 0

let batch_user config genre_db movie_db user_db rating_db user_uid =
  let module Rating_db = (val rating_db : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in
  let module Movie_db = (val movie_db : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let module User_db = (val user_db : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in

  let genre_htbl = Hashtbl.create 100 in
  let movie_htbl = Hashtbl.create 40000 in

  let cost_function user =
    lwt j =
      Lwt_list.fold_left_s (
        fun j rating_uid ->
          lwt rating = Rating_db.find rating_uid in
          lwt movie = Movie_db.find rating.Graph.Rating.movie_uid in

          Lwt.return (j +. ((cost user.Graph.User.vector movie.Graph.Movie.vector rating.Graph.Rating.rating) ** 2.))
      ) 0. user.Graph.User.ratings
    in

    let user_reg =
      List.fold_left (
        fun j p ->
          j +. (p.Graph.Param.value ** 2.)
      ) 0. user.Graph.User.vector
    in

    let j = j /. 2. +. (config.learning.lambda /. 2.) *. user_reg in
    Balsa_log.debug "Cost : %f" j;
    Lwt.return j
  in

  let gradient_descent user =
    let user_cost user k =
      (* E(r) [ Cost * Theta(u) ] *)
      lwt v = Lwt_list.fold_left_s (
          fun u_cost rating_uid ->
            lwt rating = Rating_db.find rating_uid in
            lwt movie = Movie_db.find rating.Graph.Rating.movie_uid in
            let m_v_k = (List.nth movie.Graph.Movie.vector k).Graph.Param.value in

            Lwt.return (u_cost +. ((cost user.Graph.User.vector movie.Graph.Movie.vector rating.Graph.Rating.rating) *. m_v_k))
        ) 0. user.Graph.User.ratings
      in

      Lwt.return v
    in

    let user_grad user =
      let k = ref 0 in
      lwt vector =
        Lwt_list.map_s (
          fun u_vect ->
            lwt cost = (user_cost user !k) in
            let reg = (config.learning.lambda *. u_vect.Graph.Param.value) in
            let value = u_vect.Graph.Param.value -. (config.learning.alpha *. (cost +. reg)) in
            incr k;
            Lwt.return ({
              u_vect with
                Graph.Param.value;
            })
        ) user.Graph.User.vector
      in

      Lwt.return {
        user with
          Graph.User.vector ;
      }
    in

    let rec iter alpha prev_c n (user : Graph.User.t) : Graph.User.t Lwt.t =
      if n = 0 then Lwt.return user
      else begin
        Balsa_log.debug "loop nb: %d" n;
        lwt new_user = user_grad user in

        (* if cost function is lower, we replace the vector and make the step 5% higher
           if it's higher we divide the step by 50%
        *)
        lwt c = cost_function new_user in

        if c <= prev_c then begin
          (* if c = prev_c we may have reach a minima,
             we probably do not want to raise alpha *)
          let alpha =
            if c < prev_c then begin
              let a = alpha *. 1.05 in
              Balsa_log.info "i: %d, alpha raised: %f" n a ;
              a
            end else alpha
          in

          iter alpha c (n - 1) new_user
        end else begin
          let alpha = alpha /. 2. in
          Balsa_log.warning "alpha lowered: %f" alpha ;
          if alpha > 0.000005 then
            iter alpha prev_c n user
          else Lwt.return user
        end
      end
    in

    lwt c = cost_function user in

    iter config.learning.alpha c 100 user
  in

  lwt _ = load_genres_params genre_db genre_htbl in
  lwt _ = load_movies_params movie_db movie_htbl genre_htbl in
  lwt user = User_db.find user_uid in

  lwt user = gradient_descent user in

  (* update the user *)
  let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) user.Graph.User.vector in
  let modifier = Bson.add_element "vector" vector Bson.empty in
  lwt _ = User_db.update ~modifier user in

  Lwt.return  ();
