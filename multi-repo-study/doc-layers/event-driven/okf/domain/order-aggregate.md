---
type: concept
title: Order aggregate
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:41:00Z
sources:
  - src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs
  - src/Ordering.Domain/AggregatesModel/OrderAggregate/OrderItem.cs
  - src/Ordering.Domain/AggregatesModel/OrderAggregate/OrderStatus.cs
---

# Order aggregate

`Order` is the aggregate root; `OrderItem` is a child entity only reachable through
it — `OrderItems` is `IReadOnlyCollection<OrderItem>` backed by a private
`List<OrderItem> _orderItems`, and the only way to add one is
`Order.AddOrderItem(...)`, which either bumps an existing line's units/discount or
constructs a new `OrderItem`. `OrderItem`'s constructor and `AddUnits` both enforce
invariants (`units <= 0` throws, `unitPrice * units < discount` throws) — these run
even when called from inside `AddOrderItem`, so there's no way to get an invalid
line item into an order.

## Status state machine

`OrderStatus` (`OrderStatus.cs`) is a 6-value enum: `Submitted(1) →
AwaitingValidation(2) → StockConfirmed(3) → Paid(4) → Shipped(5)`, with `Cancelled(6)`
reachable from several states. Transitions are one method per target status on
`Order`, and **the guard style is not consistent across them** — this matters if
you're adding a new transition or relying on one:

- `SetAwaitingValidationStatus`, `SetStockConfirmedStatus`, `SetPaidStatus`: each
  checks `if (OrderStatus == <required prior state>)` and, if false, **does
  nothing** — no exception, no state change, no domain event. Calling
  `SetPaidStatus()` on an order that isn't `StockConfirmed` is a silent no-op.
- `SetShippedStatus`, `SetCancelledStatus`: check the *disallowed* states and throw
  `OrderingDomainException` via a shared private `StatusChangeException` helper if
  matched. `SetShippedStatus` throws unless the order is `Paid`.
  `SetCancelledStatus` throws only if the order is already `Paid` or `Shipped`
  (i.e. cancellation is allowed from every other state).
- `SetCancelledStatusWhenStockIsRejected`: a third shape — only acts if
  `AwaitingValidation`, sets `Cancelled` and a descriptive `Description`, but raises
  no domain event (unlike every other transition that changes status).

Each of the exception-raising and event-raising transitions was written for one
specific caller in the Application layer; there's no generic "transition(newStatus)"
method, by design — this keeps every legal transition's side effects (which domain
event, what `Description` text) explicit at the call site.

## `GetTotal()`

`Order.GetTotal()` sums `Units * UnitPrice` across `_orderItems` — it does **not**
subtract `Discount`. Any UI/reporting code that needs a discounted total computes it
separately; this is worth confirming (not assuming) if a task touches pricing.
