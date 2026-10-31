open Core

let search =
  Command.basic ~summary:"Search for aur package"
    [%map_open.Command
      let term = anon ("term" %: string) in
      fun () -> Lwt_main.run (Aur.Web.search term)]

let command = Command.group ~summary:"aur utilities" [ ("search", search) ]
let () = Command_unix.run ~version:"1.0" ~build_info:"RWO" command
