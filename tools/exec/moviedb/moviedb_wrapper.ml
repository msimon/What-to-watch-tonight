let read_params () =
  if Array.length (Sys.argv) = 1 then begin
    Printf.printf "%s argument required" Sys.argv.(0);
    Printf.printf "Usage:\n-rd : drop and reload all movies. Takes approx 2 days\n-c or -complete: load new movies into db\n-rf or -retry: try to reaload all missing id\n-g or -genres: relaod only the genres list%!";
    exit 0
  end else if Array.length (Sys.argv) > 2 then begin
    Printf.printf "%s argument required" Sys.argv.(0);
    Printf.printf "Only one argument at a time!";
    exit 0
  end else begin
    match Sys.argv.(1) with
      | "-rd" -> `Reload
      | "-c" | "-complete" -> `Complete
      | "-retry" | "-r" -> `Retry
      | "-genres" | "-g" -> `Genres_only
      | s ->
        Printf.printf "Unknow parameter %s\n%!" s;
        exit 0
  end

let _ =
  let config = Config.get () in
  let action = read_params () in
  Lwt_main.run (Moviedb.Fetch.run config action)
