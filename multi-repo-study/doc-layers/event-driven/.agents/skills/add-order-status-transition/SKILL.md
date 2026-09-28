---
name: add-order-status-transition
description: Add a new Order.SetXStatus()-style method to the Order aggregate — the guard-condition convention, and the two genuinely different failure behaviors existing transitions use (silent no-op vs. thrown exception). Use this whenever the change involves the Order state machine itself, not just a command that calls into it.
---

# Add an Order status transition

All status changes live as methods on `Order`
(`src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs`), never set from
outside via a public setter — `OrderStatus` has a `private set`. Read the existing
six methods (`SetAwaitingValidationStatus`, `SetStockConfirmedStatus`,
`SetPaidStatus`, `SetShippedStatus`, `SetCancelledStatus`,
`SetCancelledStatusWhenStockIsRejected`) before writing a new one — they are not all
guarded the same way, and picking the wrong style silently changes your feature's
failure behavior:

- **Silent no-op style** (`SetAwaitingValidationStatus`, `SetStockConfirmedStatus`,
  `SetPaidStatus`): the method checks `if (OrderStatus == <expected prior state>)`
  and does nothing at all — no exception, no domain event, no state change — if the
  order isn't in that state. A caller that doesn't check the order's status
  afterward will not know the transition was skipped.
- **Throwing style** (`SetShippedStatus`, `SetCancelledStatus`): checks the
  *disallowed* prior states and calls `StatusChangeException(newStatus)`, which
  throws `OrderingDomainException` with a message naming both states, if the order
  is in one of them.

Pick whichever matches how the rest of the codebase treats that transition's
callers — if the calling command handler already treats a `false`/no-op return as
valid ("nothing to do"), the silent style is consistent; if callers need to know a
transition was rejected, use the throwing style so the command handler can catch
`OrderingDomainException` and surface it.

Within the method body, if the transition should raise a domain event (most do, to
trigger downstream integration-event publishing — see the `add-domain-event-handler`
skill), call `AddDomainEvent(new YourDomainEvent(...))` from
`src/Ordering.Domain/Events/` *before* changing `OrderStatus`, matching the existing
methods' ordering. Update `Description` only if an existing transition in the same
family does.

Test in `tests/Ordering.UnitTests/Domain/OrderAggregateTest.cs` — construct an
`Order` via the existing `Builders.cs` helper or the public constructor, drive it to
the prior state with the real methods (don't reflection-hack the private setter),
call your new method, and assert both the resulting `OrderStatus` and (if
applicable) that the expected domain event was added — `Order` inherits an
`Entity.DomainEvents` collection you can inspect directly in a unit test.
