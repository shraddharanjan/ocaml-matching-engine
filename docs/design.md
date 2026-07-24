# Matching Engine Design

## Overview

This project implements a deterministic limit-order-book matching engine in OCaml.

The engine supports:

- limit buy and sell orders
- price-time priority
- full and partial fills
- matching across multiple resting orders
- order cancellation
- exact integer price representation
- deterministic order and trade sequencing
- immutable state transitions

The matching engine is designed as a pure core.

Each operation receives an existing engine state and returns:

```text
new engine state + generated trades
```

The core library does not read from the terminal, print output, open network connections, or write to files. Those responsibilities belong to adapters such as the command-line interface.

## Goals

The primary goals are:

1. Correctness
2. Deterministic behaviour
3. Clear domain modelling
4. Testability
5. Explicit design trade-offs
6. Reasonable in-memory performance

The project is not intended to claim production-exchange performance or reliability.

## Matching model

### Limit orders

A limit buy order specifies the maximum price the buyer is willing to pay.

A limit sell order specifies the minimum price the seller is willing to accept.

An order contains:

```text
ID
side
limit price
remaining quantity
arrival sequence
```

### Best bid

The best bid is the highest active buy price.

For example:

```text
Buy A: £99
Buy B: £101
Buy C: £100
```

The best bid is £101.

A seller would prefer to trade with the buyer offering the most money.

### Best ask

The best ask is the lowest active sell price.

For example:

```text
Sell A: £103
Sell B: £101
Sell C: £102
```

The best ask is £101.

A buyer would prefer to trade with the seller asking for the least money.

### Price priority

Better prices match before worse prices.

For an incoming buy order, the lowest available sell price matches first.

For an incoming sell order, the highest available buy price matches first.

Price priority is considered before arrival time.

For example:

```text
sell-expensive arrives at £101
sell-cheap arrives later at £100
```

An incoming buyer willing to pay £101 matches `sell-cheap` first because £100 is the better selling price.

### Time priority

When several orders have the same price, they match in FIFO order.

For example:

```text
1. sell-1 arrives at £100
2. sell-2 arrives at £100
3. sell-3 arrives at £100
```

The matching order is:

```text
sell-1
sell-2
sell-3
```

### Crossing conditions

An incoming buy crosses when:

```text
incoming buy limit >= best ask
```

An incoming sell crosses when:

```text
incoming sell limit <= best bid
```

When the prices do not cross, the incoming order rests in the book.

### Execution price

A trade executes at the resting order's price.

Example:

```text
Resting sell: £100
Incoming buy limit: £105
```

The trade executes at £100.

The incoming limit is the maximum acceptable price, not necessarily the price that must be paid.

### Full fills

Suppose:

```text
Resting sell quantity: 10
Incoming buy quantity: 10
```

The trade quantity is 10.

Both orders are completely filled and neither remains in the book.

### Partial fills

Suppose:

```text
Resting sell quantity: 100
Incoming buy quantity: 40
```

The trade quantity is 40.

The remaining resting quantity is:

```text
100 - 40 = 60
```

The buy is fully filled and disappears. The sell remains with quantity 60.

### Multi-order fills

An incoming order may consume several resting orders.

Example:

```text
sell-1: 10 units at £100
sell-2: 20 units at £101
sell-3: 50 units at £102

incoming buy: 25 units with limit £101
```

The engine produces:

```text
Trade 10 with sell-1 at £100
Trade 15 with sell-2 at £101
```

Five units of `sell-2` remain.

The engine stops before `sell-3` because £102 exceeds the incoming buy limit.

## Price representation

### Requirement

Prices must compare exactly and deterministically.

### Options considered

- floating-point values
- integer ticks
- a decimal or rational-number library

### Decision

Use integer ticks.

The current implementation defines:

```text
1 tick = £0.01
```

Therefore:

```text
£100.50 = 10,050 ticks
```

### Rationale

Binary floating-point values cannot represent many decimal fractions exactly.

Approximation is usually acceptable for scientific calculation, but a matching engine repeatedly relies on exact ordering and crossing decisions.

Integer ticks provide:

- exact equality
- exact ordering
- deterministic comparisons
- straightforward formatting

### Consequences

The tick size is currently fixed.

A production design would likely associate tick-size metadata with each instrument.

### Revisit when

- supporting instruments with different tick sizes
- supporting sub-penny prices
- supporting currencies with different decimal conventions

## Order IDs

### Requirement

Active orders need unique identifiers for matching, cancellation, logging, and tests.

### Decision

Use an abstract `Id.t` type.

