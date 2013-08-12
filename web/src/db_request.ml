module type M =
sig
  type db_t
  type client_t
  type uid

  val to_client: db_t -> client_t Lwt.t
  val find: uid -> db_t Lwt.t

end

module Make (M : M) =
struct

  let to_client = M.to_client

  let list_to_client db_ts =
    Lwt_list.map_s to_client db_ts

  let of_uid uid =
    let open Lwt in
    (M.find uid) >>= (
      fun db_t ->
        to_client db_t
    )
    (* lwt db_t = M.find uid in *)
    (* to_client db_t *)

  let list_of_uid uids =
    Lwt_list.map_s of_uid uids

end
