open Core

type t =
  { front : Order.t list
  ; back : Order.t list
  }
[@@deriving sexp]

let empty =
  { front = []
  ; back = []
  }
;;

let normalise level =
  match level.front with
  | _ :: _ ->
      level
  | [] ->
      { front = List.rev level.back
      ; back = []
      }
;;

let is_empty level =
  List.is_empty level.front
  && List.is_empty level.back
;;

let add level order =
  { level with back = order :: level.back }
;;

let peek level =
  let level = normalise level in
  List.hd level.front
;;

let remove_first level =
  let level = normalise level in

  match level.front with
  | [] ->
      invalid_arg "Cannot remove from an empty price level"
  | _ :: rest ->
      normalise
        { level with front = rest }
;;

let update_first level order =
  let level = normalise level in

  match level.front with
  | [] ->
      invalid_arg "Cannot update an empty price level"
  | _ :: rest ->
      { level with front = order :: rest }
;;

let orders level =
  let level = normalise level in
  level.front @ List.rev level.back
;;

let remove_order level id =
  let all_orders = orders level in

  let rec loop reversed = function
    | [] ->
        let remaining = List.rev reversed in

        ( { front = remaining
          ; back = []
          }
        , None )
    | order :: rest ->
        if Id.equal (Order.id order) id
        then
          let remaining =
            List.rev_append reversed rest
          in

          ( { front = remaining
            ; back = []
            }
          , Some order )
        else
          loop (order :: reversed) rest
  in

  loop [] all_orders
;;

let total_quantity level =
  List.sum
    (module Int)
    (orders level)
    ~f:Order.quantity
;;