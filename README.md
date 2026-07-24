# OCaml Matching Engine

A deterministic limit-order-book matching engine written in OCaml using Jane Street's Core libraries.

The project implements price-time priority, exact integer pricing, full and partial fills, multi-order matching, cancellation, property-based testing, an interactive command-line interface, and reproducible microbenchmarks.

## Features

- Limit buy and sell orders
- Highest-bid and lowest-ask matching
- Price priority across different price levels
- FIFO priority for orders at the same price
- Full and partial fills
- One incoming order matching multiple resting orders
- Execution at the resting order's price
- Cancellation by order ID
- Duplicate order ID rejection
- Exact integer tick prices
- Immutable engine state
- Alcotest unit tests
- QCheck property-based tests
- Core_bench performance benchmarks
- Interactive command-line interface

## Example

Start the CLI:

```bash
dune exec matching-engine
```

Example session:

```text
OCaml Matching Engine
Commands:
  BUY <id> <price> <quantity>
  SELL <id> <price> <quantity>
  CANCEL <id>
  BOOK
  HELP
  QUIT

> SELL sell-1 100.00 10
ACCEPTED sell-1

> BOOK
BEST BID: none
BEST ASK: 100.00 quantity=10 id=sell-1

> BUY buy-1 101.00 5
ACCEPTED buy-1
TRADE buyer=buy-1 seller=sell-1 price=100.00 quantity=5

> BOOK
BEST BID: none
BEST ASK: 100.00 quantity=5 id=sell-1

> CANCEL sell-1
CANCELLED sell-1 remaining=5

> BOOK
BEST BID: none
BEST ASK: none

> QUIT
Goodbye.
```

## Matching rules

The engine uses price-time priority.

### Best bid

The best bid is the highest active buy price.

A buyer offering £101 has priority over a buyer offering £100.

### Best ask

The best ask is the lowest active sell price.

A seller asking £100 has priority over a seller asking £101.

### Price priority

Orders at better prices match before orders at worse prices.

For example, an incoming buy order will match a sell order at £100 before a sell order at £101.

### Time priority

Orders at the same price are matched in FIFO order.

An order that arrived earlier is matched before a later order at the same price.

### Crossing prices

An incoming buy order crosses the order book when:

```text
incoming buy limit >= best ask
```

An incoming sell order crosses the order book when:

```text
incoming sell limit <= best bid
```

### Execution price

Trades execute at the resting order's price.

For example, suppose a sell order is already resting at £100 and an incoming buyer submits a limit of £101. The trade executes at £100.

### Partial fills

A partially filled resting order retains its original queue position.

For example:

```text
Before:
sell-1 quantity=100
sell-2 quantity=50

After sell-1 trades 40:
sell-1 quantity=60
sell-2 quantity=50
```

`sell-1` remains ahead of `sell-2` because it arrived first.

## Architecture

```text
CLI command
    |
    v
Parsing and validation
    |
    v
Engine
    |
    v
Order book
    |-- bids: price -> FIFO price level
    |-- asks: price -> FIFO price level
    `-- order index: order ID -> side and price
    |
    v
Trades and updated engine state
```

The core engine does not perform input or output. The CLI is an adapter that parses user commands, calls the engine, and displays the resulting trades or errors.

## Project structure

```text
matching_engine/
├── bin/
│   ├── dune
│   └── main.ml
├── lib/
│   ├── dune
│   ├── id.ml
│   ├── id.mli
│   ├── price.ml
│   ├── price.mli
│   ├── order.ml
│   ├── order.mli
│   ├── trade.ml
│   ├── trade.mli
│   ├── price_level.ml
│   ├── price_level.mli
│   ├── order_book.ml
│   ├── order_book.mli
│   ├── engine.ml
│   └── engine.mli
├── test/
│   ├── dune
│   ├── test_order_book.ml
│   └── test_properties.ml
├── bench/
│   ├── dune
│   └── bench_engine.ml
├── docs/
│   └── design.md
├── dune-project
├── matching_engine.opam
├── .ocamlformat
├── .gitignore
├── LICENSE
└── README.md
```

## Domain types

The engine uses modules to give domain values distinct types.

### Order IDs

Order IDs use:

```ocaml
Id.t
```

Although an ID is represented internally as a string, other modules cannot treat arbitrary strings as IDs. They must use:

```ocaml
Id.of_string "order-1"
```

and convert back for display with:

```ocaml
Id.to_string id
```

### Prices

Prices use:

```ocaml
Price.t
```

Prices are represented as integer ticks rather than floating-point numbers.

The current implementation uses:

```text
1 tick = £0.01
```

For example:

```text
£100.50 = 10,050 ticks
```

This gives exact and deterministic price comparisons.

Using a floating-point representation could introduce imprecision when testing equality or deciding whether two prices cross.

### Orders

An order contains:

```text
order ID
side
limit price
remaining quantity
arrival sequence
```

`Order.t` is abstract. Other modules use accessors such as:

```ocaml
Order.id order
Order.side order
Order.price order
Order.quantity order
Order.sequence order
```

This prevents other modules from depending directly on the record representation.

## Data structures

The order book contains:

```ocaml
type t =
  { bids : Price_level.t Price.Map.t
  ; asks : Price_level.t Price.Map.t
  ; order_index : (Order.Side.t * Price.t) Id.Map.t
  }
```

### Bid and ask maps

The bid and ask maps associate occupied prices with their price levels:

```text
Price.Map
    price -> price level
```

The bid map allows the engine to find the highest active buy price.

The ask map allows the engine to find the lowest active sell price.

Ordered maps were selected because prices can be sparse and the valid price range is not known in advance.

### Price levels

A price level contains all orders resting at one price.

It is implemented as a persistent two-list FIFO queue:

```ocaml
type t =
  { front : Order.t list
  ; back : Order.t list
  }
