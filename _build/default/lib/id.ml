open Core

module T = struct
  type t = string [@@deriving compare, equal, hash, sexp]
end

include T
include Comparable.Make (T)
include Hashable.Make (T)

let of_string value =
  if String.is_empty value then invalid_arg "Order ID cannot be empty";
  value
;;

let to_string t = t