# Ordering subsystem answers

## 1. Cancelling an already-shipped order

The request path is:

1. `src/Ordering.API/Apis/OrdersApi.cs:7-18`, `OrdersApi.MapOrdersApiV1`, maps `PUT /api/orders/cancel` to `CancelOrderAsync`.
2. `src/Ordering.API/Apis/OrdersApi.cs:22-49`, `OrdersApi.CancelOrderAsync`, rejects an empty `x-requestid`; otherwise it wraps the `CancelOrderCommand` in `IdentifiedCommand<CancelOrderCommand, bool>` and awaits `services.Mediator.Send` (line 41). If that returns `false`, it returns `TypedResults.Problem(detail: "Cancel order failed to process.", statusCode: 500)` (lines 43-46); otherwise it returns `200 OK` (line 48).
3. MediatR is configured in `src/Ordering.API/Extensions/Extensions.cs:35-42`, which registers `LoggingBehavior`, `ValidatorBehavior`, and `TransactionBehavior`. `ValidatorBehavior.Handle` runs the `CancelOrderCommandValidator` from `src/Ordering.API/Application/Validations/CancelOrderCommandValidator.cs:3-13`; for a valid shipped order number its `NotEmpty` rule passes. The identified request then reaches `IdentifiedCommandHandler<CancelOrderCommand, bool>.Handle` in `src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs:39-104`.
4. `Handle` calls `IRequestManager.ExistAsync` (line 41), then `CreateRequestForCommandAsync<T>` (line 48). The implementation is `src/Ordering.Infrastructure/Idempotency/RequestManager.cs:21-37`: it checks again, adds a `ClientRequest` to the context, and calls `OrderingContext.SaveChangesAsync` (line 36). The identified handler then calls `_mediator.Send(command, cancellationToken)` (line 87) for the embedded `CancelOrderCommand`.
5. The embedded command is handled by `CancelOrderCommandHandler.Handle` in `src/Ordering.API/Application/Commands/CancelOrderCommandHandler.cs:19-29`. It calls `OrderRepository.GetAsync` (`src/Ordering.Infrastructure/Repositories/OrderRepository.cs:21-31`), which loads the order and its `OrderItems`.
6. `CancelOrderCommandHandler.Handle` calls `orderToUpdate.SetCancelledStatus()` (line 27). In `src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:142-153`, the guard at lines 144-145 matches `OrderStatus.Shipped`, so line 147 calls `StatusChangeException(OrderStatus.Cancelled)`. `StatusChangeException` (lines 180-183) throws `OrderingDomainException` before the assignment at line 150 and before the cancellation domain event at line 152.
7. The exception bubbles out of the embedded mediator call and is caught by the broad `catch` in `IdentifiedCommandHandler.Handle` (line 99). Line 101, `return default;`, returns `false` for `R = bool`. The outer transaction behavior therefore receives a normal `false` response and the endpoint receives `false`.
8. `CancelOrderAsync` returns an HTTP 500 `ProblemHttpResult` with detail `Cancel order failed to process.` (lines 43-46). The order does **not** get cancelled: its `OrderStatus` remains `Shipped`, and no `OrderCancelledDomainEvent` is added.

## 2. `Order.GetTotal()`

`src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:185` is exactly:

```csharp
public decimal GetTotal() => _orderItems.Sum(o => o.Units * o.UnitPrice);
```

It sums each item's gross `Units * UnitPrice`. It does **not** read or subtract `OrderItem.Discount` (`src/Ordering.Domain/AggregatesModel/OrderAggregate/OrderItem.cs:13-17`), so discounts have no effect on this total. With no items, LINQ's decimal `Sum` yields `0`.

## 3. Exception through the identified-command path

For an exception thrown by the embedded handler, `IdentifiedCommandHandler<T,R>.Handle` catches it at `src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs:99` and returns `default` at **line 101**:

```csharp
catch
{
    return default;
}
```

Therefore the original caller receives `default(R)` rather than the exception. For `IdentifiedCommand<ShipOrderCommand, bool>`, that value is `false`.

## 4. `Order.SetPaidStatus()` guard

The exact guard in `src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:119-128` is:

```csharp
if (OrderStatus == OrderStatus.StockConfirmed)
```

Only in that state does it add `OrderStatusChangedToPaidDomainEvent`, set `OrderStatus = OrderStatus.Paid`, and set the payment description. For every other prior status, the method does nothing: it does not change status or description, add a domain event, throw, or log. It returns normally because it is `void`. Consequently, the normal `SetPaidOrderStatusCommandHandler.Handle` path (`src/Ordering.API/Application/Commands/SetPaidOrderStatusCommandHandler.cs:19-32`) can continue to `SaveEntitiesAsync` and return its result even when `SetPaidStatus()` made no change.

## 5. Buyer/payment verification event

`Buyer.VerifyOrAddPaymentMethod` raises `BuyerAndPaymentMethodVerifiedDomainEvent` in `src/Ordering.Domain/AggregatesModel/BuyerAggregate/Buyer.cs:29-49`. The handler is `UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler.Handle` in `src/Ordering.API/Application/DomainEventHandlers/UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler.cs:19-24`.

That handler loads the order with `_orderRepository.GetAsync(domainEvent.OrderId)` (line 21), then calls `orderToUpdate.SetPaymentMethodVerified(domainEvent.Buyer.Id, domainEvent.Payment.Id)` (line 22). `Order.SetPaymentMethodVerified` only assigns `BuyerId` and `PaymentId` (`src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:93-97`); it does not touch `OrderStatus`. Therefore handling this event does **not** transition the order to `AwaitingValidation`.

The transition is performed by `Order.SetAwaitingValidationStatus()` (`Order.cs:99-106`), called by `SetAwaitingValidationOrderStatusCommandHandler.Handle` (`src/Ordering.API/Application/Commands/SetAwaitingValidationOrderStatusCommandHandler.cs:19-29`, especially line 27). That command is sent by `GracePeriodConfirmedIntegrationEventHandler.Handle` (`src/Ordering.API/Application/IntegrationEvents/EventHandling/GracePeriodConfirmedIntegrationEventHandler.cs:15-29`, lines 19 and 28). The domain method changes the status only when the prior status is `Submitted`; it first adds `OrderStatusChangedToAwaitingValidationDomainEvent` and then assigns `AwaitingValidation`.
