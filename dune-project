(lang dune 3.24)

(name oaurutil)
(generate_opam_files true)
(source
 (github fredericboileau/oaurutils))
(authors "Frederic Boileau <frederic.boileau@protonmail.com>")
(maintainers "Frederic Boileau <frederic.boileau@protonmail.com>")
(license BSD-3-Clause)
; (documentation https://url/to/documentation)

(package
 (name oaurutil)
 (synopsis "A rewrite of Alad's aurutils for archlinux in ocaml")
 (description "Hobby project")
 (depends ocaml dune core core_unix ppx_let cohttp-lwt-unix tls-lwt lwt ocolor yojson))
 ;
 ; (tags
 ;  ("add topics" "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
