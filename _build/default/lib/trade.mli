open Core

type t =
  { buy_order_id : Id.t
  ; sell_order_id : Id.t
  ; price : Price.t
  ; quantity : int
  ; sequence : int
  }
[@@deriving equal, sexp]