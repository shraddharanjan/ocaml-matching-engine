open Core
open Matching_engine

let get_ok = function
  | Ok value -> value
  | Error _ -> failwith "Expected operation to succeed"
;;

let test_full_match () =
  let engine = Engine.empty in
  let engine, sell_trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  Alcotest.(check int) "resting sell produces no trade" 0 (List.length sell_trades);
  let engine, buy_trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_100)
      ~quantity:10
    |> get_ok
  in
  Alcotest.(check int) "one trade created" 1 (List.length buy_trades);
  Alcotest.(check int)
    "book empty after full match"
    0
    (Order_book.order_count (Engine.book engine));
  let trade = List.hd_exn buy_trades in
  Alcotest.(check int) "trade quantity" 10 trade.quantity;
  Alcotest.(check int) "trade uses resting price" 10_000 (Price.to_ticks trade.price)
;;

let test_partial_fill () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:100
    |> get_ok
  in
  let engine, trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:40
    |> get_ok
  in
  Alcotest.(check int) "one trade" 1 (List.length trades);
  Alcotest.(check int)
    "one resting order remains"
    1
    (Order_book.order_count (Engine.book engine));
  match Order_book.best_ask (Engine.book engine) with
  | None -> Alcotest.fail "Expected a remaining sell order"
  | Some (_, order) -> Alcotest.(check int) "remaining quantity" 60 (Order.quantity order)
;;

let test_fifo_same_price () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-2")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let engine, trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let trade = List.hd_exn trades in
  Alcotest.(check string)
    "first resting order matched"
    "sell-1"
    (Id.to_string trade.sell_order_id);
  match Order_book.best_ask (Engine.book engine) with
  | None -> Alcotest.fail "Expected sell-2 to remain"
  | Some (_, order) ->
    Alcotest.(check string)
      "second order remains"
      "sell-2"
      (Id.to_string (Order.id order))
;;

let test_matches_multiple_orders () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-2")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_100)
      ~quantity:20
    |> get_ok
  in
  let engine, trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_100)
      ~quantity:25
    |> get_ok
  in
  Alcotest.(check int) "two trades created" 2 (List.length trades);
  let first_trade = List.nth_exn trades 0 in
  let second_trade = List.nth_exn trades 1 in
  Alcotest.(check string)
    "first trade matches best ask"
    "sell-1"
    (Id.to_string first_trade.sell_order_id);
  Alcotest.(check int) "first trade quantity" 10 first_trade.quantity;
  Alcotest.(check int) "first trade price" 10_000 (Price.to_ticks first_trade.price);
  Alcotest.(check string)
    "second trade matches next ask"
    "sell-2"
    (Id.to_string second_trade.sell_order_id);
  Alcotest.(check int) "second trade quantity" 15 second_trade.quantity;
  Alcotest.(check int) "second trade price" 10_100 (Price.to_ticks second_trade.price);
  Alcotest.(check int)
    "one resting order remains"
    1
    (Order_book.order_count (Engine.book engine));
  match Order_book.best_ask (Engine.book engine) with
  | None -> Alcotest.fail "Expected sell-2 to remain partially filled"
  | Some (price, order) ->
    Alcotest.(check int) "remaining ask price" 10_100 (Price.to_ticks price);
    Alcotest.(check string) "remaining order" "sell-2" (Id.to_string (Order.id order));
    Alcotest.(check int) "remaining quantity" 5 (Order.quantity order)
;;

let test_non_crossing_orders_rest () =
  let engine = Engine.empty in
  let engine, sell_trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_100)
      ~quantity:10
    |> get_ok
  in
  let engine, buy_trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  Alcotest.(check int) "sell produces no trade" 0 (List.length sell_trades);
  Alcotest.(check int) "buy produces no trade" 0 (List.length buy_trades);
  Alcotest.(check int) "two orders remain" 2 (Order_book.order_count (Engine.book engine));
  match Order_book.best_bid (Engine.book engine) with
  | None -> Alcotest.fail "Expected a best bid"
  | Some (price, order) ->
    Alcotest.(check int) "best bid price" 10_000 (Price.to_ticks price);
    Alcotest.(check string) "best bid ID" "buy-1" (Id.to_string (Order.id order));
    (match Order_book.best_ask (Engine.book engine) with
     | None -> Alcotest.fail "Expected a best ask"
     | Some (price, order) ->
       Alcotest.(check int) "best ask price" 10_100 (Price.to_ticks price);
       Alcotest.(check string) "best ask ID" "sell-1" (Id.to_string (Order.id order)))
;;

let test_duplicate_order_id_rejected () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "order-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let result =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "order-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_100)
      ~quantity:20
  in
  match result with
  | Error (Engine.Duplicate_order_id id) ->
    Alcotest.(check string) "duplicate ID returned" "order-1" (Id.to_string id);
    Alcotest.(check int)
      "original order remains"
      1
      (Order_book.order_count (Engine.book engine))
  | Error _ -> Alcotest.fail "Expected Duplicate_order_id error"
  | Ok _ -> Alcotest.fail "Expected duplicate order to be rejected"
;;

