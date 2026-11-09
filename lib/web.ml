open Util

let aur_location = "https://aur.archlinux.org"
let aur_rpc_ver = 5
let ua_header = Cohttp.Header.init_with "User-Agent" "camlaur"

type search_error =
  | Aur_error of string
  | Network_error of string
  | Bad_response of string

type response_parsed = {
  name : string;
  ver : string;
  numvotes : string;
  popularity : float;
  descr : string option;
  ood : string;
}

let search term =
  let open Yojson.Basic in
  let open Yojson.Basic.Util in
  let open Lwt.Syntax in
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
        let* _, body = Cohttp_lwt_unix.Client.get ~headers:ua_header query in
        let+ body_str = Cohttp_lwt.Body.to_string body in
        Ok body_str)
      (fun exn -> Lwt.return (Error (network_error exn)))
  in
  let parse_aur body : (response_parsed list, search_error) result =
    try
      let json = from_string body in
      match member "type" json |> to_string_option with
      | Some "error" ->
          let msg =
            member "error" json |> to_string_option
            |> Option.value ~default:"unknown error"
          in
          Error (Aur_error msg)
      | _ ->
          Ok
            (member "results" json |> to_list
            |> List.map (fun r ->
                let name = member "Name" r |> to_string in
                let ver = member "Version" r |> to_string in
                let numvotes = member "NumVotes" r |> to_int |> string_of_int in
                let popularity = member "Popularity" r |> to_number in
                let descr = member "Description" r |> to_string_option in
                let ood =
                  match member "OutOfDate" r |> to_number_option with
                  | None -> ""
                  | Some epoch ->
                      Core_unix.strftime (Core_unix.gmtime epoch)
                        "(Out-of-date: %d %B %Y)"
                in
                { name; ver; numvotes; popularity; descr; ood }))
    with
    | Yojson.Json_error msg -> Error (Bad_response msg)
    | Yojson.Basic.Util.Type_error (msg, _) -> Error (Bad_response msg)
  in
  let display_search_results results =
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
    List.iter
      (fun r ->
        let label = colored_pkg_name r.name in
        let pre = osc8_link (aur_location ^ "/packages/" ^ r.name) label in
        let rest_fmt : _ format =
          "%s @{<bold>@{<green>%s@}@} (+%s %.2f%%) @{<bold;red>%s@}\n    %s\n"
        in
        Ocolor_format.printf rest_fmt pre r.ver r.numvotes r.popularity r.ood
          (Option.value ~default:"" r.descr))
      results
  in
  let* results = search_aur term in
  Lwt.return
    (let ( let* ) = Result.bind in
     let* body = results in
     let* parsed = parse_aur body in
     display_search_results parsed;
     Ok ())

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
    let ( let* ) = Result.bind in
    let* () = if in_path "git" then Ok () else Error Git_not_installed in
    let* () =
      match run_quiet "git" [ "ls-remote"; "--exit-code"; pkglocation ] with
      | Error (`Exit_non_zero 2) -> Error (Pkg_not_found pkgname)
      | status -> check_git "git ls-remote" status
    in
    check_git "git clone" (run "git" [ "clone"; pkglocation ])