Internally:

```ocaml
type t = string
```

Externally, callers use:

```ocaml
Id.of_string
Id.to_string
```

### Rationale

Using a distinct type prevents an arbitrary string from being accidentally passed where an order ID is expected.

It also centralises validation.

The current implementation rejects empty IDs.

### Consequences

The current validation still permits spaces and punctuation.

A stricter future implementation might permit only letters, digits, hyphens, and underscores.

## Order representation

The main order type is abstract outside the `Order` module.

Conceptually, it contains:

```ocaml
type t =
  { id : Id.t
  ; side : Side.t
  ; price : Price.t
  ; quantity : int
  ; sequence : int
  }
```

Other modules use accessors:

```ocaml
Order.id
Order.side
Order.price
Order.quantity
Order.sequence
```

### Rationale

An abstract type prevents other modules from constructing invalid orders directly or depending on the internal record representation.

The `Order.create` function validates that quantity is positive.

### Possible improvement

Introduce a dedicated abstract `Quantity.t` type so non-positive quantities cannot be represented after validation.

## Sequence numbers

### Requirement

Orders at the same price need an unambiguous arrival order.

### Options considered

- wall-clock timestamps
- monotonic sequence numbers
- both timestamps and sequence numbers

### Decision

Use monotonic sequence numbers for priority.

### Rationale

Sequence numbers provide:

- a total order
- deterministic replay
- no timestamp collisions
- independence from clock resolution
- simpler tests

Wall-clock timestamps could still be stored separately for audit and observability.

### Consequences

Sequence numbers are assigned by the engine and therefore assume commands are processed sequentially within one order book.

## Order-book representation

The order book contains:

```ocaml
type t =
  { bids : Price_level.t Price.Map.t
  ; asks : Price_level.t Price.Map.t
  ; order_index : (Order.Side.t * Price.t) Id.Map.t
  }
```

## Bid and ask maps

### Requirement

The engine needs to:

- insert a price level
- remove an empty price level
- find the highest bid
- find the lowest ask
- support sparse prices

### Options considered

- balanced ordered maps
- arrays indexed by price
- heaps
- custom trees

### Decision

Use `Price.Map`.

### Rationale

Ordered maps:

- support arbitrary sparse prices
- do not require a fixed range
- preserve price ordering
- support minimum and maximum price queries
- provide logarithmic insertion and removal

### Array alternative

A price-indexed array might offer fast direct access and good memory locality when the price range is narrow and known.

However, it would:

- require explicit price bounds
- waste memory for sparse ranges
- require scanning or another index to find the next occupied price

### Heap alternative

A heap can efficiently expose one best element, but arbitrary cancellation and ordered book traversal are less natural.

### Consequences

Map operations allocate new persistent map nodes because the current implementation is immutable.

## Price-level representation

### Requirement

At one price, orders must:

- preserve FIFO priority
- append new orders
- inspect the oldest order
- remove the oldest order
- update a partially filled oldest order
- remove an arbitrary cancelled order

### Initial implementation

The initial version used:

```ocaml
type t = Order.t list
```

and added an order with:

```ocaml
level @ [ order ]
```

This was simple but required `O(L)` time to append to a level containing `L` orders.

### Current implementation

The current version uses a persistent two-list queue:

```ocaml
type t =
  { front : Order.t list
  ; back : Order.t list
  }
```

New orders are added with:

```ocaml
order :: level.back
```

When `front` is empty, `back` is reversed and moved to `front`.

### Complexity

```text
append: amortised O(1)
peek: amortised O(1)
remove front: amortised O(1)
```

Each order moves from `back` to `front` at most once, so the occasional reversal is amortised across prior insertions.

### Arbitrary cancellation

Removing an arbitrary order still requires scanning one price level.

Its complexity is:

```text
O(L)
```

where `L` is the number of orders at that price.

### Alternative considered

A mutable doubly linked list combined with direct node references could provide constant-time removal after locating the order.

That design would introduce:

- mutation
- pointer management
- aliasing concerns
- more complicated snapshots
- more complicated persistent-state semantics

### Revisit when

Cancellation-heavy benchmarks show that scanning one price level is a material bottleneck.

## Order index

### Requirement

Cancellation by ID should not require scanning the entire order book.

### Decision

Maintain:

```ocaml
order_index : (Order.Side.t * Price.t) Id.Map.t
```

### Rationale

The index identifies the side and price level containing an active order.

Without the index, cancellation could require scanning all bids, asks, and orders.

### Current complexity

Locating the relevant price level is logarithmic in the number of active IDs.

