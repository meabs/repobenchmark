---
name: add-command-validation-rule
description: Add or change a FluentValidation rule for an Ordering command — where validators live, how they're wired in, and the one thing that's easy to get wrong (a validator class with no matching registration is silently never run). Use for input/precondition checks that should reject a command before its handler runs.
---

# Add a command validation rule

Validators live in `src/Ordering.API/Application/Validations/`, one class per
command: `AbstractValidator<TCommand>` with `RuleFor(...)` calls in the
constructor. `CancelOrderCommandValidator` is the simplest real example — a single
`RuleFor(order => order.OrderNumber).NotEmpty()`. `CreateOrderCommandValidator` is
the most elaborate (validates card expiration, address fields, etc.) — read it if
your rule is more than a single field check.

1. If a validator for your command doesn't exist yet, create
   `YourCommandValidator.cs` in that folder, matching the constructor-injects-
   `ILogger<T>`-and-logs-at-Trace convention the existing validators use (see
   `CancelOrderCommandValidator`) — cosmetic, but keep it consistent.
2. **Registration is NOT automatic the way command handlers are.** FluentValidation
   validators in this project are picked up via assembly scanning configured in
   `src/Ordering.API/Extensions/Extensions.cs` — confirm your new validator class is
   actually in `src/Ordering.API/Application/Validations/` (not some other folder)
   and is `public`, since that's what the scan relies on. A validator that compiles
   fine but was put in the wrong namespace/folder will simply never run, and no
   error will tell you — the command will just succeed when it shouldn't. Always
   verify with a test (below), not by reading the code.
3. Validation runs through a MediatR pipeline behavior (`ValidatorBehavior` in
   `src/Ordering.API/Application/Behaviors/`) before the command handler executes —
   a failed rule throws `OrderingDomainException` (wrapping the FluentValidation
   `ValidationException` as `InnerException`, not throwing it directly), and the
   handler method body never runs.
4. Test the validator directly (construct it with a stub logger, call `.Validate()`
   or `.TestValidate()` if the FluentValidation.TestHelper package is referenced —
   check `tests/Ordering.UnitTests/Ordering.UnitTests.csproj`'s package references
   first) rather than only testing it indirectly through the handler, so a
   regression in the rule itself fails close to its cause.

Verify with `dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj` — see
`verify-work`.
