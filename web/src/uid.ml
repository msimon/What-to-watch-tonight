{shared{
  (* deriving need a type even if it is never used *)
  type user = User deriving (Bson_ext)
  type movie = Movie deriving (Bson_ext)
  type genre = Genre deriving (Bson_ext)
  type rating = Rating deriving (Bson_ext)

  type _ typ =
    | User : user typ
    | Movie : movie typ
    | Genre : genre typ
    | Rating : rating typ

  module type Uid =
  sig
    type 'a uid deriving (Bson_ext)

    val fresh_uid : 't typ -> 't uid
    val set_uid : 't typ -> unit
    val get_uid_value : 'a uid -> int -> unit

  end

  module Uid =
  struct
    type 'a uid = int deriving (Bson_ext)

    let uid_htbl = Hashtbl.create 4

    let get_uid_value uid = uid

    let fresh_uid : type t. t typ -> t uid =
      fun t ->
        let find_n_update ty =
          try
            let n = Hashtbl.find uid_htbl ty in
            Hashtbl.replace uid_htbl ty (n + 1);
            n + 1
          with Not_found ->
            let _ = Hashtbl.add uid_htbl ty 1 in
            1
        in

        match t with
          | User ->
            find_n_update 0
          | Movie ->
            find_n_update 1
          | Genre ->
            find_n_update 2
          | Rating ->
            find_n_update 3

    let set_uid : type t. t typ -> int -> unit =
      fun t v ->
        let find_n_update ty =
          try
            let n = Hashtbl.find uid_htbl ty in
            if (n <> 1) then begin
              Balsa_log.error "Uid.uid has already been set" ;
              failwith "Uid.uid has already been set"
            end else
              Hashtbl.replace uid_htbl ty v
          with Not_found ->
            Hashtbl.add uid_htbl ty v
        in

      match t with
        | User ->
          find_n_update 0
        | Movie ->
          find_n_update 1
        | Genre ->
          find_n_update 2
        | Rating ->
          find_n_update 3


  end


  type 'a uid = 'a Uid.uid deriving (Bson_ext)
}}

let get_uid_value = Uid.get_uid_value
let fresh_uid = Uid.fresh_uid
let set_uid = Uid.set_uid
