---
name: add-order-command
description: Add a new CQRS command that mutates an Order — the record/handler/idempotent-wrapper triad, mediator registration, and which existing command to copy as a template. Use this when the task is "add an operation that changes an order," not a pure query.
---

# Add a new Order command

Every existing Order-mutating operation (`CancelOrderCommand`, `ShipOrderCommand`,
`CreateOrderCommand`, `SetPaidOrderStatusCommand`, ...) follows the same three-file
shape under `src/Ordering.API/Application/Commands/`. Copy `CancelOrderCommand.cs` /
`CancelOrderCommandHandler.cs` as your template — it's the simplest complete example.

1. **Command record**: `public record YourCommand(...) : IRequest<TResult>;` — a
   plain record with the data the operation needs (usually at least the order
   number/id). `bool` is the conventional return type for "did it succeed."

2. **Handler**: `public class YourCommandHandler : IRequestHandler<YourCommand, TResult>`.
   Inject `IOrderRepository` (not `DbContext` directly). Load the order with
   `await _orderRepository.GetAsync(orderNumber)`, return the failure value if
   `null`, call the relevant method on the `Order` aggregate (add one via the
   `add-order-status-transition` skill if it doesn't exist yet — **never** mutate
   `Order`'s state from the handler directly, only through an aggregate method),
   then persist with `await _orderRepository.UnitOfWork.SaveEntitiesAsync(cancellationToken)`.

3. **Idempotent wrapper** (only if the command can be triggered by a retryable
   client action, e.g. a button press): add a second class
   `YourIdentifiedCommandHandler : IdentifiedCommandHandler<YourCommand, TResult>`
   in the same file, and add a `case YourCommand yourCommand:` branch to the
   `switch` in `src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs`
   (around line 56) so duplicate-request logging names the right property — this is
   easy to forget since the switch has a silent `default` fallback that still
   "works" but loses the specific log detail.
   **Know this wrapper's actual behavior**: `IdentifiedCommandHandler.Handle`
   catches *any* exception from the inner command and returns `default` — it does
   not rethrow, retry, or log the exception. If your handler needs a caller to see a
   failure, do it through the return value, not an exception, when going through the
   identified path.

4. **Registration**: command/handler pairs in this project are picked up
   automatically by MediatR's assembly scan (see `src/Ordering.API/Extensions/Extensions.cs`)
   — no manual DI registration needed for the handler itself. If you added a
   validator, see the `add-command-validation-rule` skill.

5. Write a test in `tests/Ordering.UnitTests/Application/`, following the pattern in
   `NewOrderCommandHandlerTest.cs`: `NSubstitute.Substitute.For<IOrderRepository>()`,
   stub `GetAsync`/`UnitOfWork.SaveEntitiesAsync` (or `SaveChangesAsync`), construct
   the handler directly (no DI container in these tests), call `Handle`, assert on
   the result and on the repository mock's calls.

Verify with `dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj` — see
`verify-work`.
