open Core

let search = 
  Command.basic
  ~summary:"Search for aur package"
  ~readme:(fun () -> "Search for aur package")
  [%map_open.Command
let term = anon ("term" %: string)
in 
  fun () -> Lwt_main.run(Aur.Commands.search term)]
