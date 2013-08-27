module type M =
sig
  type db_t
  type client_t
  type uid

  val to_client: db_t -> client_t Lwt.t
  val find: uid -> db_t Lwt.t

  val find_all : unit -> db_t list Lwt.t

end

module Make (M : M) =
struct

  let to_client = M.to_client

  let list_to_client db_ts =
    Lwt_list.map_s to_client db_ts

  let of_uid uid =
    lwt db_t = M.find uid in
    to_client db_t

  let list_of_uid uids =
    Lwt_list.map_s of_uid uids

  let all_to_client () =
    lwt db_ts = M.find_all () in
    list_to_client db_ts

end
