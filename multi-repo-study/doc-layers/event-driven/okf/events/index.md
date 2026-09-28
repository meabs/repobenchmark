---
type: concept-index
title: Domain events vs. integration events
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:47:00Z
sources:
  - src/Ordering.Domain/Events/
  - src/Ordering.API/Application/DomainEventHandlers/
  - src/Ordering.API/Application/IntegrationEvents/
---

# Domain events vs. integration events

Two distinct event concepts share this codebase, and the naming (`*DomainEvent` vs.
`*IntegrationEvent`) is the only thing that tells them apart at a glance — both are
plain records, both flow through similar-looking handler classes.

**Domain events** (`src/Ordering.Domain/Events/*.cs`, e.g.
`OrderStatusChangedToPaidDomainEvent`) are raised inside `Order`/`Buyer` aggregate
methods via `AddDomainEvent`, dispatched in-process by MediatR when `SaveChanges`
commits. Their handlers live in
`src/Ordering.API/Application/DomainEventHandlers/*.cs`
(`INotificationHandler<TDomainEvent>`). They never leave the process.

**Integration events** (`src/Ordering.API/Application/IntegrationEvents/Events/*.cs`,
e.g. `OrderStatusChangedToPaidIntegrationEvent`) are published to the message broker
via `IOrderingIntegrationEventService`, for other services (Basket, Catalog,
Webhooks) to consume. Their inbound handlers — for events *other* services publish
that Ordering listens to — live in
`src/Ordering.API/Application/IntegrationEvents/EventHandling/*.cs`
(e.g. `OrderStockConfirmedIntegrationEventHandler`, reacting to something Catalog
published).

The common pattern connecting the two: a domain event fires when `Order`'s in-memory
state changes, its handler in `DomainEventHandlers/` looks up any data it needs
(buyer info, stock items) and constructs the *matching* integration event, then
calls `_orderingIntegrationEventService.AddAndSaveEventAsync(...)` to queue it —
actual publish to the broker happens later, from `TransactionBehavior`, only after
the database transaction that produced the domain event has committed (see
`../application/commands.md`). This ordering (queue during the transaction, publish
after commit) is what prevents another service from reacting to a state change that
then gets rolled back.