```

New orders are inserted into `back`.

When `front` becomes empty, `back` is reversed to restore FIFO ordering.

This provides amortised constant-time insertion and front removal.

### Order index

The order index associates each active order ID with its location:

```text
order ID -> side and price
```

This means cancellation does not need to scan every price level in the book.

After locating the correct price level, removing an arbitrary order from that level is still linear in the number of orders at that price.

## Immutable engine state

The engine is implemented immutably.

Each command receives an engine state and returns a new engine state:

```text
old engine + command -> new engine + trades
```

For example:

```ocaml
let engine = Engine.empty in

let engine, _ =
  Engine.submit_limit_order engine ...
  |> get_ok
in

let engine, trades =
  Engine.submit_limit_order engine ...
  |> get_ok
in
...
```

The original engine value is not modified.

Benefits include:

- deterministic behaviour
- easier testing
- easier reasoning about state transitions
- no hidden mutation
- support for future event replay

The trade-off is greater allocation than a specialised mutable implementation.

## Error handling

Expected domain errors use the `Engine.error` type:

```ocaml
type error =
  | Duplicate_order_id of Id.t
  | Unknown_order_id of Id.t
  | Invalid_quantity of int
```

Engine operations return `Result` values:

```ocaml
Ok result
```

or:

```ocaml
Error reason
```

Expected user errors therefore do not crash the program.

## Testing

Run all tests:

```bash
dune runtest
```

### Unit tests

The Alcotest unit suite covers explicit scenarios including:

- full fills
- partial fills
- FIFO priority
- better-price priority
- one incoming order matching multiple resting orders
- non-crossing orders resting
- duplicate order ID rejection
- successful cancellation
- unknown cancellation
- cancellation preserving queue order
- zero quantity rejection
- negative quantity rejection

### Property-based tests

The QCheck suite generates many inputs and checks broader properties including:

- price values round-trip through `Price.of_ticks` and `Price.to_ticks`
- IDs round-trip through `Id.of_string` and `Id.to_string`
- a single valid order rests in an empty book
- non-crossing orders do not trade
- guaranteed crossing orders produce trades
- crossing orders execute at the resting price
- matching conserves quantity
- cancellation returns the correct order
- active duplicate IDs are rejected
- non-positive quantities are rejected
- repeating the same command sequence produces the same result

Unit tests provide clear examples of expected behaviour. Property tests search a broader input space for unexpected edge cases.

## Benchmarks

Run the benchmarks with:

```bash
dune exec bench/bench_engine.exe -- -quota 10s
```

Current local Core_bench results:

| Benchmark | Time per run | Minor allocation |
|---|---:|---:|
| Submit one resting order | 58.48 ns | 59 words |
| Full match against one resting order | 127.34 ns | 91 words |
| Partial match against one resting order | 134.86 ns | 108 words |
| Add 1,000 orders at one price | 966.61 µs | 206,911 words |
| Sweep 1,000 resting orders | 350.94 µs | 133,056 words |

These are synthetic, in-memory microbenchmarks.

They exclude:

- command parsing
- networking
- persistence
- logging
- operating-system scheduling
- multiple instruments

They should not be interpreted as end-to-end exchange throughput.

### Benchmark environment

```text
CPU: 12th Gen Intel(R) Core(TM) i5-1235U
Operating system: Linux under WSL
OCaml: version 5.4.0
Dune: 3.24.1
```

## Complexity

Let:

```text
P = number of occupied price levels
N = number of active orders
L = number of orders at a selected price
```

| Operation | Current complexity |
|---|---:|
| Find best bid or ask | `O(log P)` |
| Insert a new price level | `O(log P)` |
| Append at an existing price level | amortised `O(1)` queue work plus map update |
| Remove the best order | amortised `O(1)` queue work plus map update |
| Locate an order's cancellation level | `O(log N)` |
| Remove an arbitrary order within one level | `O(L)` |

## Installation

Create or enter an opam environment and install dependencies:

```bash
opam install . --deps-only --with-test
```

Alternatively, install the principal packages directly:

```bash
opam install dune core core_unix core_bench alcotest qcheck \
  qcheck-alcotest ppx_jane ocamlformat
```

## Build

```bash
dune build
```

## Run tests

```bash
dune runtest
```

## Run the CLI

```bash
dune exec matching-engine
```

## Run benchmarks

Development smoke test:

```bash
dune exec bench/bench_engine.exe -- -quota 1s
```

Longer benchmark:

```bash
dune exec bench/bench_engine.exe -- -quota 10s
```

## Formatting

The project uses the Jane Street `ocamlformat` profile.

Format the project with:

```bash
dune fmt
```

If Dune reports changes that require promotion:

```bash
dune promote
```

## Design documentation

See [`docs/design.md`](docs/design.md) for detailed discussion of:

- integer ticks versus floating-point prices
- immutable versus mutable state
- ordered maps versus alternative structures
- FIFO queue representation
- cancellation indexing
- sequence numbers versus timestamps
- resting-price execution
- testing strategy
- concurrency
- complexity and future optimisation

## Current limitations

- One order book rather than multiple instruments
- Limit orders only
- Fixed penny tick size
- No persistence or command replay
- No snapshots
- No networking
- No user or participant identifiers
- Arbitrary cancellation remains linear within one price level
- Benchmarks cover only the in-memory engine

## Future work

Possible extensions include:

- multiple symbols
- market orders
- immediate-or-cancel orders
- fill-or-kill orders
- post-only orders
- order modification
- participant IDs and self-trade prevention
- append-only event logging
- deterministic replay
- snapshots
- an Async TCP interface
- instrument-specific tick sizes
- a mutable low-allocation implementation
- direct node references for faster cancellation
