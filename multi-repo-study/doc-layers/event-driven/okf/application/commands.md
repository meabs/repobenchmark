---
type: concept
title: Commands, handlers, and the idempotency wrapper
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:45:00Z
sources:
  - src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs
  - src/Ordering.API/Application/Commands/CancelOrderCommandHandler.cs
  - src/Ordering.API/Application/Behaviors/
---

# Commands, handlers, and the idempotency wrapper

Each mutating operation is a `record : IRequest<TResult>` plus a
`IRequestHandler<TCommand, TResult>` — see `.agents/skills/add-order-command/` for
the concrete steps. This doc covers the two things wrapped around every command.

## Pipeline behaviors (`Behaviors/`)

Every command sent through `IMediator.Send` passes through, in registration order:
`LoggingBehavior` (logs the command and its result), `ValidatorBehavior` (runs any
registered FluentValidation validator for the command type — on failure throws
`OrderingDomainException` wrapping a `ValidationException` as its `InnerException`,
not a bare `ValidationException`, short-circuiting the handler), `TransactionBehavior`
(wraps the handler call plus `DbContext.SaveChangesAsync` in a transaction, and
publishes any integration events queued via `IOrderingIntegrationEventService`
*after* the transaction commits).

## The `IdentifiedCommand<T, R>` wrapper

`CreateOrderCommand`, `CancelOrderCommand`, `ShipOrderCommand` are all sent from the
API wrapped in `IdentifiedCommand<T, R>(command, requestId)`, where `requestId`
comes from an `x-requestid` header the client supplies — the client, not the
server, decides what counts as "the same request retried." `IdentifiedCommandHandler<T,R>.Handle`
(see `.agents/skills/add-order-command/`) checks
`IRequestManager.ExistAsync(requestId)`: if that ID was already processed, it
returns `CreateResultForDuplicateRequest()` (each concrete `*IdentifiedCommandHandler`
subclass defines this — `CancelOrderIdentifiedCommandHandler` returns `true`,
treating a duplicate cancel as a successful no-op) **without re-running the inner
command at all**. If it's new, it records the ID, sends the inner command through
`IMediator`, and — this is easy to miss — **swallows any exception the inner
command throws and returns `default(R)`** rather than propagating it. A caller
relying on an exception from a command sent through the identified path will not
see one.
