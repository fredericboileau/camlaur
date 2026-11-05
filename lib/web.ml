open Util

let aur_location = "https://aur.archlinux.org"
let aur_rpc_ver = 5
let ua_header = Cohttp.Header.init_with "User-Agent" "oaur"

type search_error = Aur_error of string | Network_error of string

let search term =
  let search_aur term =
    let aururl = Uri.of_string aur_location in
    let path = "/rpc" ^ "/v" ^ string_of_int aur_rpc_ver ^ "/search/" ^ term in
    let query = Uri.with_path aururl path in
    let network_error = function
      | Unix.Unix_error (err, _, _) -> Network_error (Unix.error_message err)
      | exn -> Network_error (Printexc.to_string exn)
    in
    Lwt.catch
      (fun () ->
        let open Lwt.Syntax in
        let* _, body = Cohttp_lwt_unix.Client.get ~headers:ua_header query in
        let+ body_str = Cohttp_lwt.Body.to_string body in
        Ok body_str)
      (fun exn -> Lwt.return (Error (network_error exn)))
  in
  let display_search_results body =
    let osc8_link uri label =
      let st = "\o033\\" in
      let osc8 = "\o033]8" in
      Printf.sprintf "%s;;%s%s%s%s;;%s" osc8 uri st label osc8 st
    in
    let colored_pkg_name name =
      let fmt = Format.get_str_formatter () in
      Ocolor_format.prettify_formatter fmt;
      Format.fprintf fmt "@{<bold>@{<blue>aur@}/%s@}" name;
      Format.flush_str_formatter ()
    in
    let open Yojson.Basic in
    let open Yojson.Basic.Util in
    let results = from_string body |> member "results" |> to_list in
    List.iter
      (fun result ->
        let name = member "Name" result |> to_string in
        let ver = member "Version" result |> to_string in
        let numvotes = member "NumVotes" result |> to_int |> string_of_int in
        let popularity = member "Popularity" result |> to_number in
        let descr =
          member "Description" result
          |> to_string_option |> Option.value ~default:""
        in
        let ood =
          match member "OutOfDate" result |> to_number_option with
          | None -> ""
          | Some epoch ->
              Core_unix.strftime (Core_unix.gmtime epoch)
                "(Out-of-date: %d %B %Y)"
        in
        let label = colored_pkg_name name in
        let pre = osc8_link (aur_location ^ "/packages/" ^ name) label in
        let rest_fmt : _ format =
          "%s @{<bold>@{<green>%s@}@} (+%s %.2f%%) @{<bold;red>%s@}\n    %s\n"
        in
        Ocolor_format.printf rest_fmt pre ver numvotes popularity ood descr)
      results
  in
  let open Lwt.Syntax in
  let* body = search_aur term in
  match body with
  | Ok body ->
      display_search_results body;
      Lwt.return (Ok ())
  | Error e -> Lwt.return (Error e)

type fetch_error =
  | Pkg_not_found of string
  | Already_cloned of string
  | Git_failed of { cmd : string; status : Core_unix.Exit_or_signal.error }
  | Git_not_installed

let fetch pkgname : (unit, fetch_error) result =
  let open Core.Result.Let_syntax in
  let pkglocation = aur_location ^ "/" ^ pkgname in
  let check_git cmd = function
    | Ok () -> Ok ()
    | Error status -> Error (Git_failed { cmd; status })
  in
  let dir = Filename.concat pkgname ".git" in
  if Sys.file_exists dir && Sys.is_directory dir then
    Error (Already_cloned pkgname)
  else
    let%bind () = if in_path "git" then Ok () else Error Git_not_installed in
    let%bind () =
      match run_quiet "git" [ "ls-remote"; "--exit-code"; pkglocation ] with
      | Error (`Exit_non_zero 2) -> Error (Pkg_not_found pkgname)
      | status -> check_git "git ls-remote" status
    in
    check_git "git clone" (run "git" [ "clone"; pkglocation ])
