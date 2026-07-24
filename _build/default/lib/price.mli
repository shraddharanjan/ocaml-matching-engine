open Core

type t [@@deriving compare, equal, sexp]

val of_ticks : int -> t
val to_ticks : t -> int
val of_string : string -> t Or_error.t
val to_string : t -> string

include Comparable.S with type t := t