open Core
open Matching_engine

(* ---------- Helpers ---------- *)

let get_ok = function
  | Ok value -> Some value
  | Error _ -> None
;;

let no_crossed_book engine =
  let book = Engine.book engine in
  match Order_book.best_bid book, Order_book.best_ask book with
  | Some (best_bid, _), Some (best_ask, _) -> Price.compare best_bid best_ask < 0
  | _ -> true
;;

let total_trade_quantity trades = List.sum (module Int) trades ~f:Trade.quantity

let remaining_quantity engine =
  let book = Engine.book engine in
  match Order_book.best_bid book, Order_book.best_ask book with
  | None, None -> 0
  | Some (_, order), None | None, Some (_, order) -> Order.quantity order
  | Some _, Some _ ->
    (* This helper is used only in properties where at most
         one order should remain. *)
    -1
;;

let side_generator = QCheck.oneof_list [ Order.Side.Buy; Order.Side.Sell ]
let valid_price_generator = QCheck.(0 -- 1_000_000)
let valid_quantity_generator = QCheck.(1 -- 10_000)

(* ---------- Domain-type properties ---------- *)

let price_round_trip =
  QCheck.Test.make
    ~count:1_000
    ~name:"Price.of_ticks and Price.to_ticks round-trip"
    valid_price_generator
    (fun ticks ->
       let price = Price.of_ticks ticks in
       Price.to_ticks price = ticks)
;;

let non_empty_string_generator =
  QCheck.Gen.(string_size ~gen:printable (1 -- 50)) |> QCheck.make
;;

let id_round_trip =
  QCheck.Test.make
    ~count:1_000
    ~name:"Id.of_string and Id.to_string round-trip"
    non_empty_string_generator
    (fun text ->
       let id = Id.of_string text in
       String.equal (Id.to_string id) text)
;;

(* ---------- Single-order property ---------- *)

let single_order_generator =
  QCheck.triple side_generator valid_price_generator valid_quantity_generator
;;

let single_order_rests =
  QCheck.Test.make
    ~count:500
    ~name:"A single valid order rests in an empty book"
    single_order_generator
    (fun (side, price_ticks, quantity) ->
       let result =
         Engine.submit_limit_order
           Engine.empty
           ~id:(Id.of_string "order-1")
           ~side
           ~price:(Price.of_ticks price_ticks)
           ~quantity
       in
       match result with
       | Error _ -> false
       | Ok (engine, trades) ->
         List.is_empty trades
         && Order_book.order_count (Engine.book engine) = 1
         && no_crossed_book engine)
;;

(* ---------- Non-crossing-order property ---------- *)

let non_crossing_generator =
  QCheck.(
    pair
      (0 -- 999_000)
      (triple (1 -- 1_000) valid_quantity_generator valid_quantity_generator))
;;

let non_crossing_orders_rest =
  QCheck.Test.make
    ~count:500
    ~name:"Non-crossing buy and sell orders both rest"
    non_crossing_generator
    (fun (buy_ticks, (spread, buy_quantity, sell_quantity)) ->
       let sell_ticks = buy_ticks + spread in
       match
         Engine.submit_limit_order
           Engine.empty
           ~id:(Id.of_string "sell-1")
           ~side:Order.Side.Sell
           ~price:(Price.of_ticks sell_ticks)
           ~quantity:sell_quantity
       with
       | Error _ -> false
       | Ok (engine, sell_trades) ->
         (match
            Engine.submit_limit_order
              engine
              ~id:(Id.of_string "buy-1")
              ~side:Order.Side.Buy
              ~price:(Price.of_ticks buy_ticks)
              ~quantity:buy_quantity
          with
          | Error _ -> false
          | Ok (engine, buy_trades) ->
            List.is_empty sell_trades
            && List.is_empty buy_trades
            && Order_book.order_count (Engine.book engine) = 2
            && no_crossed_book engine))
;;

(* ---------- Crossing-order properties ---------- *)

