open Core

module Side = struct
  type t =
    | Buy
    | Sell
  [@@deriving compare, equal, sexp]

  let opposite = function
    | Buy -> Sell
    | Sell -> Buy
  ;;
end

type t =
  { id : Id.t
  ; side : Side.t
  ; price : Price.t
  ; quantity : int
  ; sequence : int
  }
[@@deriving equal, sexp]

let create ~id ~side ~price ~quantity ~sequence =
  if quantity <= 0 then invalid_arg "Quantity must be positive";
  { id; side; price; quantity; sequence }
;;

let id order = order.id
let side order = order.side
let price order = order.price
let quantity order = order.quantity
let sequence order = order.sequence

let with_quantity order quantity =
  if quantity <= 0 then invalid_arg "Quantity must be positive";
  { order with quantity }
;;