open Core

module T = struct
  type t = int [@@deriving compare, equal, sexp]
end

include T
include Comparable.Make (T)

let of_ticks ticks =
  if ticks < 0 then invalid_arg "Price cannot be negative";
  ticks
;;

let to_ticks t = t

let of_string input =
  Or_error.try_with (fun () ->
    match String.split input ~on:'.' with
    | [ pounds ] ->
      let pounds = Int.of_string pounds in
      of_ticks (pounds * 100)
    | [ pounds; pennies ] ->
      let pennies =
        match String.length pennies with
        | 0 -> 0
        | 1 -> Int.of_string pennies * 10
        | 2 -> Int.of_string pennies
        | _ -> failwith "Price must have at most two decimal places"
      in
      of_ticks ((Int.of_string pounds * 100) + pennies)
    | _ -> failwith "Invalid price")
;;

let to_string ticks = sprintf "%d.%02d" (ticks / 100) (ticks % 100)
