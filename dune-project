(lang dune 3.24)

(name matching_engine)

(generate_opam_files true)

(authors "Shraddha Ranjan")

(maintainers "Shraddha Ranjan")


(package
 (name matching_engine)
 (synopsis "A price-time-priority limit order book written in OCaml")
 (description
  "A deterministic limit-order-book matching engine supporting limit orders,
   partial fills, price-time priority, cancellation, testing and benchmarking.")
 (depends
  ocaml
  dune
  core
  ppx_jane
  (alcotest :with-test)
  (qcheck :with-test)
  (qcheck-alcotest :with-test)
  core_bench)
 (tags
  ("ocaml"
   "order-book"
   "matching-engine"
   "finance"
   "algorithms")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
