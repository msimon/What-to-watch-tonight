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



(** Predict a rating for a user and a movie **)
let predicted_rating user movie =
  (* to calculate the value we use cost with a rating of 0. So we got: (Theta)T * X - 0 *)
  let r = cost user.Graph.User.vector movie.Graph.Movie.vector 0 in
  if r < 0. then 0.
  else r

module Max_heap = Balsa_heap.Binary (struct
    type t = (float * Graph.Movie.t)
    let compare (pr1,m1) (pr2,m2) =
      if (abs_float(pr1 -. pr2) < epsilon_float) then
        compare m2.Graph.Movie.vote_count m1.Graph.Movie.vote_count
      else
        compare pr2 pr1
  end)

let top_movies_by_user rating_db user movie_htbl =
  let module Rating_db = (val rating_db : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in

  (** we create a hastble (Genre.uid option, Heap) to compute top movie by genre**)
  let heap_htbl = Hashtbl.create 40 in

  let get_heap g_uid =
    try
      Hashtbl.find heap_htbl g_uid
    with Not_found ->
      let heap = Max_heap.empty () in
      Hashtbl.add heap_htbl g_uid heap;
      heap
  in

  (** we are going thru all the movies and insert them into the heap
      1 global heap, one heap by genre.
      In case of similar prediction, movie with more overal rating are put on top
   **)

  (** since hashtbl.iter is not lwt friendly,
      we create a sleeping thread that will only be wakeup when all
      necessary execution are done
   **)
  let get_rating u_uid m_uid =
    let query = Bson.add_element "user_uid" (Graph.User.bson_uid u_uid) Bson.empty in
    let query = Bson.add_element "movie_uid" (Graph.Movie.bson_uid m_uid) query in

    Rating_db.query_one_no_cache query
  in

  let (heap_inserted,wakener) = Lwt.task () in
  let hash_size = ref (Hashtbl.length movie_htbl) in

  Hashtbl.iter (
    fun key movie ->
      let gs = movie.Graph.Movie.genres in
      let pr = predicted_rating user movie in

      Lwt.async (
        fun _ ->
          (* check if the user already rated this movie *)
          lwt _ =
            match_lwt get_rating user.Graph.User.uid movie.Graph.Movie.uid with
              | Some r -> Lwt.return ()
              | None ->
                Max_heap.insert (get_heap None) (pr, movie);
                List.iter (
                  fun g_uid ->
                    Max_heap.insert (get_heap (Some g_uid)) (pr,movie);
                ) gs;
                Lwt.return ()
          in

          decr hash_size;

          if !hash_size = 0 then
            Lwt.wakeup wakener ();

          Lwt.return ()
      );
  ) movie_htbl;

  (* this part of the code will wait for the wakener to be wakened up *)
  lwt _ = heap_inserted in

  let top_movies = Hashtbl.fold (
      fun key heap acc ->
        let genre_info = Balsa_option.map (
            fun g_uid ->
              let weight =
                Max_heap.ordered_fold ~max:20 (
                  fun n (pr,_) ->
                    pr +. n
                ) 0. heap
              in

              {
                Graph.User.genre_uid = g_uid;
                weight ;
              }
          ) key
        in

        let movie_list =
          Max_heap.ordered_fold ~max:20 (
            fun acc (_,m) ->
              m.Graph.Movie.uid::acc
          ) [] heap
        in

        {
          Graph.User.genre_info = genre_info;
          movie_list = List.rev movie_list ;
        }::acc
    ) heap_htbl []
  in

  let l = List.sort (
      fun v1 v2 ->
        (* we want the global top movie as the first element of the list
           This function assure that it always seen as bigger
        *)
        match v1.Graph.User.genre_info, v2.Graph.User.genre_info with
          | None, None -> 0
          | None, _ -> -1
          | _ , None -> 1
          | Some g1, Some g2 ->
            compare g2.Graph.User.weight g1.Graph.User.weight
    ) top_movies
  in

  Lwt.return l


(** Calculate the vector for all user and all movies **)
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

  let gradient_descent () =
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
      (* E [ Cost * Theta(u) ] *)
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

    let movie alpha =
      let vect_htbl = Hashtbl.create (Hashtbl.length movie_htbl) in
      Hashtbl.iter (
        fun m_uid movie ->
          let v = List.mapi (
              fun k m_vect ->
                let value = m_vect.Param.value
                            -. (alpha *. ((movie_cost movie k) +. (config.learning.lambda *. m_vect.Param.value)))
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
      let ratings =
        try Hashtbl.find u_rating_htbl user.User.uid
        with _ -> []
      in

      let v = List.fold_left (
          fun u_cost r ->
            let m = Hashtbl.find movie_htbl r.Rating.movie_uid in
            let m_v_k = (List.nth m.Movie.vector k).Param.value in

            u_cost +. ((cost (`Uid (user.User.uid, m.Movie.uid)) r.Rating.rating) *. m_v_k)
        ) 0. ratings
      in
      v
    in

    let user alpha =
      let vect_htbl = Hashtbl.create (Hashtbl.length user_htbl) in
      Hashtbl.iter (
        fun u_uid user ->
          let v = List.mapi (
              fun k u_vect ->
                let cost = (user_cost user k) in
                let reg = (config.learning.lambda *. u_vect.Param.value) in
                let value = u_vect.Param.value -. (alpha *. (cost +. reg)) in
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
        let new_movie_vect = movie alpha in
        let new_user_vect = user alpha in

        (* if cost function is lower, we replace the vector and make the step 5% higher
           if it's higher we lower the step by 50%
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
              Balsa_log.info "i: %d, alpha raised to %f" n a ;
              a
            end else alpha
          in

          iter alpha c (n - 1)
        end else begin
          let alpha = alpha /. 2. in
          Balsa_log.warning "alpha lowered to %f" alpha ;
          if alpha > 0.000005 then
            iter alpha prev_c n
          else
            Balsa_log.error "Alpha went to low"
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

    Balsa_log.info "Updating movies' vector";

    (* update user and movie vector in db *)
    let movies_update = Hashtbl.fold (
        fun key v acc ->
          let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) v.Graph.Movie.vector in
          let modifier = Bson.add_element "vector" vector Bson.empty in

          (Movie_db.update ~modifier v)::acc
      ) movie_htbl []
    in

    let m_nb = ref 0 in
    let m_len = List.length movies_update in

    lwt _ =
      Lwt_list.iter_p (
        fun m ->
          lwt _ = m in

          incr (m_nb);
          if (!m_nb mod 100) = 0 then
            Balsa_log.info "process %d on %d movies' vector" !m_nb m_len;

          Lwt.return_unit
      ) movies_update
    in

    Balsa_log.info "Updating users' vector";
    let users_values = Hashtbl.fold (
        fun key v acc -> v::acc
      ) user_htbl []
    in

    let u_nb = ref 0 in
    let len = List.length users_values in

    Lwt_list.iter_p (
      fun u ->
        let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) u.Graph.User.vector in
        let modifier = Bson.add_element "vector" vector Bson.empty in

        lwt top_movies_u = top_movies_by_user rating_db u movie_htbl in
        let top_movies =
          (let module M = Bson_ext.Bson_ext_list (Graph.User.Bson_ext_top_movie) in M.to_bson) top_movies_u
        in
        let modifier = Bson.add_element "top_movies" top_movies modifier in

        lwt _ = User_db.update ~modifier u in
        incr(u_nb);

        if (!u_nb mod 10) = 0 then
          Balsa_log.info "process %d on %d users vector" !u_nb len;

        Lwt.return ()
    ) users_values
  in

  lwt _ = do_ () in
  Lwt.return_unit

(** Calculate the vector for only one user specified by user_uid **)
let batch_user config genre_db movie_db user_db rating_db user_uid =
  let module Rating_db = (val rating_db : Graph_server.Db.Sig with type t = Graph_server.Rating.t and type key = Graph_server.Rating.key) in
  let module Movie_db = (val movie_db : Graph_server.Db.Sig with type t = Graph_server.Movie.t and type key = Graph_server.Movie.key) in
  let module User_db = (val user_db : Graph_server.Db.Sig with type t = Graph_server.User.t and type key = Graph_server.User.key) in

  let genre_htbl = Hashtbl.create 100 in
  let movie_htbl = Hashtbl.create 40000 in
  let rating_htbl = Hashtbl.create 100 in

  let cost_function user =
    let j =
      Hashtbl.fold (
        fun _ rating j ->
          let movie = Hashtbl.find movie_htbl rating.Graph.Rating.movie_uid in

          j +. ((cost user.Graph.User.vector movie.Graph.Movie.vector rating.Graph.Rating.rating) ** 2.)
      ) rating_htbl 0.
    in

    let user_reg =
      List.fold_left (
        fun j p ->
          j +. (p.Graph.Param.value ** 2.)
      ) 0. user.Graph.User.vector
    in

    let j = j /. 2. +. (config.learning.lambda /. 2.) *. user_reg in
    (* Balsa_log.debug "Cost : %f" j; *)
    j
  in

  let gradient_descent user =
    let user_cost user k =
      (* E(r) [ Cost * Theta(u) ] *)
        Hashtbl.fold (
          fun _ rating u_cost ->
            let movie = Hashtbl.find movie_htbl rating.Graph.Rating.movie_uid in
            let m_v_k = (List.nth movie.Graph.Movie.vector k).Graph.Param.value in

            u_cost +. ((cost user.Graph.User.vector movie.Graph.Movie.vector rating.Graph.Rating.rating) *. m_v_k)
        ) rating_htbl 0.
    in

    let user_grad alpha user =
      let k = ref 0 in
      let vector =
        List.map (
          fun u_vect ->
            let cost = user_cost user !k in
            let reg = (config.learning.lambda *. u_vect.Graph.Param.value) in
            let value = u_vect.Graph.Param.value -. (alpha *. (cost +. reg)) in
            incr k;
            {
              u_vect with
                Graph.Param.value;
            }
        ) user.Graph.User.vector
      in

      {
        user with
          Graph.User.vector ;
      }
    in

    let rec iter alpha prev_c n (user : Graph.User.t) : Graph.User.t =
      if n = 0 then user
      else begin
        (* Balsa_log.debug "loop nb: %d" n; *)
        let new_user = user_grad alpha user in

        (* if cost function is lower, we replace the vector and make the step 5% higher
           if it's higher we divide the step by 50%
        *)
        let c = cost_function new_user in

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
          else user
        end
      end
    in

    let c = cost_function user in

    iter config.learning.alpha c 100 user
  in

  let load_ratings user =
    let query = Bson.add_element "user_uid" (Bson.create_int64 (Int64.of_int (Graph.Uid.get_value user.Graph.User.uid))) Bson.empty in
    lwt ratings = Rating_db.query_no_cache ~full:true query in

    List.iter (
      fun r ->
        Hashtbl.add rating_htbl r.Graph.Rating.uid r
    ) ratings;

    Lwt.return ()
  in

  let load_user () =
    lwt user = User_db.find user_uid in
    Lwt.return {
      user with
        Graph.User.vector = init_vector genre_htbl user.Graph.User.vector
    }
  in

  lwt _ = load_genres_params genre_db genre_htbl in
  lwt _ = load_movies_params movie_db movie_htbl genre_htbl in
  lwt user = load_user () in
  lwt _ = load_ratings user in

  Balsa_log.info "Starting gradient Descent";
  let user = gradient_descent user in
  Balsa_log.info "Gradient descent Finished";

  Balsa_log.info "Updating user vector and top movie";
  (* update the user *)
  let vector = (let module M = Bson_ext.Bson_ext_list (Graph.Param.Bson_ext_t) in M.to_bson) user.Graph.User.vector in
  let modifier = Bson.add_element "vector" vector Bson.empty in

  lwt top_movies_u = top_movies_by_user rating_db user movie_htbl in
  let top_movies =
    (let module M = Bson_ext.Bson_ext_list (Graph.User.Bson_ext_top_movie) in M.to_bson) top_movies_u
  in
  let modifier = Bson.add_element "top_movies" top_movies modifier in

  lwt _ = User_db.update ~modifier user in

  Balsa_log.info "User %d has been updated" (Graph.Uid.get_value (user.Graph.User.uid));
  Lwt.return  ();
