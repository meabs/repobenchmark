---
name: add-domain-event-handler
description: React to an existing Order domain event (MediatR INotificationHandler), and understand how domain events differ from integration events in this codebase. Use when the task is "when X happens to an order, also do Y" rather than changing the Order state machine itself.
---

# Add a domain event handler

Domain events (`src/Ordering.Domain/Events/*.cs`, e.g. `OrderShippedDomainEvent`,
`OrderStatusChangedToPaidDomainEvent`) are raised by `Order` aggregate methods via
`AddDomainEvent(...)` (see `add-order-status-transition`) and are **in-process
MediatR notifications**, dispatched when the EF Core `SaveChanges` pipeline commits
— not messages on the event bus. Don't confuse them with **integration events**
(`src/Ordering.API/Application/IntegrationEvents/Events/*.cs`), which *are*
published to the message broker for other services (Basket, Catalog webhooks) to
consume; a domain event handler in
`src/Ordering.API/Application/DomainEventHandlers/` is frequently the thing that
translates a domain event into an integration event publish — see
`OrderStatusChangedToPaidDomainEventHandler` as the pattern for that translation.

1. Create `YourDomainEventHandler.cs` in
   `src/Ordering.API/Application/DomainEventHandlers/`:
   `public class YourDomainEventHandler : INotificationHandler<YourDomainEvent>`
   with a `Task Handle(YourDomainEvent notification, CancellationToken ct)` method.
2. Handlers are picked up by MediatR's assembly scan automatically — no manual
   registration, same as command handlers.
3. If your handler needs to look something up, inject the relevant repository
   (`IOrderRepository`, `IBuyerRepository`) — don't reach into `DbContext` directly,
   matching every existing handler in that folder.
4. If the point of the handler is to notify another service, construct and publish
   the matching integration event via `IOrderingIntegrationEventService`
   (`AddAndSaveEventAsync`) rather than hand-rolling a broker call — that's the
   consistent pattern across every existing handler that crosses the domain/
   integration boundary.

Test by constructing the handler directly with NSubstitute mocks for its
dependencies (same style as `tests/Ordering.UnitTests/Application/*Test.cs`),
calling `Handle` with a real instance of the domain event record, and asserting on
what the mocks were called with.

Verify with `dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj` — see
`verify-work`.