let test_better_price_matches_first () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-expensive")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_100)
      ~quantity:10
    |> get_ok
  in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-cheap")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let engine, trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_100)
      ~quantity:10
    |> get_ok
  in
  Alcotest.(check int) "one trade created" 1 (List.length trades);
  let trade = List.hd_exn trades in
  Alcotest.(check string)
    "cheapest sell order matched first"
    "sell-cheap"
    (Id.to_string trade.sell_order_id);
  Alcotest.(check int)
    "trade uses cheapest resting price"
    10_000
    (Price.to_ticks trade.price);
  Alcotest.(check int)
    "one resting order remains"
    1
    (Order_book.order_count (Engine.book engine));
  match Order_book.best_ask (Engine.book engine) with
  | None -> Alcotest.fail "Expected the more expensive sell order to remain"
  | Some (price, order) ->
    Alcotest.(check int) "remaining ask price" 10_100 (Price.to_ticks price);
    Alcotest.(check string)
      "expensive sell remains"
      "sell-expensive"
      (Id.to_string (Order.id order))
;;

let test_cancel_existing_order () =
  let engine = Engine.empty in
  let order_id = Id.of_string "buy-1" in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:order_id
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:25
    |> get_ok
  in
  Alcotest.(check bool)
    "order exists before cancellation"
    true
    (Order_book.contains (Engine.book engine) order_id);
  let engine, cancelled_order = Engine.cancel engine order_id |> get_ok in
  Alcotest.(check string)
    "correct order cancelled"
    "buy-1"
    (Id.to_string (Order.id cancelled_order));
  Alcotest.(check int) "cancelled order quantity" 25 (Order.quantity cancelled_order);
  Alcotest.(check bool)
    "order absent after cancellation"
    false
    (Order_book.contains (Engine.book engine) order_id);
  Alcotest.(check int)
    "book empty after cancellation"
    0
    (Order_book.order_count (Engine.book engine))
;;

let test_cancel_unknown_order () =
  let engine = Engine.empty in
  let missing_id = Id.of_string "missing-order" in
  match Engine.cancel engine missing_id with
  | Error (Engine.Unknown_order_id id) ->
    Alcotest.(check string) "unknown ID returned" "missing-order" (Id.to_string id);
    Alcotest.(check int)
      "book remains empty"
      0
      (Order_book.order_count (Engine.book engine))
  | Error _ -> Alcotest.fail "Expected Unknown_order_id error"
  | Ok _ -> Alcotest.fail "Expected cancellation to fail"
;;

let test_zero_quantity_rejected () =
  let engine = Engine.empty in
  let result =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-zero")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:0
  in
  match result with
  | Error (Engine.Invalid_quantity quantity) ->
    Alcotest.(check int) "invalid quantity returned" 0 quantity;
    Alcotest.(check int)
      "invalid order not added"
      0
      (Order_book.order_count (Engine.book engine))
  | Error _ -> Alcotest.fail "Expected Invalid_quantity error"
  | Ok _ -> Alcotest.fail "Expected zero quantity to be rejected"
;;

let test_negative_quantity_rejected () =
  let engine = Engine.empty in
  let result =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-negative")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:(-10)
  in
  match result with
  | Error (Engine.Invalid_quantity quantity) ->
    Alcotest.(check int) "invalid quantity returned" (-10) quantity;
    Alcotest.(check int)
      "invalid order not added"
      0
      (Order_book.order_count (Engine.book engine))
  | Error _ -> Alcotest.fail "Expected Invalid_quantity error"
  | Ok _ -> Alcotest.fail "Expected negative quantity to be rejected"
;;

let test_cancel_preserves_remaining_orders () =
  let engine = Engine.empty in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-1")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-2")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:20
    |> get_ok
  in
  let engine, _ =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "sell-3")
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:30
    |> get_ok
  in
  let engine, cancelled = Engine.cancel engine (Id.of_string "sell-2") |> get_ok in
  Alcotest.(check string)
    "middle order cancelled"
    "sell-2"
    (Id.to_string (Order.id cancelled));
  Alcotest.(check int) "two orders remain" 2 (Order_book.order_count (Engine.book engine));
  let engine, trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:10
    |> get_ok
  in
  let trade = List.hd_exn trades in
  Alcotest.(check string)
    "first order still matched first"
    "sell-1"
    (Id.to_string trade.sell_order_id);
  match Order_book.best_ask (Engine.book engine) with
  | None -> Alcotest.fail "Expected sell-3 to remain"
  | Some (_, order) ->
    Alcotest.(check string)
      "third order remains after first is filled"
      "sell-3"
      (Id.to_string (Order.id order))
;;

let () =
  Alcotest.run
    "Matching engine"
    [ ( "limit orders"
      , [ Alcotest.test_case "full match" `Quick test_full_match
        ; Alcotest.test_case "partial fill" `Quick test_partial_fill
        ; Alcotest.test_case "FIFO at same price" `Quick test_fifo_same_price
        ; Alcotest.test_case "matches multiple orders" `Quick test_matches_multiple_orders
        ; Alcotest.test_case
            "non-crossing orders rest"
            `Quick
            test_non_crossing_orders_rest
        ; Alcotest.test_case
            "duplicate order ID rejected"
            `Quick
            test_duplicate_order_id_rejected
        ; Alcotest.test_case
            "better price matches first"
            `Quick
            test_better_price_matches_first
        ] )
    ; ( "cancellation"
      , [ Alcotest.test_case "cancel existing order" `Quick test_cancel_existing_order
        ; Alcotest.test_case "cancel unknown order" `Quick test_cancel_unknown_order
        ; Alcotest.test_case
            "cancellation preserves order"
            `Quick
            test_cancel_preserves_remaining_orders
        ] )
    ; ( "validation"
      , [ Alcotest.test_case "zero quantity rejected" `Quick test_zero_quantity_rejected
        ; Alcotest.test_case
            "negative quantity rejected"
            `Quick
            test_negative_quantity_rejected
        ] )
    ]
;;
