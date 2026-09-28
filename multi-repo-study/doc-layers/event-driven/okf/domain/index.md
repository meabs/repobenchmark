---
type: concept-index
title: Domain layer
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:40:00Z
sources:
  - src/Ordering.Domain/AggregatesModel/OrderAggregate/
  - src/Ordering.Domain/AggregatesModel/BuyerAggregate/
  - src/Ordering.Domain/SeedWork/
---

# Domain layer

`src/Ordering.Domain` has no dependency on ASP.NET, EF Core, or MediatR — it's
plain C#. Two aggregate roots:

- [order-aggregate.md](order-aggregate.md) — `Order`, its `OrderItem` collection,
  the status state machine, and its invariants.
- [buyer-aggregate.md](buyer-aggregate.md) — `Buyer` and its `PaymentMethod`
  collection.

Both inherit `Entity` (`SeedWork/Entity.cs`), which supplies identity-based
equality, a `DomainEvents` collection, and `AddDomainEvent`/`ClearDomainEvents`. Both
implement the marker interface `IAggregateRoot` (`SeedWork/IAggregateRoot.cs`),
which has no members — it exists purely so repositories can be constrained to
`where T : IAggregateRoot`, enforcing "only aggregate roots get a repository," a
core DDD rule, at the type level.

`Order.Address` is a value object (`Address.cs`) — EF Core owned-entity mapped, no
identity of its own, equality by value via `SeedWork/ValueObject.cs`.