Removing the order within the level remains linear in that level's length.

### Invariant

Every active order must appear exactly once in the index.

Every index entry must correspond to an order in the identified price level.

## Immutable state

### Decision

The core engine is immutable.

Its state resembles:

```ocaml
type t =
  { book : Order_book.t
  ; next_order_sequence : int
  ; next_trade_sequence : int
  }
```

An operation behaves conceptually as:

```text
old engine + command -> new engine + events
```

### Benefits

- deterministic state transitions
- easier testing
- simple rollback through retained values
- easier future command replay
- no hidden mutation
- clear ownership
- simpler reasoning about invariants

### Costs

- allocation of persistent maps and records
- potentially lower throughput than specialised mutable structures
- more garbage-collection pressure

### Alternative

A mutable implementation could update the book in place and potentially reduce allocation.

A useful future extension would place immutable and mutable implementations behind equivalent interfaces and compare them with the same unit tests and benchmarks.

## Updating the best order

After a match, the best resting order is either:

- fully filled and removed
- partially filled and replaced with a reduced quantity

The order-book operation accepts:

```ocaml
replacement : Order.t option
```

The meanings are:

```text
None
    remove the best order

Some updated_order
    replace the best order without changing its queue position
```

This operation also updates the order index and removes empty price levels.

## Preserving priority after partial fills

A partially filled resting order does not lose its original time priority.

Suppose:

```text
sell-1 arrives first at £100
sell-2 arrives second at £100
```

After `sell-1` is partially filled, the queue must remain:

```text
sell-1 remaining quantity
sell-2 original quantity
```

Removing and re-adding `sell-1` would incorrectly move it behind `sell-2`.

The implementation therefore updates the first order in place within the immutable queue representation.

## Error handling

Expected user-facing errors are represented as data:

```ocaml
type error =
  | Duplicate_order_id of Id.t
  | Unknown_order_id of Id.t
  | Invalid_quantity of int
```

Operations return `Result`:

```ocaml
(t * Trade.t list, error) Result.t
```

or:

```ocaml
(t * Order.t, error) Result.t
```

### Rationale

Duplicate IDs, unknown cancellations, and invalid quantities are expected domain failures rather than unexpected program crashes.

### Exceptions

Exceptions remain appropriate for violated internal assumptions, such as attempting to remove the first order from an empty level when the program's invariants say the level must be non-empty.

## Trade representation

A trade contains:

```text
buy order ID
sell order ID
execution price
quantity
trade sequence
```

The execution quantity is:

```text
min(incoming remaining quantity, resting remaining quantity)
```

Each executed unit consumes one unit from both participating orders.

## Quantity conservation

For one crossing pair of orders:

```text
submitted quantity
=
2 × executed quantity
+ remaining resting quantity
```

Example:

```text
Resting quantity: 100
Incoming quantity: 40
Executed quantity: 40
Remaining quantity: 60

100 + 40 = 2 × 40 + 60
140 = 140
```

The factor of two exists because each traded unit consumes one unit from the buy order and one from the sell order.

## Testing strategy

The project uses both example-based and property-based testing.

## Unit tests

Alcotest unit tests cover explicit scenarios.

Examples include:

- exact full match
- partial fill
- FIFO at the same price
- better price before worse price
- one incoming order matching multiple levels
- non-crossing orders resting
- duplicate ID rejection
- successful cancellation
- unknown cancellation
- cancellation preserving remaining order priority
- zero quantity rejection
- negative quantity rejection

### Benefits

Unit tests:

- clearly document specific expected behaviour
- are easy to understand when they fail
- protect known edge cases
- serve as executable examples

## Property-based tests

QCheck generates many inputs and verifies general properties.

Current properties include:

- `Price.of_ticks` and `Price.to_ticks` round-trip
- `Id.of_string` and `Id.to_string` round-trip
- one valid order rests in an empty book
- non-crossing orders do not trade
- guaranteed crossing orders produce a trade
- trades use the resting price
- matching conserves quantity
- equal crossing quantities leave zero resting orders
- unequal crossing quantities leave one resting order
- a resting order can be cancelled
- active duplicate IDs are rejected
- non-positive quantities are rejected
- identical command sequences produce identical results

### Benefits

Property tests explore far more input combinations than manually selected examples.

They are particularly valuable for systems with invariants and interacting state transitions.

## Determinism

The same initial engine and command sequence should always produce:

- the same final book
- the same trades
- the same order sequence numbers
- the same trade sequence numbers

Determinism is valuable for:

- tests
- incident reproduction
- event replay
- debugging
- comparing alternative implementations

