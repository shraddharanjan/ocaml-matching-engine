open Core
open Matching_engine

let print_trade trade =
  printf
    "TRADE buyer=%s seller=%s price=%s quantity=%d\n"
    (Id.to_string (Trade.buy_order_id trade))
    (Id.to_string (Trade.sell_order_id trade))
    (Price.to_string (Trade.price trade))
    (Trade.quantity trade)
;;

let print_engine_error = function
  | Engine.Duplicate_order_id id ->
    printf "ERROR duplicate order ID: %s\n" (Id.to_string id)
  | Engine.Unknown_order_id id -> printf "ERROR unknown order ID: %s\n" (Id.to_string id)
  | Engine.Invalid_quantity quantity -> printf "ERROR invalid quantity: %d\n" quantity
;;

let parse_side = function
  | "BUY" -> Ok Order.Side.Buy
  | "SELL" -> Ok Order.Side.Sell
  | value -> Or_error.errorf "Unknown side: %s" value
;;

let submit_order engine side_text id_text price_text quantity_text =
  let open Or_error.Let_syntax in
  let%bind side = parse_side side_text in
  let%bind price = Price.of_string price_text in
  let%bind quantity = Or_error.try_with (fun () -> Int.of_string quantity_text) in
  let id = Id.of_string id_text in
  match Engine.submit_limit_order engine ~id ~side ~price ~quantity with
  | Error error ->
    print_engine_error error;
    Ok engine
  | Ok (engine, trades) ->
    printf "ACCEPTED %s\n" id_text;
    List.iter trades ~f:print_trade;
    Ok engine
;;

let cancel_order engine id_text =
  let id = Id.of_string id_text in
  match Engine.cancel engine id with
  | Error error ->
    print_engine_error error;
    engine
  | Ok (engine, order) ->
    printf "CANCELLED %s remaining=%d\n" id_text (Order.quantity order);
    engine
;;

let print_book engine =
  let book = Engine.book engine in
  (match Order_book.best_bid book with
   | None -> printf "BEST BID: none\n"
   | Some (price, order) ->
     printf
       "BEST BID: %s quantity=%d id=%s\n"
       (Price.to_string price)
       (Order.quantity order)
       (Id.to_string (Order.id order)));
  match Order_book.best_ask book with
  | None -> printf "BEST ASK: none\n"
  | Some (price, order) ->
    printf
      "BEST ASK: %s quantity=%d id=%s\n"
      (Price.to_string price)
      (Order.quantity order)
      (Id.to_string (Order.id order))
;;

let print_help () =
  print_endline "Commands:";
  print_endline "  BUY <id> <price> <quantity>";
  print_endline "  SELL <id> <price> <quantity>";
  print_endline "  CANCEL <id>";
  print_endline "  BOOK";
  print_endline "  HELP";
  print_endline "  QUIT"
;;

let rec loop engine =
  printf "> %!";
  match In_channel.input_line In_channel.stdin with
  | None -> ()
  | Some line ->
    let parts =
      String.strip line |> String.split ~on:' ' |> List.filter ~f:(Fn.non String.is_empty)
    in
    (match parts with
     | [] -> loop engine
     | [ "QUIT" ] -> print_endline "Goodbye."
     | [ "HELP" ] ->
       print_help ();
       loop engine
     | [ "BOOK" ] ->
       print_book engine;
       loop engine
     | [ "CANCEL"; id ] ->
       let engine = cancel_order engine id in
       loop engine
     | [ side; id; price; quantity ]
       when String.equal side "BUY" || String.equal side "SELL" ->
       (match submit_order engine side id price quantity with
        | Ok engine -> loop engine
        | Error error ->
          printf "ERROR %s\n" (Error.to_string_hum error);
          loop engine)
     | _ ->
       print_endline "ERROR invalid command";
       print_help ();
       loop engine)
;;

let () =
  print_endline "OCaml Matching Engine";
  print_help ();
  loop Engine.empty
;;
