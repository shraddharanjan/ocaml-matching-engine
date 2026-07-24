open Core

type t =
  { book : Order_book.t
  ; next_order_sequence : int
  ; next_trade_sequence : int
  }
[@@deriving sexp]

type error =
  | Duplicate_order_id of Id.t
  | Unknown_order_id of Id.t
  | Invalid_quantity of int
[@@deriving sexp]

let empty = { book = Order_book.empty; next_order_sequence = 1; next_trade_sequence = 1 }
let book engine = engine.book

let best_opposing_order book side =
  match side with
  | Order.Side.Buy -> Order_book.best_ask book
  | Order.Side.Sell -> Order_book.best_bid book
;;

let prices_cross incoming resting_price =
  match Order.side incoming with
  | Order.Side.Buy -> Price.compare (Order.price incoming) resting_price >= 0
  | Order.Side.Sell -> Price.compare (Order.price incoming) resting_price <= 0
;;

let make_trade ~sequence ~incoming ~resting ~price ~quantity =
  match Order.side incoming with
  | Order.Side.Buy ->
    { Trade.buy_order_id = Order.id incoming
    ; sell_order_id = Order.id resting
    ; price
    ; quantity
    ; sequence
    }
  | Order.Side.Sell ->
    { Trade.buy_order_id = Order.id resting
    ; sell_order_id = Order.id incoming
    ; price
    ; quantity
    ; sequence
    }
;;

let rec match_order engine incoming trades =
  match best_opposing_order engine.book (Order.side incoming) with
  | None ->
    let updated_book = Order_book.add engine.book incoming in
    { engine with book = updated_book }, List.rev trades
  | Some (resting_price, resting_order) ->
    if not (prices_cross incoming resting_price)
    then (
      let updated_book = Order_book.add engine.book incoming in
      { engine with book = updated_book }, List.rev trades)
    else (
      let traded_quantity =
        Int.min (Order.quantity incoming) (Order.quantity resting_order)
      in
      let trade =
        make_trade
          ~sequence:engine.next_trade_sequence
          ~incoming
          ~resting:resting_order
          ~price:resting_price
          ~quantity:traded_quantity
      in
      let resting_quantity = Order.quantity resting_order - traded_quantity in
      let incoming_quantity = Order.quantity incoming - traded_quantity in
      let updated_book =
        if resting_quantity = 0
        then
          Order_book.update_best
            engine.book
            ~side:(Order.side resting_order)
            ~replacement:None
        else (
          let updated_resting_order =
            Order.with_quantity resting_order resting_quantity
          in
          Order_book.update_best
            engine.book
            ~side:(Order.side resting_order)
            ~replacement:(Some updated_resting_order))
      in
      let engine =
        { engine with
          book = updated_book
        ; next_trade_sequence = engine.next_trade_sequence + 1
        }
      in
      if incoming_quantity = 0
      then engine, List.rev (trade :: trades)
      else (
        let remaining_incoming = Order.with_quantity incoming incoming_quantity in
        match_order engine remaining_incoming (trade :: trades)))
;;

let submit_limit_order engine ~id ~side ~price ~quantity =
  if quantity <= 0
  then Error (Invalid_quantity quantity)
  else if Order_book.contains engine.book id
  then Error (Duplicate_order_id id)
  else (
    let order =
      Order.create ~id ~side ~price ~quantity ~sequence:engine.next_order_sequence
    in
    let engine = { engine with next_order_sequence = engine.next_order_sequence + 1 } in
    let engine, trades = match_order engine order [] in
    Ok (engine, trades))
;;

let cancel engine id =
  let updated_book, removed = Order_book.cancel engine.book id in
  match removed with
  | None -> Error (Unknown_order_id id)
  | Some order -> Ok ({ engine with book = updated_book }, order)
;;
