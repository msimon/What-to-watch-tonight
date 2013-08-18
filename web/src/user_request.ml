{shared{
  type user = {
    uid : User_type.key ;
    name : string ;
    facebook : User_type.facebook option ;
  }

}}

{client{
  module M =
  struct
    type client_t = user
  end
}}

module M =
struct
  type db_t = User_type.t
  type uid = User_type.key
  type client_t = user

  let to_client u =
    Lwt.return ({
        uid = u.User_type.uid ;
        name = u.User_type.name ;
        facebook = u.User_type.facebook ;
      })

  let find = Db.User.find

end

module DB_r = Db_request.Make (M)
include DB_r


let facebook_sign_in (fb_id, access_token) =
  lwt access_token, expired_in = Balsa_facebook.extended_access_token access_token in

  (* search for facebook_id *)
  let q = Bson.add_element "facebook.facebook_uid" (Bson.create_string fb_id) Bson.empty in
  lwt u = Db.User.query_one q in

  match u with
    | Some u ->
      (* update the access token if the user already exist*)
      let u = {
        u with
          User_type.facebook = Some {
          User_type.facebook_uid = fb_id ;
          facebook_access_token = access_token ;
          facebook_access_token_expire_on = Int64.of_int expired_in ;
        }
      } in

      lwt _ = Db.User.update u in

      to_client u

    | None ->
      (* creating the user if it doesn't exist *)
      lwt fb_user = Balsa_facebook.get_user ~access_token fb_id in
      let u = {
        User_type.uid = Uid.fresh_uid Uid.User ;
        name = fb_user.Balsa_facebook.FBUser.name ;
        ratings = [] ;
        facebook = Some ({
            User_type.facebook_uid = fb_id ;
            facebook_access_token = access_token ;
            facebook_access_token_expire_on = Int64.of_int expired_in ;
          }) ;
        vector = [];
      } in

      lwt _ = Db.User.insert u in

      to_client u


let sign_out () = ()


(* TODO *)
let create_email () = ()
let sign_in () = ()
