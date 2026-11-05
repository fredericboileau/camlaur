let run ?(quiet = false) ?(quiet_stderr = false) ?env prog args :
    Core_unix.Exit_or_signal.t =
  let open Core_unix in
  let devnull = lazy (openfile "/dev/null" ~mode:[ O_WRONLY ]) in
  let out = if quiet then Lazy.force devnull else stdout in
  let err = if quiet_stderr then Lazy.force devnull else stderr in
  let child =
    Fun.protect
      ~finally:(fun () ->
        if Lazy.is_val devnull then close (Lazy.force devnull))
      (fun () ->
        create_process_with_fds ?env ~prog ~args ~stdin:(Fd_spec.Use_this stdin)
          ~stdout:(Fd_spec.Use_this out) ~stderr:(Fd_spec.Use_this err) ())
  in
  waitpid child.pid

let run_quiet = run ~quiet:true ~quiet_stderr:true

let in_path prog =
  match Sys.getenv_opt "PATH" with
  | None -> false
  | Some path ->
      String.split_on_char ':' path
      |> List.exists (fun dir -> Sys.file_exists (Filename.concat dir prog))
