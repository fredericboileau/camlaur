(lang dune 3.24)

(name oaurutil)
(generate_opam_files true)
(source
 (github username/reponame))
(authors "Author Name <author@example.com>")
(maintainers "Maintainer Name <maintainer@example.com>")
(license LICENSE)
(documentation https://url/to/documentation)

(package
 (name oaurutil)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends ocaml dune core core_unix cohttp-lwt-unix tls-lwt lwt ocolor yojson)
 (tags
  ("add topics" "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
