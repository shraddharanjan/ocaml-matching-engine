open Core

type t [@@deriving sexp]

val empty : t
val add : t -> Order.t -> t
val cancel : t -> Id.t -> t * Order.t option
val best_bid : t -> (Price.t * Order.t) option
val best_ask : t -> (Price.t * Order.t) option
val contains : t -> Id.t -> bool
val order_count : t -> int
val update_best : t -> side:Order.Side.t -> replacement:Order.t option -> t
