---
type: concept
title: Buyer aggregate
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:42:00Z
sources:
  - src/Ordering.Domain/AggregatesModel/BuyerAggregate/Buyer.cs
  - src/Ordering.Domain/AggregatesModel/BuyerAggregate/PaymentMethod.cs
---

# Buyer aggregate

`Buyer` is a separate aggregate root from `Order` (own repository, own consistency
boundary) — `Order.BuyerId` is a foreign key by convention, not an EF navigation
that would pull `Buyer` into the same aggregate. `Buyer`'s constructor throws
`ArgumentNullException` if `identity` or `name` is null/whitespace — there's no
optional/anonymous buyer path.

The one behavior method, `VerifyOrAddPaymentMethod`, does double duty: if a
matching payment method already exists (matched by `PaymentMethod.IsEqualTo(cardTypeId,
cardNumber, expiration)`, a value-equality check, not by identity), it's reused;
otherwise a new one is added to `_paymentMethods`. **Both branches raise the same
`BuyerAndPaymentMethodVerifiedDomainEvent`** — the event doesn't distinguish "this
was a new card" from "this card was already on file." This method is the target of
`ValidateOrAddBuyerAggregateWhenOrderStartedDomainEventHandler`
(`src/Ordering.API/Application/DomainEventHandlers/`), which reacts to a new order's
`OrderStartedDomainEvent` by looking up or creating the `Buyer` and calling this
method. The resulting `BuyerAndPaymentMethodVerifiedDomainEvent` is then handled by
`UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler`, but that handler
only calls `Order.SetPaymentMethodVerified(buyerId, paymentId)` — it does **not**
call `SetAwaitingValidationStatus()`. The `AwaitingValidation` transition is a
separate path entirely: `SetAwaitingValidationOrderStatusCommandHandler`
(`src/Ordering.API/Application/Commands/`), driven by its own command. Don't assume
these two flows are chained without checking — they update different things on the
same `Order` in response to different triggers.
