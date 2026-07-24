open Core

type t =
  { bids : Price_level.t Price.Map.t
  ; asks : Price_level.t Price.Map.t
  ; order_index : (Order.Side.t * Price.t) Id.Map.t
  }
[@@deriving sexp]

let empty = { bids = Price.Map.empty; asks = Price.Map.empty; order_index = Id.Map.empty }

let levels_for_side book = function
  | Order.Side.Buy -> book.bids
  | Order.Side.Sell -> book.asks
;;

let set_levels book side levels =
  match side with
  | Order.Side.Buy -> { book with bids = levels }
  | Order.Side.Sell -> { book with asks = levels }
;;

let add book order =
  if Map.mem book.order_index (Order.id order) then invalid_arg "Duplicate order ID";
  let levels = levels_for_side book (Order.side order) in
  let level =
    Map.find levels (Order.price order) |> Option.value ~default:Price_level.empty
  in
  let updated_level = Price_level.add level order in
  let updated_levels = Map.set levels ~key:(Order.price order) ~data:updated_level in
  let updated_index =
    Map.set
      book.order_index
      ~key:(Order.id order)
      ~data:(Order.side order, Order.price order)
  in
  let updated_book = set_levels book (Order.side order) updated_levels in
  { updated_book with order_index = updated_index }
;;

let best_bid book =
  match Map.max_elt book.bids with
  | None -> None
  | Some (price, level) ->
    Option.map (Price_level.peek level) ~f:(fun order -> price, order)
;;

let best_ask book =
  match Map.min_elt book.asks with
  | None -> None
  | Some (price, level) ->
    Option.map (Price_level.peek level) ~f:(fun order -> price, order)
;;

let update_best book ~side ~replacement =
  let levels = levels_for_side book side in
  let best_entry =
    match side with
    | Order.Side.Buy -> Map.max_elt levels
    | Order.Side.Sell -> Map.min_elt levels
  in
  match best_entry with
  | None -> book
  | Some (price, level) ->
    let current_order = Price_level.peek level |> Option.value_exn in
    let updated_level =
      match replacement with
      | Some updated_order -> Price_level.update_first level updated_order
      | None -> Price_level.remove_first level
    in
    let updated_levels =
      if Price_level.is_empty updated_level
      then Map.remove levels price
      else Map.set levels ~key:price ~data:updated_level
    in
    let updated_index =
      match replacement with
      | None -> Map.remove book.order_index (Order.id current_order)
      | Some updated_order ->
        Map.set
          book.order_index
          ~key:(Order.id updated_order)
          ~data:(Order.side updated_order, Order.price updated_order)
    in
    let updated_book = set_levels book side updated_levels in
    { updated_book with order_index = updated_index }
;;

let cancel book id =
  match Map.find book.order_index id with
  | None -> book, None
  | Some (side, price) ->
    let levels = levels_for_side book side in
    let level = Map.find_exn levels price in
    let updated_level, removed = Price_level.remove_order level id in
    let updated_levels =
      if Price_level.is_empty updated_level
      then Map.remove levels price
      else Map.set levels ~key:price ~data:updated_level
    in
    let updated_index = Map.remove book.order_index id in
    let updated_book = set_levels book side updated_levels in
    { updated_book with order_index = updated_index }, removed
;;

let contains book id = Map.mem book.order_index id
let order_count book = Map.length book.order_index
