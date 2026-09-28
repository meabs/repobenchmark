# Ordering subsystem answers

## 1. Cancelling an already-shipped order

The request path is:

1. `src/Ordering.API/Program.cs:19-22` creates the versioned Orders API, calls `OrdersApi.MapOrdersApiV1()`, and requires authorization. `src/Ordering.API/Apis/OrdersApi.cs:7-11` maps `PUT /api/orders/cancel` to `OrdersApi.CancelOrderAsync`.
2. `OrdersApi.CancelOrderAsync` (`src/Ordering.API/Apis/OrdersApi.cs:22-49`) rejects an empty `x-requestid` with `BadRequest`; otherwise it constructs `IdentifiedCommand<CancelOrderCommand, bool>` at line 32, sends it through `services.Mediator.Send` at line 41, and returns `Problem(detail: "Cancel order failed to process.", statusCode: 500)` at lines 43-45 when the result is `false`. A `true` result produces `Ok` at line 48.
3. MediatR is configured by `Extensions.AddApplicationServices` (`src/Ordering.API/Extensions/Extensions.cs:34-42`) to scan the API assembly and apply `LoggingBehavior<,>`, `ValidatorBehavior<,>`, and `TransactionBehavior<,>`. The outer identified request therefore passes through the corresponding `Handle` methods in `src/Ordering.API/Application/Behaviors/LoggingBehavior.cs`, `ValidatorBehavior.cs`, and `TransactionBehavior.cs`; the transaction behavior starts the transaction and invokes the identified handler. `IdentifiedCommandHandler<CancelOrderCommand, bool>.Handle` (`src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs:39-104`) checks `IRequestManager.ExistAsync` (line 41), returns the duplicate result if necessary, otherwise calls `CreateRequestForCommandAsync` (line 48) and sends the embedded `CancelOrderCommand` with `_mediator.Send` (line 87). The request manager implementation is `RequestManager` in `src/Ordering.Infrastructure/Idempotency/RequestManager.cs`; it records the client request and calls `_context.SaveChangesAsync()` at lines 34-36.
4. The inner `CancelOrderCommand` goes through `CancelOrderCommandValidator` (`src/Ordering.API/Application/Validations/CancelOrderCommandValidator.cs:3-13`), whose rule at line 7 requires a non-empty `OrderNumber`, then `CancelOrderCommandHandler.Handle` (`src/Ordering.API/Application/Commands/CancelOrderCommandHandler.cs:19-29`). Because the outer transaction is active, `TransactionBehavior.Handle` takes its `HasActiveTransaction` branch at lines 27-30 and invokes the handler without starting another transaction. The command handler loads the order with `OrderRepository.GetAsync` (`src/Ordering.Infrastructure/Repositories/OrderRepository.cs:21-31`), then calls `orderToUpdate.SetCancelledStatus()` at `CancelOrderCommandHandler.cs:27`.
5. `Order.SetCancelledStatus` (`src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:142-153`) checks `if (OrderStatus == OrderStatus.Paid || OrderStatus == OrderStatus.Shipped)` at lines 144-145. For `Shipped`, it calls `StatusChangeException(OrderStatus.Cancelled)` at line 147; `StatusChangeException` (`Order.cs:180-183`) throws `OrderingDomainException` with the from/to statuses. Therefore execution never reaches the `OrderStatus = OrderStatus.Cancelled` assignment at line 150, description update, or cancellation domain event at line 152.
6. The exception is caught by the bare `catch` in `IdentifiedCommandHandler.Handle` at lines 99-102. The exact return is `return default;` at line 101, which is `false` for `R == bool`. The caller therefore receives `false`, not the exception.
7. The outer request pipeline returns that `false` to `CancelOrderAsync`, which returns the HTTP 500 problem result described in step 2. `TransactionBehavior.Handle` (`src/Ordering.API/Application/Behaviors/TransactionBehavior.cs:20-62`) commits the surrounding transaction after the identified handler returns; no cancellation domain event was added. The client ultimately receives HTTP 500 with detail `Cancel order failed to process.`

The order is not cancelled; it remains `Shipped`. The idempotency request record can still be committed because it was created before the inner command ran and the identified handler converted the inner exception into `false`.

## 2. `Order.GetTotal()`

`Order.GetTotal()` is the expression-bodied method at `src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:185`:

```csharp
_orderItems.Sum(o => o.Units * o.UnitPrice)
```

It sums each item's quantity multiplied by its unit price. It does not read or subtract `OrderItem.Discount` (`src/Ordering.Domain/AggregatesModel/OrderAggregate/OrderItem.cs:15`), so discounts do not affect the returned total.

## 3. Exception through `IdentifiedCommandHandler<T,R>`

`IdentifiedCommandHandler<T,R>.Handle` catches any exception from `_mediator.Send(command, cancellationToken)` in `src/Ordering.API/Application/Commands/IdentifiedCommandHandler.cs:99-102`. The exact responsible line is line 101:

```csharp
return default;
```

Thus the original caller receives `default(R)`. For a `ShipOrderCommand` wrapped as `IdentifiedCommand<ShipOrderCommand, bool>`, that value is `false`; the exception is not rethrown.

## 4. `Order.SetPaidStatus()` guard

The exact guard in `src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:119-128` is:

```csharp
if (OrderStatus == OrderStatus.StockConfirmed)
```

Only an order currently in `StockConfirmed` enters the body: it adds `OrderStatusChangedToPaidDomainEvent`, assigns `OrderStatus = OrderStatus.Paid`, and updates `Description`.

For every other prior status, the `if` body is skipped. Nothing is thrown or logged; no domain event is added, and neither `OrderStatus` nor `Description` changes.

## 5. Buyer/payment verification event

The event is handled by `UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler.Handle` in `src/Ordering.API/Application/DomainEventHandlers/UpdateOrderWhenBuyerAndPaymentMethodVerifiedDomainEventHandler.cs:19-24`. It loads the order with `_orderRepository.GetAsync(domainEvent.OrderId)` at line 21 and calls:

```csharp
orderToUpdate.SetPaymentMethodVerified(domainEvent.Buyer.Id, domainEvent.Payment.Id);
```

`Order.SetPaymentMethodVerified` (`src/Ordering.Domain/AggregatesModel/OrderAggregate/Order.cs:93-97`) only sets the order's `BuyerId` and `PaymentId`. It does not change `OrderStatus`, so handling `BuyerAndPaymentMethodVerifiedDomainEvent` does not transition the order to `AwaitingValidation`.

That transition is performed by `SetAwaitingValidationOrderStatusCommandHandler.Handle` (`src/Ordering.API/Application/Commands/SetAwaitingValidationOrderStatusCommandHandler.cs:19-29`), which loads the order and calls `SetAwaitingValidationStatus()` at line 27. The aggregate method (`Order.cs:99-106`) changes `Submitted` to `AwaitingValidation` and raises `OrderStatusChangedToAwaitingValidationDomainEvent`. In the normal flow, `GracePeriodConfirmedIntegrationEventHandler.Handle` (`src/Ordering.API/Application/IntegrationEvents/EventHandling/GracePeriodConfirmedIntegrationEventHandler.cs:15-29`) creates that command and sends it through MediatR at line 28.
