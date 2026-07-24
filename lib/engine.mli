open Core

type t [@@deriving sexp]

type error =
  | Duplicate_order_id of Id.t
  | Unknown_order_id of Id.t
  | Invalid_quantity of int
[@@deriving sexp]

val empty : t

val submit_limit_order
  :  t
  -> id:Id.t
  -> side:Order.Side.t
  -> price:Price.t
  -> quantity:int
  -> (t * Trade.t list, error) Result.t

val cancel : t -> Id.t -> (t * Order.t, error) Result.t
val book : t -> Order_book.t
