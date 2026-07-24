open Core

type t [@@deriving sexp]

val empty : t
val is_empty : t -> bool
val add : t -> Order.t -> t
val peek : t -> Order.t option
val remove_first : t -> t
val update_first : t -> Order.t -> t
val remove_order : t -> Id.t -> t * Order.t option
val orders : t -> Order.t list
val total_quantity : t -> int