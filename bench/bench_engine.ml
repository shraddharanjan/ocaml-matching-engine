open Core
open Core_bench
open Matching_engine

let get_ok_exn = function
  | Ok value -> value
  | Error _ -> failwith "Benchmark setup unexpectedly failed"
;;

let submit_resting_sell engine ~id ~quantity =
  Engine.submit_limit_order
    engine
    ~id:(Id.of_string id)
    ~side:Order.Side.Sell
    ~price:(Price.of_ticks 10_000)
    ~quantity
  |> get_ok_exn
  |> fst
;;

(* This engine contains one resting sell order. Because the engine is
   immutable, every benchmark run may safely reuse this same value. *)
let engine_with_resting_sell = submit_resting_sell Engine.empty ~id:"sell-1" ~quantity:100

let benchmark_submit_to_empty_book =
  Bench.Test.create ~name:"submit one resting order" (fun () ->
    Engine.submit_limit_order
      Engine.empty
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:100
    |> Sys.opaque_identity
    |> ignore)
;;

let benchmark_full_match =
  Bench.Test.create ~name:"full match against one resting order" (fun () ->
    Engine.submit_limit_order
      engine_with_resting_sell
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:100
    |> Sys.opaque_identity
    |> ignore)
;;

let benchmark_partial_match =
  Bench.Test.create ~name:"partial match against one resting order" (fun () ->
    Engine.submit_limit_order
      engine_with_resting_sell
      ~id:(Id.of_string "buy-1")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:40
    |> Sys.opaque_identity
    |> ignore)
;;

let build_same_price_book order_count =
  List.fold (List.range 0 order_count) ~init:Engine.empty ~f:(fun engine index ->
    let id = Id.of_string (sprintf "sell-%d" index) in
    Engine.submit_limit_order
      engine
      ~id
      ~side:Order.Side.Sell
      ~price:(Price.of_ticks 10_000)
      ~quantity:1
    |> get_ok_exn
    |> fst)
;;

let benchmark_add_same_price_orders =
  Bench.Test.create ~name:"add 1,000 orders at one price" (fun () ->
    build_same_price_book 1_000 |> Sys.opaque_identity |> ignore)
;;

let engine_with_many_sells = build_same_price_book 1_000

let benchmark_sweep_same_price_level =
  Bench.Test.create ~name:"sweep 1,000 resting orders" (fun () ->
    Engine.submit_limit_order
      engine_with_many_sells
      ~id:(Id.of_string "large-buy")
      ~side:Order.Side.Buy
      ~price:(Price.of_ticks 10_000)
      ~quantity:1_000
    |> Sys.opaque_identity
    |> ignore)
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ benchmark_submit_to_empty_book
       ; benchmark_full_match
       ; benchmark_partial_match
       ; benchmark_add_same_price_orders
       ; benchmark_sweep_same_price_level
       ])
;;
