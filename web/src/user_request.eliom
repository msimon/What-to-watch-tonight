{shared{
  type user = {
    uid : Graph.User.key ;
    name : string ;
    facebook : Graph.User.facebook option ;
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
  type db_t = Graph.User.t
  type uid = Graph.User.key
  type client_t = user

  let to_client u =
    Lwt.return ({
        uid = u.Graph.User.uid ;
        name = u.Graph.User.name ;
        facebook = u.Graph.User.facebook ;
      })

  let find = Db.User.find

  let find_all () = Db.User.query ~full:true Bson.empty

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

      lwt u = Db.User.find_and_update u.Graph.User.uid (
          fun u ->
            {
              u with
                Graph.User.facebook = Some {
                Graph.User.facebook_uid = fb_id ;
                facebook_access_token = access_token ;
                facebook_access_token_expire_on = Int64.of_int expired_in ;
              }
            }
        ) in

      to_client u

    | None ->
      (* creating the user if it doesn't exist *)
      lwt fb_user = Balsa_facebook.get_user ~access_token fb_id in
      let u = {
        Graph.User.uid = Graph.Uid.fresh_uid Graph.Uid.User ;
        name = fb_user.Balsa_facebook.FBUser.name ;
        ratings = [] ;
        facebook = Some ({
            Graph.User.facebook_uid = fb_id ;
            facebook_access_token = access_token ;
            facebook_access_token_expire_on = Int64.of_int expired_in ;
          }) ;
        vector = [];
        top_movies = [];
      } in

      lwt _ = Db.User.insert u in

      to_client u


let sign_out () = ()


(* TODO *)
let create_email () = ()
let sign_in () = ()
