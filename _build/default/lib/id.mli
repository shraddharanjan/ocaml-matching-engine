open Core

type t [@@deriving compare, equal, hash, sexp]

val of_string : string -> t
val to_string : t -> string

include Comparable.S with type t := t
include Hashable.S with type t := t