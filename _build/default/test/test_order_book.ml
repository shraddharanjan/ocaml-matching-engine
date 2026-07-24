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

  Alcotest.(check int)
    "resting sell produces no trade"
    0
    (List.length sell_trades);

  let engine, buy_trades =
    Engine.submit_limit_order
      engine
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_100)
      ~quantity:10
    |> get_ok
  in

  Alcotest.(check int)
    "one trade created"
    1
    (List.length buy_trades);

  Alcotest.(check int)
    "book empty after full match"
    0
    (Order_book.order_count (Engine.book engine));

  let trade = List.hd_exn buy_trades in

  Alcotest.(check int)
    "trade quantity"
    10
    trade.quantity;

  Alcotest.(check int)
    "trade uses resting price"
    10_000
    (Price.to_ticks trade.price)
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

  Alcotest.(check int)
    "one trade"
    1
    (List.length trades);

  Alcotest.(check int)
    "one resting order remains"
    1
    (Order_book.order_count (Engine.book engine));

  match Order_book.best_ask (Engine.book engine) with
  | None ->
      Alcotest.fail "Expected a remaining sell order"
  | Some (_, order) ->
      Alcotest.(check int)
        "remaining quantity"
        60
        (Order.quantity order)
;;

let () =
  Alcotest.run
    "Matching engine"
    [ ( "limit orders"
      , [ Alcotest.test_case
            "full match"
            `Quick
            test_full_match
        ; Alcotest.test_case
            "partial fill"
            `Quick
            test_partial_fill
        ] )
    ]
;;