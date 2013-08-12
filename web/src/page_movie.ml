(* {server{ *)

(*   let uid_of_service = *)
(*     server_function Json.t<Uid.movie Uid.uid> ( *)
(*       fun m_uid -> *)

(*     ) *)

(* }} *)

(* {client{ *)

(*   open Eliom_content *)
(*   open Html5 *)
(*   open D *)

(*   open Balsa_react *)

(*   let dom s = *)
(*     let uid_of_service = function *)
(*       | Movie uid -> uid *)
(*       | _ -> assert false *)
(*     in *)
(*     let m_uid = uid_of_service s in *)

(*     lwt movie = %fetch_movie m_uid in *)

(*     () *)

(*   module Page_movie = Page.Make(struct *)
(*       let service s = *)
(*         match s with *)
(*           | Path.Movie _ -> true *)
(*           | _ -> false *)
(*     end) *)

(* }} *)
