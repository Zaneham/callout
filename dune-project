(lang dune 3.0)
(name callout)

(generate_opam_files true)

(source (github Zaneham/callout))
(license Apache-2.0)

(package
 (name callout-shared)
 (synopsis "Callout CAD shared types and protocol"))

(package
 (name callout-core)
 (synopsis "Callout CAD core domain logic")
 (depends callout-shared))

(package
 (name callout-client)
 (synopsis "Callout CAD web frontend")
 (depends callout-shared js_of_ocaml js_of_ocaml-ppx js_of_ocaml-lwt)
 (allow_empty))

(package
 (name callout-engine)
 (synopsis "Callout CAD headless dispatch engine")
 (depends callout-core))

(package
 (name callout-harness)
 (synopsis "Callout CAD headless test harness")
 (depends callout-engine))

(package
 (name callout-test)
 (synopsis "Callout CAD test suite")
 (depends callout-core alcotest)
 (allow_empty))
