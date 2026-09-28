---
type: log
title: Build log for this bundle
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:48:00Z
---

# Log

- 2026-09-28: Bundle built by reading `Ordering.Domain`, `Ordering.Infrastructure`
  (not directly documented — thin EF Core repository implementations, no
  interesting business logic), and `Ordering.API/Application` source directly,
  cross-checked against `tests/Ordering.UnitTests`.
- First draft of `domain/buyer-aggregate.md` claimed
  `UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler` was the mechanism
  that transitions a new order to `AwaitingValidation`. Re-reading that handler's
  source showed it only calls `Order.SetPaymentMethodVerified(...)` — it never calls
  `SetAwaitingValidationStatus()`. Corrected before publishing: the two flows
  (payment-method verification, and the `AwaitingValidation` transition via
  `SetAwaitingValidationOrderStatusCommandHandler`) are separate, not chained. This
  is exactly the kind of claim this bundle's trust tier warns about — verify against
  `sources` before relying on a cross-reference claim, this bundle included.
- First draft of `application/commands.md` and the `add-command-validation-rule`
  skill both said a failed validation "throws `ValidationException`." Reading
  `ValidatorBehavior.cs` directly showed it throws `OrderingDomainException`
  wrapping the FluentValidation `ValidationException` as `InnerException`. Corrected
  in both places before publishing.
- Confirmed via direct test run (`dotnet test tests/Ordering.UnitTests/...`) that
  the fixture's baseline test count is 43 passing, 0 failing, before any doc-layer
  content was added, and again after, to confirm the doc layer changes nothing about
  test behavior (docs-only commits).
