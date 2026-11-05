(lang dune 3.24)
(name camlaur)
(source
 (github fredericboileau/camlaur))
(authors "Frederic Boileau <frederic.boileau@protonmail.com>")
(maintainers "Frederic Boileau <frederic.boileau@protonmail.com>")
(license BSD-3-Clause)

(package
 (name camlaur)
 (synopsis "A rewrite of Alad's aurutils for archlinux in ocaml")
 (description "Hobby project")
 (depends ocaml dune core core_unix ppx_let cohttp-lwt-unix tls-lwt lwt ocolor yojson))
