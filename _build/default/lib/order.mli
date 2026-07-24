open Core

module Side : sig
  type t =
    | Buy
    | Sell
  [@@deriving compare, equal, sexp]

  val opposite : t -> t
end

type t [@@deriving equal, sexp]

val create
  :  id:Id.t
  -> side:Side.t
  -> price:Price.t
  -> quantity:int
  -> sequence:int
  -> t

val id : t -> Id.t
val side : t -> Side.t
val price : t -> Price.t
val quantity : t -> int
val sequence : t -> int

val with_quantity : t -> int -> t