# AGENTS.md

This is the full `eShop` reference application (.NET 10, Aspire-orchestrated
microservices: Catalog, Basket, Ordering, Identity, Webhooks, and a Blazor
storefront). **This documentation layer is scoped to one subsystem only: Ordering**
(`src/Ordering.Domain/`, `src/Ordering.Infrastructure/`, `src/Ordering.API/`). The
rest of the repo (Catalog, Basket, Identity, Webhooks, the Aspire AppHost, the MAUI/
Blazor clients) exists and works, but this fixture makes no claims about it and has
no docs for it — treat any task here as scoped to Ordering unless told otherwise.

**Running tests — no Docker, no Aspire needed for Ordering:**
```
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$DOTNET_ROOT:$PATH"
dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj
```
This is the only verification path this fixture expects you to use. It covers the
Order/Buyer aggregates (`tests/Ordering.UnitTests/Domain/`) and the Application layer
— command handlers, the idempotency wrapper, the minimal-API endpoints
(`tests/Ordering.UnitTests/Application/`). Don't attempt `dotnet run` on
`eShop.AppHost` or the functional test projects — they need Docker/Aspire
orchestration and are out of scope here.

- **What things mean, and why they're built that way** (the Order aggregate's
  invariants, the CQRS command flow, domain events vs. integration events, the
  idempotency pattern — rationale folded into the doc, not a separate ADR tree):
  [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per task —
  open only the one(s) matching what you're about to do:
  - `add-order-command` — add a new CQRS command + handler that mutates an Order
  - `add-order-status-transition` — add a new `Order.SetXStatus()`-style method
  - `add-command-validation-rule` — add/change a FluentValidation rule for a command
  - `add-domain-event-handler` — react to an existing domain event
- **Human setup/running instructions for the full system**: root `README.md` — not
  duplicated here, and not needed for anything scoped to Ordering.UnitTests.

Nothing else lives in this file. If you find yourself adding an explanation or a
procedure here, it belongs in `okf/` or one of the skills instead.
