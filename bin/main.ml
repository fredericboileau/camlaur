open Core

let progname = "camlaur"

let search =
  Command.basic ~summary:"Search for aur package"
    [%map_open.Command
      let term = anon ("term" %: string) in
      fun () ->
        match Lwt_main.run (Aur.Web.search term) with
        | Ok () -> ()
        | Error (Aur.Web.Network_error msg) ->
            eprintf "%s: could not reach the AUR: %s\n" progname msg;
            exit 1
        | Error (Aur.Web.Aur_error msg) ->
            eprintf "%s: AUR error: %s\n" progname msg;
            exit 1
        | Error (Aur.Web.Bad_response msg) ->
            eprintf "%s: Bad response from aur: %s\n" progname msg;
            exit 1]

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
            eprintf "%s: no AUR package named %s\n" progname p;
            exit 1
        | Error (Aur.Web.Git_failed { cmd; status = `Exit_non_zero code }) ->
            eprintf "%s: %s failed (exit %d)\n" progname cmd code;
            exit 2
        | Error (Aur.Web.Git_failed { cmd; status = `Signal s }) ->
            eprintf "%s: %s was killed by %s\n" progname cmd
              (Signal.to_string s);
            exit 2
        | Error Aur.Web.Git_not_installed ->
            eprintf "%s: git is not installed\n" progname;
            exit 1]

let command =
  Command.group ~summary:"aur utilities"
    [ ("search", search); ("fetch", fetch) ]

let () = Command_unix.run ~version:"1.0" command