(*
   This generator creates:

   - an incoming side;
   - a base price;
   - a price improvement;
   - a resting quantity;
   - an incoming quantity.

   For an incoming buy:
     resting sell = base
     incoming buy = base + improvement

   For an incoming sell:
     resting buy = base + improvement
     incoming sell = base

   Therefore the two orders are always guaranteed to cross.
*)
let crossing_case_generator =
  QCheck.pair
    side_generator
    QCheck.(
      pair
        (0 -- 999_000)
        (pair (0 -- 1_000) (pair valid_quantity_generator valid_quantity_generator)))
;;

let run_crossing_case
      incoming_side
      base_ticks
      improvement
      resting_quantity
      incoming_quantity
  =
  let resting_side = Order.Side.opposite incoming_side in
  let resting_ticks, incoming_ticks =
    match incoming_side with
    | Order.Side.Buy -> base_ticks, base_ticks + improvement
    | Order.Side.Sell -> base_ticks + improvement, base_ticks
  in
  match
    Engine.submit_limit_order
      Engine.empty
      ~id:(Id.of_string "resting-1")
      ~side:resting_side
      ~price:(Price.of_ticks resting_ticks)
      ~quantity:resting_quantity
  with
  | Error error -> Error error
  | Ok (engine, _) ->
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "incoming-1")
      ~side:incoming_side
      ~price:(Price.of_ticks incoming_ticks)
      ~quantity:incoming_quantity
;;

let crossing_orders_trade =
  QCheck.Test.make
    ~count:1_000
    ~name:"Guaranteed crossing orders produce one trade"
    crossing_case_generator
    (fun
        (incoming_side, (base_ticks, (improvement, (resting_quantity, incoming_quantity))))
       ->
       match
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       with
       | Error _ -> false
       | Ok (engine, trades) ->
         let expected_trade_quantity = Int.min resting_quantity incoming_quantity in
         List.length trades = 1
         && total_trade_quantity trades = expected_trade_quantity
         && no_crossed_book engine)
;;

let crossing_orders_use_resting_price =
  QCheck.Test.make
    ~count:1_000
    ~name:"Crossing orders execute at the resting price"
    crossing_case_generator
    (fun
        (incoming_side, (base_ticks, (improvement, (resting_quantity, incoming_quantity))))
       ->
       let expected_resting_ticks =
         match incoming_side with
         | Order.Side.Buy -> base_ticks
         | Order.Side.Sell -> base_ticks + improvement
       in
       match
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       with
       | Error _ -> false
       | Ok (_, trades) ->
         (match trades with
          | [ trade ] -> Price.to_ticks trade.price = expected_resting_ticks
          | _ -> false))
;;

let crossing_orders_conserve_quantity =
  QCheck.Test.make
    ~count:1_000
    ~name:"Crossing orders conserve quantity"
    crossing_case_generator
    (fun
        (incoming_side, (base_ticks, (improvement, (resting_quantity, incoming_quantity))))
       ->
       match
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       with
       | Error _ -> false
       | Ok (engine, trades) ->
         let submitted_quantity = resting_quantity + incoming_quantity in
         let executed_quantity = total_trade_quantity trades in
         let resting_quantity_after = remaining_quantity engine in
         submitted_quantity = (2 * executed_quantity) + resting_quantity_after)
;;

let crossing_orders_leave_correct_count =
  QCheck.Test.make
    ~count:1_000
    ~name:"Crossing orders leave the correct number of resting orders"
    crossing_case_generator
    (fun
        (incoming_side, (base_ticks, (improvement, (resting_quantity, incoming_quantity))))
       ->
       match
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       with
       | Error _ -> false
       | Ok (engine, _) ->
         let expected_count = if resting_quantity = incoming_quantity then 0 else 1 in
         Order_book.order_count (Engine.book engine) = expected_count)
;;

(* ---------- Cancellation property ---------- *)

let cancellation_generator =
  QCheck.triple side_generator valid_price_generator valid_quantity_generator
;;

