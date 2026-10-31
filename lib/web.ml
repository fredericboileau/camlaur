let aur_location = "https://aur.archlinux.org"
let aur_rpc_ver = 5
let ua_header = Cohttp.Header.init_with "User-Agent" "oaur"

let search term =
  let search_aur term =
    let aururl = Uri.of_string aur_location in
    let path = "/rpc" ^ "/v" ^ string_of_int aur_rpc_ver ^ "/search/" ^ term in
    let query = Uri.with_path aururl path in
    let open Lwt.Syntax in
    let open Cohttp_lwt_unix in
    let* _, body = Client.get ?headers:(Some ua_header) query in
    Cohttp_lwt.Body.to_string body
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
        let descr = member "Description" result |> to_string in
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
      results;
    Lwt.return ()
  in
  let open Lwt.Syntax in
  let* body = search_aur term in
  display_search_results body
