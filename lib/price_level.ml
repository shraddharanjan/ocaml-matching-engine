open Core

type t = Order.t list [@@deriving sexp]

let empty = []
let is_empty = List.is_empty
let add level order = level @ [ order ]
let peek = List.hd
let remove_first = List.tl_exn

let update_first level order =
  match level with
  | [] -> invalid_arg "Cannot update an empty price level"
  | _ :: rest -> order :: rest
;;

let remove_order level id =
  let rec loop reversed = function
    | [] -> List.rev reversed, None
    | order :: rest ->
      if Id.equal (Order.id order) id
      then List.rev_append reversed rest, Some order
      else loop (order :: reversed) rest
  in
  loop [] level
;;

let orders level = level
let total_quantity level = List.sum (module Int) level ~f:Order.quantity
