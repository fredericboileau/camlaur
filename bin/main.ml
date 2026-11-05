open Core

let search =
  Command.basic ~summary:"Search for aur package"
    [%map_open.Command
      let term = anon ("term" %: string) in
      fun () -> Lwt_main.run (Aur.Web.search term)]

let fetch =
  Command.basic ~summary:"Fetch aur package"
    [%map_open.Command
      let pkgname = anon ("pkgname" %: string) in
      fun () ->
        match Aur.Web.fetch pkgname with
        | Ok () -> ()
        | Error (Aur.Web.Already_cloned p) ->
            printf "%s is already cloned, skipping\n" p
        | Error (Aur.Web.Pkg_not_found p) ->
            eprintf "oaurutil: no AUR package named %s\n" p;
            exit 1
        | Error (Aur.Web.Git_failed { cmd; status = `Exit_non_zero code }) ->
            eprintf "oaurutil: %s failed (exit %d)\n" cmd code;
            exit 2
        | Error (Aur.Web.Git_failed { cmd; status = `Signal s }) ->
            eprintf "oaurutil: %s was killed by %s\n" cmd (Signal.to_string s);
            exit 2]

let command =
  Command.group ~summary:"aur utilities"
    [ ("search", search); ("fetch", fetch) ]

let () = Command_unix.run ~version:"1.0" command
