---
type: concept-index
title: Application layer (CQRS)
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:44:00Z
sources:
  - src/Ordering.API/Application/Commands/
  - src/Ordering.API/Application/Validations/
  - src/Ordering.API/Application/Behaviors/
  - src/Ordering.API/Apis/OrdersApi.cs
---

# Application layer

Lives inside `src/Ordering.API/Application/` — there is no separate
`Ordering.Application` project; commands, handlers, validators, and domain-event
handlers are all part of the API project. Built on MediatR (`IRequest`/
`IRequestHandler`/`INotificationHandler`) and FluentValidation.

- [commands.md](commands.md) — the command/handler/idempotency-wrapper triad and
  the three MediatR pipeline behaviors every command passes through.

Minimal-API endpoints in `src/Ordering.API/Apis/OrdersApi.cs` are thin: they build a
command (often wrapping it in `IdentifiedCommand` using a client-supplied
`x-requestid` header) and `_mediator.Send(...)` it — business logic isn't in the API
layer.