## Benchmarking

Core_bench measures:

- submitting one resting order
- a full match against one resting order
- a partial match against one resting order
- adding 1,000 orders at one price
- sweeping 1,000 resting orders

Current measured results:

| Benchmark | Time per run |
|---|---:|
| Submit one resting order | 58.48 ns |
| Full match against one resting order | 127.34 ns |
| Partial match against one resting order | 134.86 ns |
| Add 1,000 orders at one price | 966.61 µs |
| Sweep 1,000 resting orders | 350.94 µs |

These are synthetic microbenchmarks for the in-memory engine.

They exclude parsing, networking, persistence, and logging.

The results are useful for comparing implementation changes, not for claiming production exchange throughput.

## Complexity

Let:

```text
P = occupied price levels
N = active orders
L = orders at one selected price
T = trades generated by one incoming order
```

| Operation | Current complexity |
|---|---:|
| Find best bid | `O(log P)` |
| Find best ask | `O(log P)` |
| Add a new price level | `O(log P)` |
| Add to an existing price-level queue | amortised `O(1)` queue work plus map update |
| Remove best order | amortised `O(1)` queue work plus map update |
| Locate cancellation level | `O(log N)` |
| Remove arbitrary order from a level | `O(L)` |
| Match across resting orders | depends on `T` and associated map updates |

The exact constants and allocation behaviour are also important and are measured separately using Core_bench.

## Concurrency

### Current decision

Each order book is processed sequentially.

### Rationale

Matching requires a total order of commands to preserve deterministic price-time priority.

Allowing concurrent mutation of one book would introduce:

- ordering races
- lock contention
- complicated cancellation behaviour
- nondeterministic outcomes
- more difficult testing

### Scaling approach

Parallelism can be introduced by partitioning independent instruments:

```text
AAPL commands -> AAPL engine
MSFT commands -> MSFT engine
GOOG commands -> GOOG engine
```

Each individual book remains single-threaded and deterministic, while different books can run concurrently.

## CLI boundary

The command-line interface handles:

- reading text
- splitting commands
- parsing prices and quantities
- displaying accepted orders
- displaying trades
- displaying errors
- displaying the best bid and ask

The engine itself remains independent of terminal input and output.

This separation makes it possible to add other adapters later, such as:

- a TCP server
- a replay tool
- a graphical interface
- a test harness

without changing the core matching logic.

## Current limitations

The present implementation has intentional limitations:

- one order book
- no symbol or instrument type
- limit orders only
- fixed penny tick size
- no persistence
- no event log
- no snapshots
- no networking
- no participant identity
- no self-trade prevention
- no authentication
- arbitrary cancellation is linear within one price level
- immutable updates allocate persistent data structures

## Future work

### Multiple instruments

Introduce:

```ocaml
Symbol.t
```

and maintain:

```ocaml
Order_book.t Symbol.Map.t
```

### Additional order types

Possible additions:

- market orders
- immediate-or-cancel
- fill-or-kill
- post-only
- modify or replace

Variants should model valid combinations explicitly.

### Event logging

Represent external inputs as commands:

```ocaml
type command =
  | Submit_limit of ...
  | Cancel of Id.t
```

Append accepted commands to a log.

### Deterministic replay

Reconstruct engine state by folding a command list from `Engine.empty`.

The replayed final state and trade stream should equal the original results.

### Snapshots

Periodically store a serialised engine state so restart does not require replaying the full history.

### Networking

Add an Async TCP adapter that:

- accepts client connections
- parses commands
- calls the pure engine
- returns acknowledgements and trades

### Mutable implementation

Build a mutable version behind a similar interface and compare:

- latency
- throughput
- allocation
- implementation complexity
- testability

### Faster cancellation

Use a mutable linked price level and direct node references from the ID index.

This could reduce arbitrary removal after lookup from `O(L)` to `O(1)`, at the cost of greater implementation complexity.

## Summary of design decisions

| Area | Decision |
|---|---|
| Price representation | Integer ticks |
| Order priority | Price, then monotonic sequence |
| Execution price | Resting order's price |
| Engine state | Immutable |
| Bid/ask storage | Ordered `Price.Map` |
| Price level | Persistent two-list FIFO queue |
| Cancellation lookup | `Id.Map` index |
| Expected errors | `Result` |
| Core processing | Single-threaded per book |
| Testing | Unit tests plus QCheck properties |
| Benchmarking | Core_bench microbenchmarks |

The implementation prioritises correctness, deterministic behaviour, and clarity while documenting where a production-oriented design might make different performance trade-offs.