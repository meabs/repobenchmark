---
name: verify-work
description: How to actually confirm a change to the Ordering subsystem works, not just that it compiles — which test command to run and what a passing/failing result actually covers.
---

# Verify your work

```
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$DOTNET_ROOT:$PATH"
dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj
```

This is the only verification this fixture expects. A clean baseline run is 43
tests, all passing, in under 2 seconds. If your change was purely in
`Ordering.Domain` or `Ordering.API/Application`, this alone is a real signal — the
suite covers both the Order/Buyer aggregate invariants
(`tests/Ordering.UnitTests/Domain/`) and the command/handler layer
(`tests/Ordering.UnitTests/Application/`).

Do **not**:
- Try to run `dotnet run --project src/eShop.AppHost` or anything that starts the
  Aspire orchestration — it expects Docker and other services (Postgres, RabbitMQ/
  Redis, Identity) that aren't set up in this fixture, and will hang or fail for
  reasons unrelated to your change.
- Run `tests/Ordering.FunctionalTests` — same reason, it's an integration suite
  against a real running stack.
- Treat a successful build (`dotnet build`) as sufficient — the repo's warnings
  are not configured as errors, and MediatR/FluentValidation wiring (assembly
  scanning for handlers and validators) has no compile-time check; a handler or
  validator with the wrong access modifier or in the wrong folder builds cleanly
  and silently never runs. Only a passing test that actually exercises the new
  behavior confirms it's wired up.

If you added a new command, event handler, or validator, make sure your new test
actually fails without your production change (comment it out locally and confirm,
if you're not sure) before trusting that it's testing what you think it is.