let submitted_order_can_be_cancelled =
  QCheck.Test.make
    ~count:500
    ~name:"A resting order can be cancelled"
    cancellation_generator
    (fun (side, price_ticks, quantity) ->
       let id = Id.of_string "cancel-me" in
       let price = Price.of_ticks price_ticks in
       match Engine.submit_limit_order Engine.empty ~id ~side ~price ~quantity with
       | Error _ -> false
       | Ok (engine, _) ->
         (match Engine.cancel engine id with
          | Error _ -> false
          | Ok (engine, cancelled_order) ->
            Id.equal (Order.id cancelled_order) id
            && Order.Side.equal (Order.side cancelled_order) side
            && Price.equal (Order.price cancelled_order) price
            && Order.quantity cancelled_order = quantity
            && Order_book.order_count (Engine.book engine) = 0))
;;

(* ---------- Duplicate-ID property ---------- *)

let duplicate_id_rejected =
  QCheck.Test.make
    ~count:500
    ~name:"An active duplicate order ID is rejected"
    single_order_generator
    (fun (side, price_ticks, quantity) ->
       let id = Id.of_string "duplicate-id" in
       match
         Engine.submit_limit_order
           Engine.empty
           ~id
           ~side
           ~price:(Price.of_ticks price_ticks)
           ~quantity
       with
       | Error _ -> false
       | Ok (engine, _) ->
         (match
            Engine.submit_limit_order
              engine
              ~id
              ~side:(Order.Side.opposite side)
              ~price:(Price.of_ticks price_ticks)
              ~quantity
          with
          | Error (Engine.Duplicate_order_id returned_id) ->
            Id.equal returned_id id && Order_book.order_count (Engine.book engine) = 1
          | Error _ -> false
          | Ok _ -> false))
;;

(* ---------- Invalid-quantity property ---------- *)

let invalid_quantity_generator = QCheck.(-10_000 -- 0)

let non_positive_quantity_rejected =
  QCheck.Test.make
    ~count:500
    ~name:"Non-positive quantities are rejected"
    invalid_quantity_generator
    (fun quantity ->
       match
         Engine.submit_limit_order
           Engine.empty
           ~id:(Id.of_string "invalid-order")
           ~side:Order.Side.Buy
           ~price:(Price.of_ticks 10_000)
           ~quantity
       with
       | Error (Engine.Invalid_quantity returned_quantity) -> returned_quantity = quantity
       | Error _ -> false
       | Ok _ -> false)
;;

(* ---------- Determinism property ---------- *)

let crossing_is_deterministic =
  QCheck.Test.make
    ~count:500
    ~name:"The same command sequence produces the same result"
    crossing_case_generator
    (fun
        (incoming_side, (base_ticks, (improvement, (resting_quantity, incoming_quantity))))
       ->
       let first_result =
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       in
       let second_result =
         run_crossing_case
           incoming_side
           base_ticks
           improvement
           resting_quantity
           incoming_quantity
       in
       match first_result, second_result with
       | Ok (first_engine, first_trades), Ok (second_engine, second_trades) ->
         Sexp.equal (Engine.sexp_of_t first_engine) (Engine.sexp_of_t second_engine)
         && List.equal Trade.equal first_trades second_trades
       | Error _, Error _ -> true
       | _ -> false)
;;

(* ---------- Test registration ---------- *)

let to_alcotest properties = List.map properties ~f:QCheck_alcotest.to_alcotest

let () =
  Alcotest.run
    "Matching engine properties"
    [ "domain types", to_alcotest [ price_round_trip; id_round_trip ]
    ; ( "submission"
      , to_alcotest
          [ single_order_rests
          ; non_crossing_orders_rest
          ; duplicate_id_rejected
          ; non_positive_quantity_rejected
          ] )
    ; ( "matching"
      , to_alcotest
          [ crossing_orders_trade
          ; crossing_orders_use_resting_price
          ; crossing_orders_conserve_quantity
          ; crossing_orders_leave_correct_count
          ; crossing_is_deterministic
          ] )
    ; "cancellation", to_alcotest [ submitted_order_can_be_cancelled ]
    ]
;;
