open Core

type t =
  { buy_order_id : Id.t
  ; sell_order_id : Id.t
  ; price : Price.t
  ; quantity : int
  ; sequence : int
  }
[@@deriving equal, sexp]

let quantity trade = trade.quantity
let buy_order_id trade = trade.buy_order_id
let sell_order_id trade = trade.sell_order_id
let price trade = trade.price
let quantity trade = trade.quantity
