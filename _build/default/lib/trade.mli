open Core

type t =
  { buy_order_id : Id.t
  ; sell_order_id : Id.t
  ; price : Price.t
  ; quantity : int
  ; sequence : int
  }
[@@deriving equal, sexp]

val quantity : t -> int
val buy_order_id : t -> Id.t
val sell_order_id : t -> Id.t
val price : t -> Price.t
val quantity : t -> int
