# Rx.NET In-Process Message Bus Patterns

## Basic Message Bus

```csharp
public interface ICommand;
public interface IEvent;

public class RxMessageBus : IDisposable
{
    private readonly Subject<object> _subject = new();

    public void Publish<T>(T message) => _subject.OnNext(message!);

    public IDisposable Subscribe<T>(Func<T, Task> handler) =>
        _subject.OfType<T>().SelectMany(e => handler(e)).Subscribe();

    public IObservable<T> Observe<T>() => _subject.OfType<T>();

    public void Dispose() => _subject.Dispose();
}
```

## Pipeline Extensions

Reusable middleware-style operators:

```csharp
public static class MessagePipelineExtensions
{
    public static IObservable<T> WithLogging<T>(this IObservable<T> source, ILogger logger) =>
        source.Do(
            x => logger.LogDebug("Processing {Type}", x.GetType().Name),
            ex => logger.LogError(ex, "Pipeline error"));

    public static IObservable<T> WithRetry<T>(this IObservable<T> source, int retryCount, TimeSpan delay) =>
        source.RetryWhen(errors => errors
            .Select((err, i) => (err, attempt: i + 1))
            .SelectMany(x => x.attempt <= retryCount
                ? Observable.Timer(delay)
                : Observable.Throw<long>(x.err)));

    public static IObservable<T> WithTimeout<T>(this IObservable<T> source, TimeSpan timeout) =>
        source.Timeout(timeout);

    public static IObservable<T> WithCircuitBreaker<T>(
        this IObservable<T> source,
        int failureThreshold,
        TimeSpan resetTimeout)
    {
        var failures = 0;
        var circuitOpen = false;
        var lastFailure = DateTime.MinValue;

        return source.SelectMany(item =>
        {
            if (circuitOpen && DateTime.UtcNow - lastFailure < resetTimeout)
                return Observable.Empty<T>();

            circuitOpen = false;
            return Observable.Return(item);
        })
        .Do(_ => failures = 0)
        .Catch<T, Exception>(ex =>
        {
            failures++;
            lastFailure = DateTime.UtcNow;
            if (failures >= failureThreshold) circuitOpen = true;
            return Observable.Throw<T>(ex);
        });
    }

    public static IObservable<T> WithMetrics<T>(this IObservable<T> source, string metricName) =>
        source.Select(x => (item: x, sw: Stopwatch.StartNew()))
              .Do(x => { /* emit x.sw.Elapsed to your metrics system */ })
              .Select(x => x.item);

    public static IObservable<IList<T>> WithBatching<T>(this IObservable<T> source, TimeSpan window, int maxBatch) =>
        source.Buffer(window, maxBatch);

    public static IObservable<T> WithDeadLetter<T>(
        this IObservable<T> source,
        Action<T, Exception> deadLetterHandler) =>
        source.Catch<T, Exception>((ex, caught) =>
        {
            caught.Subscribe(item => deadLetterHandler(item, ex));
            return Observable.Empty<T>();
        });
}
```

## Composed Pipeline Example

```csharp
public class OrderCommandPipeline
{
    private readonly RxMessageBus _bus;
    private readonly ILogger _logger;
    private readonly IServiceProvider _provider;

    public OrderCommandPipeline(RxMessageBus bus, ILogger logger, IServiceProvider provider)
    {
        _bus = bus;
        _logger = logger;
        _provider = provider;

        _bus.Observe<ICommand>()
            .WithLogging(_logger)
            .WithRetry(3, TimeSpan.FromSeconds(1))
            .WithTimeout(TimeSpan.FromSeconds(30))
            .WithCircuitBreaker(5, TimeSpan.FromMinutes(1))
            .SelectMany(cmd => HandleCommand(cmd))
            .Subscribe(
                _ => { },
                ex => _logger.LogError(ex, "Pipeline terminated"));
    }

    private async Task<Unit> HandleCommand(ICommand command)
    {
        var handlerType = typeof(ICommandHandler<>).MakeGenericType(command.GetType());
        var handler = _provider.GetRequiredService(handlerType);
        var method = handlerType.GetMethod("HandleAsync")!;
        await (Task)method.Invoke(handler, [command, CancellationToken.None])!;
        return Unit.Default;
    }
}
```

## Event Fan-Out with Different Pipelines

```csharp
// Critical events: retry aggressively
_bus.Observe<OrderPlacedEvent>()
    .WithRetry(5, TimeSpan.FromMilliseconds(500))
    .Subscribe(e => _inventory.Reserve(e));

// Analytics: batch and don't fail
_bus.Observe<IEvent>()
    .WithBatching(TimeSpan.FromSeconds(10), 100)
    .Subscribe(batch => _analytics.TrackBatch(batch));

// Notifications: best-effort, no retry
_bus.Observe<OrderPlacedEvent>()
    .Subscribe(e => _email.SendConfirmation(e));
```

## Subject Variants

| Subject | Behavior |
|---------|----------|
| `Subject<T>` | Standard pub/sub, no replay |
| `ReplaySubject<T>` | Replays N items to late subscribers |
| `BehaviorSubject<T>` | Replays latest item, requires initial value |
| `AsyncSubject<T>` | Only emits final value on completion |

```csharp
// Replay last 10 events for late subscribers
private readonly ReplaySubject<object> _subject = new(bufferSize: 10);

// Replay events from last 5 minutes
private readonly ReplaySubject<object> _subject = new(window: TimeSpan.FromMinutes(5));
```

## Backpressure Handling

```csharp
// Throttle: only take one per interval
_bus.Observe<HighFrequencyEvent>()
    .Throttle(TimeSpan.FromMilliseconds(100))
    .Subscribe(Handle);

// Sample: take latest per interval
_bus.Observe<MetricEvent>()
    .Sample(TimeSpan.FromSeconds(1))
    .Subscribe(Handle);

// Buffer: collect and batch process
_bus.Observe<LogEvent>()
    .Buffer(TimeSpan.FromSeconds(5))
    .Where(batch => batch.Count > 0)
    .Subscribe(HandleBatch);
```

## Outbox Pattern

Ensures reliable message delivery by storing messages in the database within the same transaction as your business data. A background processor then publishes them.

**Why use it:**
- Guarantees at-least-once delivery
- No message loss if bus/app crashes after DB commit
- Atomic: business data and message saved together or not at all

**Outbox Entity:**

```csharp
public class OutboxMessage
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Type { get; init; } = default!;
    public string Payload { get; init; } = default!;
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
    public DateTime? ProcessedAt { get; set; }
    public int RetryCount { get; set; }
}
```

**Saving to Outbox (same transaction as business data):**

```csharp
public class OrderService
{
    private readonly AppDbContext _db;

    public async Task PlaceOrderAsync(Order order)
    {
        await using var tx = await _db.Database.BeginTransactionAsync();

        _db.Orders.Add(order);

        _db.OutboxMessages.Add(new OutboxMessage
        {
            Type = typeof(OrderPlacedEvent).AssemblyQualifiedName!,
            Payload = JsonSerializer.Serialize(new OrderPlacedEvent(order.Id, order.Total))
        });

        await _db.SaveChangesAsync();
        await tx.CommitAsync();
    }
}
```

**Outbox Processor (BackgroundService + Rx):**

```csharp
public class OutboxProcessor : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RxMessageBus _bus;
    private readonly ILogger<OutboxProcessor> _logger;

    public OutboxProcessor(
        IServiceScopeFactory scopeFactory,
        RxMessageBus bus,
        ILogger<OutboxProcessor> logger)
    {
        _scopeFactory = scopeFactory;
        _bus = bus;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        Observable
            .Interval(TimeSpan.FromSeconds(5))
            .SelectMany(_ => ProcessBatchAsync(ct).ToObservable())
            .WithLogging(_logger)
            .WithRetry(3, TimeSpan.FromSeconds(10))
            .Subscribe(ct);

        await Task.Delay(Timeout.Infinite, ct);
    }

    private async Task<Unit> ProcessBatchAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var messages = await db.OutboxMessages
            .Where(m => m.ProcessedAt == null && m.RetryCount < 5)
            .OrderBy(m => m.CreatedAt)
            .Take(100)
            .ToListAsync(ct);

        foreach (var msg in messages)
        {
            try
            {
                var type = Type.GetType(msg.Type)!;
                var payload = JsonSerializer.Deserialize(msg.Payload, type)!;

                _bus.Publish(payload);

                msg.ProcessedAt = DateTime.UtcNow;
            }
            catch
            {
                msg.RetryCount++;
            }
        }

        await db.SaveChangesAsync(ct);
        return Unit.Default;
    }
}
```

**Cleanup Old Messages:**

```csharp
// Run periodically to purge processed messages
await db.OutboxMessages
    .Where(m => m.ProcessedAt != null && m.ProcessedAt < DateTime.UtcNow.AddDays(-7))
    .ExecuteDeleteAsync();
```

**Idempotency (consumer side):**

Since outbox guarantees at-least-once (not exactly-once), handlers must be idempotent:

```csharp
public class ReserveInventoryHandler : IEventHandler<OrderPlacedEvent>
{
    private readonly AppDbContext _db;

    public async Task HandleAsync(OrderPlacedEvent e, CancellationToken ct)
    {
        // Check if already processed
        if (await _db.ProcessedEvents.AnyAsync(p => p.EventId == e.EventId, ct))
            return;

        // Do the work
        await _db.Inventory.Where(i => i.ProductId == e.ProductId)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.Reserved, i => i.Reserved + e.Quantity), ct);

        // Mark as processed
        _db.ProcessedEvents.Add(new ProcessedEvent { EventId = e.EventId });
        await _db.SaveChangesAsync(ct);
    }
}
```

## Saga Pattern

Manages long-running transactions across multiple modules with compensating actions on failure. Two styles: **choreography** (event-driven) and **orchestration** (central coordinator).

### Saga State

```csharp
public enum SagaStatus { Pending, Running, Completed, Compensating, Failed }

public class SagaState
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string SagaType { get; init; } = default!;
    public string Data { get; init; } = default!;
    public SagaStatus Status { get; set; } = SagaStatus.Pending;
    public int CurrentStep { get; set; }
    public List<string> CompletedSteps { get; set; } = [];
    public string? Error { get; set; }
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }
}
```

### Orchestration Style

Central coordinator manages the flow:

```csharp
public interface ISagaStep<TData>
{
    Task ExecuteAsync(TData data, CancellationToken ct);
    Task CompensateAsync(TData data, CancellationToken ct);
}

public abstract class Saga<TData>
{
    protected abstract IReadOnlyList<ISagaStep<TData>> Steps { get; }

    public async Task<SagaResult> ExecuteAsync(TData data, CancellationToken ct = default)
    {
        var completed = new Stack<ISagaStep<TData>>();

        try
        {
            foreach (var step in Steps)
            {
                await step.ExecuteAsync(data, ct);
                completed.Push(step);
            }
            return SagaResult.Success();
        }
        catch (Exception ex)
        {
            // Compensate in reverse order
            while (completed.Count > 0)
            {
                var step = completed.Pop();
                try
                {
                    await step.CompensateAsync(data, ct);
                }
                catch (Exception compEx)
                {
                    // Log and continue compensating
                    return SagaResult.CompensationFailed(ex, compEx);
                }
            }
            return SagaResult.Failed(ex);
        }
    }
}

public record SagaResult(bool IsSuccess, Exception? Error, Exception? CompensationError)
{
    public static SagaResult Success() => new(true, null, null);
    public static SagaResult Failed(Exception ex) => new(false, ex, null);
    public static SagaResult CompensationFailed(Exception ex, Exception compEx) => new(false, ex, compEx);
}
```

**Order Saga Example:**

```csharp
public record OrderSagaData(Guid OrderId, Guid CustomerId, List<OrderItem> Items, decimal Total);

public class PlaceOrderSaga : Saga<OrderSagaData>
{
    private readonly IInventoryService _inventory;
    private readonly IPaymentService _payment;
    private readonly IShippingService _shipping;

    protected override IReadOnlyList<ISagaStep<OrderSagaData>> Steps =>
    [
        new ReserveInventoryStep(_inventory),
        new ProcessPaymentStep(_payment),
        new ScheduleShippingStep(_shipping)
    ];
}

public class ReserveInventoryStep : ISagaStep<OrderSagaData>
{
    private readonly IInventoryService _inventory;
    public ReserveInventoryStep(IInventoryService inventory) => _inventory = inventory;

    public Task ExecuteAsync(OrderSagaData data, CancellationToken ct) =>
        _inventory.ReserveAsync(data.OrderId, data.Items, ct);

    public Task CompensateAsync(OrderSagaData data, CancellationToken ct) =>
        _inventory.ReleaseAsync(data.OrderId, ct);
}

public class ProcessPaymentStep : ISagaStep<OrderSagaData>
{
    private readonly IPaymentService _payment;
    public ProcessPaymentStep(IPaymentService payment) => _payment = payment;

    public Task ExecuteAsync(OrderSagaData data, CancellationToken ct) =>
        _payment.ChargeAsync(data.CustomerId, data.Total, data.OrderId, ct);

    public Task CompensateAsync(OrderSagaData data, CancellationToken ct) =>
        _payment.RefundAsync(data.OrderId, ct);
}
```

### Choreography Style with Rx

Each module reacts to events, no central coordinator:

```csharp
public class InventoryModule
{
    public InventoryModule(RxMessageBus bus, IInventoryRepo repo)
    {
        bus.Observe<OrderPlacedEvent>()
            .SelectMany(async e =>
            {
                try
                {
                    await repo.ReserveAsync(e.OrderId, e.Items);
                    bus.Publish(new InventoryReservedEvent(e.OrderId));
                }
                catch
                {
                    bus.Publish(new InventoryReservationFailedEvent(e.OrderId));
                }
                return Unit.Default;
            })
            .Subscribe();

        // Compensate when payment fails
        bus.Observe<PaymentFailedEvent>()
            .SelectMany(e => repo.ReleaseAsync(e.OrderId).ToObservable())
            .Subscribe();
    }
}

public class PaymentModule
{
    public PaymentModule(RxMessageBus bus, IPaymentService payment)
    {
        // Only proceed after inventory reserved
        bus.Observe<InventoryReservedEvent>()
            .SelectMany(async e =>
            {
                try
                {
                    await payment.ChargeAsync(e.OrderId);
                    bus.Publish(new PaymentCompletedEvent(e.OrderId));
                }
                catch
                {
                    bus.Publish(new PaymentFailedEvent(e.OrderId));
                }
                return Unit.Default;
            })
            .Subscribe();
    }
}
```

### Persistent Saga Orchestrator with Rx

For long-running sagas that survive restarts:

```csharp
public class SagaOrchestrator : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RxMessageBus _bus;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        // Resume incomplete sagas on startup
        await ResumeIncompleteSagasAsync(ct);

        // Listen for new saga triggers
        _bus.Observe<StartOrderSagaCommand>()
            .SelectMany(cmd => ExecuteSagaAsync(cmd, ct).ToObservable())
            .Subscribe(ct);

        await Task.Delay(Timeout.Infinite, ct);
    }

    private async Task ExecuteSagaAsync(StartOrderSagaCommand cmd, CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var state = new SagaState
        {
            SagaType = nameof(PlaceOrderSaga),
            Data = JsonSerializer.Serialize(cmd.Data),
            Status = SagaStatus.Running
        };

        db.Sagas.Add(state);
        await db.SaveChangesAsync(ct);

        var saga = scope.ServiceProvider.GetRequiredService<PlaceOrderSaga>();
        var result = await saga.ExecuteAsync(cmd.Data, ct);

        state.Status = result.IsSuccess ? SagaStatus.Completed : SagaStatus.Failed;
        state.Error = result.Error?.Message;
        state.CompletedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);

        _bus.Publish(result.IsSuccess
            ? new OrderSagaCompletedEvent(cmd.Data.OrderId)
            : new OrderSagaFailedEvent(cmd.Data.OrderId, result.Error!.Message));
    }

    private async Task ResumeIncompleteSagasAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var incomplete = await db.Sagas
            .Where(s => s.Status == SagaStatus.Running)
            .ToListAsync(ct);

        foreach (var saga in incomplete)
        {
            saga.Status = SagaStatus.Compensating;
            // Trigger compensation logic based on saga.CurrentStep
        }

        await db.SaveChangesAsync(ct);
    }
}
```

### Choreography vs Orchestration

| Aspect | Choreography | Orchestration |
|--------|--------------|---------------|
| Coupling | Loose, modules independent | Tighter, orchestrator knows all steps |
| Visibility | Hard to trace flow | Easy to see full saga in one place |
| Complexity | Distributed across modules | Centralized in orchestrator |
| Adding steps | Touch multiple modules | Modify one class |
| Failure handling | Each module handles own | Central compensation logic |
| Best for | Simple flows, few steps | Complex flows, many steps |

### Timeout Handling with Rx

```csharp
_bus.Observe<OrderPlacedEvent>()
    .SelectMany(e =>
        _bus.Observe<PaymentCompletedEvent>()
            .Where(p => p.OrderId == e.OrderId)
            .Timeout(TimeSpan.FromMinutes(5))
            .Take(1)
            .Catch<PaymentCompletedEvent, TimeoutException>(_ =>
            {
                _bus.Publish(new OrderTimedOutEvent(e.OrderId));
                return Observable.Empty<PaymentCompletedEvent>();
            }))
    .Subscribe();
```

## CQRS (Command Query Responsibility Segregation)

Separates read (query) and write (command) models. Commands mutate state and return nothing (or just ID). Queries return data and have no side effects.

### Core Abstractions

```csharp
// Commands: write operations, no return value
public interface ICommand;
public interface ICommandHandler<T> where T : ICommand
{
    Task HandleAsync(T command, CancellationToken ct = default);
}

// Commands that return a result (e.g., created ID)
public interface ICommand<TResult>;
public interface ICommandHandler<TCommand, TResult> where TCommand : ICommand<TResult>
{
    Task<TResult> HandleAsync(TCommand command, CancellationToken ct = default);
}

// Queries: read operations, always return data
public interface IQuery<TResult>;
public interface IQueryHandler<TQuery, TResult> where TQuery : IQuery<TResult>
{
    Task<TResult> HandleAsync(TQuery query, CancellationToken ct = default);
}
```

### Dispatcher

```csharp
public interface IDispatcher
{
    Task SendAsync<T>(T command, CancellationToken ct = default) where T : ICommand;
    Task<TResult> SendAsync<TResult>(ICommand<TResult> command, CancellationToken ct = default);
    Task<TResult> QueryAsync<TResult>(IQuery<TResult> query, CancellationToken ct = default);
}

public class Dispatcher : IDispatcher
{
    private readonly IServiceProvider _provider;

    public Dispatcher(IServiceProvider provider) => _provider = provider;

    public async Task SendAsync<T>(T command, CancellationToken ct = default) where T : ICommand
    {
        var handler = _provider.GetRequiredService<ICommandHandler<T>>();
        await handler.HandleAsync(command, ct);
    }

    public async Task<TResult> SendAsync<TResult>(ICommand<TResult> command, CancellationToken ct = default)
    {
        var handlerType = typeof(ICommandHandler<,>).MakeGenericType(command.GetType(), typeof(TResult));
        dynamic handler = _provider.GetRequiredService(handlerType);
        return await handler.HandleAsync((dynamic)command, ct);
    }

    public async Task<TResult> QueryAsync<TResult>(IQuery<TResult> query, CancellationToken ct = default)
    {
        var handlerType = typeof(IQueryHandler<,>).MakeGenericType(query.GetType(), typeof(TResult));
        dynamic handler = _provider.GetRequiredService(handlerType);
        return await handler.HandleAsync((dynamic)query, ct);
    }
}
```

### Commands and Handlers

```csharp
// Command definition
public record CreateOrderCommand(Guid CustomerId, List<OrderItem> Items) : ICommand<Guid>;

// Command handler - writes to write model
public class CreateOrderHandler : ICommandHandler<CreateOrderCommand, Guid>
{
    private readonly WriteDbContext _db;
    private readonly RxMessageBus _bus;

    public CreateOrderHandler(WriteDbContext db, RxMessageBus bus)
    {
        _db = db;
        _bus = bus;
    }

    public async Task<Guid> HandleAsync(CreateOrderCommand cmd, CancellationToken ct)
    {
        var order = new Order
        {
            Id = Guid.NewGuid(),
            CustomerId = cmd.CustomerId,
            Items = cmd.Items,
            Status = OrderStatus.Created,
            CreatedAt = DateTime.UtcNow
        };

        _db.Orders.Add(order);
        await _db.SaveChangesAsync(ct);

        // Publish event for read model update
        _bus.Publish(new OrderCreatedEvent(order.Id, order.CustomerId, order.Items));

        return order.Id;
    }
}
```

### Queries and Handlers

```csharp
// Query definition
public record GetOrderByIdQuery(Guid OrderId) : IQuery<OrderDto?>;
public record GetOrdersByCustomerQuery(Guid CustomerId, int Page, int PageSize) : IQuery<PagedResult<OrderSummaryDto>>;

// Query handler - reads from read model
public class GetOrderByIdHandler : IQueryHandler<GetOrderByIdQuery, OrderDto?>
{
    private readonly ReadDbContext _db;

    public GetOrderByIdHandler(ReadDbContext db) => _db = db;

    public async Task<OrderDto?> HandleAsync(GetOrderByIdQuery query, CancellationToken ct)
    {
        return await _db.OrderReadModels
            .Where(o => o.Id == query.OrderId)
            .Select(o => new OrderDto(o.Id, o.CustomerName, o.Items, o.Total, o.Status))
            .FirstOrDefaultAsync(ct);
    }
}
```

### Read Model Projections with Rx

Update read models by subscribing to events:

```csharp
public class OrderReadModelProjection
{
    private readonly IServiceScopeFactory _scopeFactory;

    public OrderReadModelProjection(RxMessageBus bus, IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;

        bus.Observe<OrderCreatedEvent>()
            .SelectMany(e => ProjectAsync(e).ToObservable())
            .Subscribe();

        bus.Observe<OrderStatusChangedEvent>()
            .SelectMany(e => UpdateStatusAsync(e).ToObservable())
            .Subscribe();

        bus.Observe<OrderItemAddedEvent>()
            .Buffer(TimeSpan.FromSeconds(1)) // Batch updates
            .Where(batch => batch.Count > 0)
            .SelectMany(batch => BatchUpdateItemsAsync(batch).ToObservable())
            .Subscribe();
    }

    private async Task ProjectAsync(OrderCreatedEvent e)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ReadDbContext>();

        var customer = await db.CustomerReadModels.FindAsync(e.CustomerId);

        db.OrderReadModels.Add(new OrderReadModel
        {
            Id = e.OrderId,
            CustomerId = e.CustomerId,
            CustomerName = customer?.Name ?? "Unknown",
            Items = e.Items.Select(i => new OrderItemReadModel(i.ProductName, i.Quantity, i.Price)).ToList(),
            Total = e.Items.Sum(i => i.Quantity * i.Price),
            Status = "Created",
            CreatedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
    }

    private async Task UpdateStatusAsync(OrderStatusChangedEvent e)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ReadDbContext>();

        await db.OrderReadModels
            .Where(o => o.Id == e.OrderId)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.Status, e.NewStatus));
    }
}
```

### Separate Read/Write Databases

```csharp
// Write side: normalized, optimized for consistency
public class WriteDbContext : DbContext
{
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<OutboxMessage> OutboxMessages => Set<OutboxMessage>();
}

// Read side: denormalized, optimized for queries
public class ReadDbContext : DbContext
{
    public DbSet<OrderReadModel> OrderReadModels => Set<OrderReadModel>();
    public DbSet<CustomerReadModel> CustomerReadModels => Set<CustomerReadModel>();
    public DbSet<ProductCatalogReadModel> ProductCatalog => Set<ProductCatalogReadModel>();
}

// Read model: flat, query-optimized
public class OrderReadModel
{
    public Guid Id { get; set; }
    public Guid CustomerId { get; set; }
    public string CustomerName { get; set; } = default!; // Denormalized
    public string CustomerEmail { get; set; } = default!; // Denormalized
    public List<OrderItemReadModel> Items { get; set; } = [];
    public decimal Total { get; set; } // Pre-computed
    public string Status { get; set; } = default!;
    public DateTime CreatedAt { get; set; }
}
```

### Pipeline Decorators

Add cross-cutting concerns via decorators:

```csharp
// Logging decorator
public class LoggingCommandHandler<T> : ICommandHandler<T> where T : ICommand
{
    private readonly ICommandHandler<T> _inner;
    private readonly ILogger _logger;

    public LoggingCommandHandler(ICommandHandler<T> inner, ILogger logger)
    {
        _inner = inner;
        _logger = logger;
    }

    public async Task HandleAsync(T command, CancellationToken ct)
    {
        _logger.LogInformation("Handling {Command}", typeof(T).Name);
        var sw = Stopwatch.StartNew();

        await _inner.HandleAsync(command, ct);

        _logger.LogInformation("Handled {Command} in {Elapsed}ms", typeof(T).Name, sw.ElapsedMilliseconds);
    }
}

// Validation decorator
public class ValidationCommandHandler<T> : ICommandHandler<T> where T : ICommand
{
    private readonly ICommandHandler<T> _inner;
    private readonly IValidator<T> _validator;

    public async Task HandleAsync(T command, CancellationToken ct)
    {
        var result = await _validator.ValidateAsync(command, ct);
        if (!result.IsValid)
            throw new ValidationException(result.Errors);

        await _inner.HandleAsync(command, ct);
    }
}

// Transaction decorator
public class TransactionalCommandHandler<T> : ICommandHandler<T> where T : ICommand
{
    private readonly ICommandHandler<T> _inner;
    private readonly WriteDbContext _db;

    public async Task HandleAsync(T command, CancellationToken ct)
    {
        await using var tx = await _db.Database.BeginTransactionAsync(ct);
        await _inner.HandleAsync(command, ct);
        await tx.CommitAsync(ct);
    }
}
```

### Registration with Scrutor

```csharp
services.Scan(scan => scan
    .FromAssemblyOf<CreateOrderHandler>()
    .AddClasses(c => c.AssignableTo(typeof(ICommandHandler<>)))
    .AsImplementedInterfaces()
    .WithScopedLifetime()
    .AddClasses(c => c.AssignableTo(typeof(ICommandHandler<,>)))
    .AsImplementedInterfaces()
    .WithScopedLifetime()
    .AddClasses(c => c.AssignableTo(typeof(IQueryHandler<,>)))
    .AsImplementedInterfaces()
    .WithScopedLifetime());

// Decorate all command handlers
services.Decorate(typeof(ICommandHandler<>), typeof(LoggingCommandHandler<>));
services.Decorate(typeof(ICommandHandler<>), typeof(ValidationCommandHandler<>));
services.Decorate(typeof(ICommandHandler<>), typeof(TransactionalCommandHandler<>));
```

### API Usage

```csharp
[ApiController]
[Route("api/orders")]
public class OrdersController : ControllerBase
{
    private readonly IDispatcher _dispatcher;

    public OrdersController(IDispatcher dispatcher) => _dispatcher = dispatcher;

    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest request, CancellationToken ct)
    {
        var orderId = await _dispatcher.SendAsync(
            new CreateOrderCommand(request.CustomerId, request.Items), ct);

        return CreatedAtAction(nameof(GetById), new { id = orderId }, null);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var order = await _dispatcher.QueryAsync(new GetOrderByIdQuery(id), ct);
        return order is null ? NotFound() : Ok(order);
    }

    [HttpGet]
    public async Task<IActionResult> GetByCustomer(
        [FromQuery] Guid customerId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await _dispatcher.QueryAsync(
            new GetOrdersByCustomerQuery(customerId, page, pageSize), ct);

        return Ok(result);
    }
}
```

### Eventual Consistency Note

With separate read/write models, reads may be slightly stale:

```csharp
[HttpPost]
public async Task<IActionResult> Create(CreateOrderRequest request, CancellationToken ct)
{
    var orderId = await _dispatcher.SendAsync(
        new CreateOrderCommand(request.CustomerId, request.Items), ct);

    // Option 1: Return ID only, client fetches later
    return Accepted(new { orderId });

    // Option 2: Return write model data directly (not from read model)
    return Created($"/api/orders/{orderId}", new { orderId, status = "Created" });

    // Option 3: Wait for projection (not recommended, adds latency)
}
```

## Event Sourcing

Instead of storing current state, store the sequence of events that led to it. State is derived by replaying events.

### Core Concepts

```
Traditional:  Order { Status: "Shipped", Total: 150 }

Event Sourced:
  1. OrderCreated { Id, CustomerId, Items }
  2. ItemAdded { ProductId, Quantity }
  3. PaymentReceived { Amount: 150 }
  4. OrderShipped { TrackingNumber }
```

**Benefits:**
- Complete audit trail
- Temporal queries ("what was the state last Tuesday?")
- Debug by replaying events
- Rebuild read models from scratch
- Natural fit with CQRS

### Event Store Abstractions

```csharp
public interface IEvent
{
    Guid EventId { get; }
    DateTime Timestamp { get; }
}

public abstract record DomainEvent : IEvent
{
    public Guid EventId { get; init; } = Guid.NewGuid();
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;
}

public class StoredEvent
{
    public long SequenceNumber { get; set; }
    public Guid StreamId { get; set; }
    public string StreamType { get; set; } = default!;
    public int Version { get; set; }
    public string EventType { get; set; } = default!;
    public string Data { get; set; } = default!;
    public string? Metadata { get; set; }
    public DateTime Timestamp { get; set; }
}

public interface IEventStore
{
    Task AppendAsync(Guid streamId, string streamType, IEnumerable<IEvent> events, int expectedVersion, CancellationToken ct = default);
    Task<List<StoredEvent>> LoadAsync(Guid streamId, int fromVersion = 0, CancellationToken ct = default);
    IObservable<StoredEvent> Subscribe(string? streamType = null);
}
```

### Simple Event Store Implementation

```csharp
public class EventStore : IEventStore
{
    private readonly EventStoreDbContext _db;
    private readonly Subject<StoredEvent> _subject = new();
    private readonly JsonSerializerOptions _jsonOptions;

    public EventStore(EventStoreDbContext db)
    {
        _db = db;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }

    public async Task AppendAsync(
        Guid streamId,
        string streamType,
        IEnumerable<IEvent> events,
        int expectedVersion,
        CancellationToken ct = default)
    {
        var currentVersion = await _db.Events
            .Where(e => e.StreamId == streamId)
            .MaxAsync(e => (int?)e.Version, ct) ?? -1;

        if (currentVersion != expectedVersion)
            throw new ConcurrencyException(streamId, expectedVersion, currentVersion);

        var version = expectedVersion;
        var storedEvents = new List<StoredEvent>();

        foreach (var @event in events)
        {
            version++;
            var stored = new StoredEvent
            {
                StreamId = streamId,
                StreamType = streamType,
                Version = version,
                EventType = @event.GetType().AssemblyQualifiedName!,
                Data = JsonSerializer.Serialize(@event, @event.GetType(), _jsonOptions),
                Timestamp = @event.Timestamp
            };

            _db.Events.Add(stored);
            storedEvents.Add(stored);
        }

        await _db.SaveChangesAsync(ct);

        // Publish to subscribers
        foreach (var stored in storedEvents)
            _subject.OnNext(stored);
    }

    public async Task<List<StoredEvent>> LoadAsync(Guid streamId, int fromVersion = 0, CancellationToken ct = default)
    {
        return await _db.Events
            .Where(e => e.StreamId == streamId && e.Version > fromVersion)
            .OrderBy(e => e.Version)
            .ToListAsync(ct);
    }

    public IObservable<StoredEvent> Subscribe(string? streamType = null)
    {
        return streamType is null
            ? _subject.AsObservable()
            : _subject.Where(e => e.StreamType == streamType);
    }

    public IEvent Deserialize(StoredEvent stored)
    {
        var type = Type.GetType(stored.EventType)!;
        return (IEvent)JsonSerializer.Deserialize(stored.Data, type, _jsonOptions)!;
    }
}

public class ConcurrencyException : Exception
{
    public ConcurrencyException(Guid streamId, int expected, int actual)
        : base($"Stream {streamId}: expected version {expected}, but was {actual}") { }
}
```

### Aggregate Root

```csharp
public abstract class AggregateRoot
{
    public Guid Id { get; protected set; }
    public int Version { get; private set; } = -1;

    private readonly List<IEvent> _uncommittedEvents = [];
    public IReadOnlyList<IEvent> UncommittedEvents => _uncommittedEvents;

    protected void RaiseEvent(IEvent @event)
    {
        ApplyEvent(@event);
        _uncommittedEvents.Add(@event);
    }

    protected abstract void ApplyEvent(IEvent @event);

    public void Load(IEnumerable<IEvent> history)
    {
        foreach (var @event in history)
        {
            ApplyEvent(@event);
            Version++;
        }
    }

    public void MarkCommitted()
    {
        Version += _uncommittedEvents.Count;
        _uncommittedEvents.Clear();
    }
}
```

### Order Aggregate Example

```csharp
// Events
public record OrderCreatedEvent(Guid OrderId, Guid CustomerId, DateTime CreatedAt) : DomainEvent;
public record OrderItemAddedEvent(Guid OrderId, Guid ProductId, string ProductName, int Quantity, decimal Price) : DomainEvent;
public record OrderItemRemovedEvent(Guid OrderId, Guid ProductId) : DomainEvent;
public record OrderSubmittedEvent(Guid OrderId, DateTime SubmittedAt) : DomainEvent;
public record OrderPaidEvent(Guid OrderId, decimal Amount, string PaymentReference) : DomainEvent;
public record OrderShippedEvent(Guid OrderId, string TrackingNumber, DateTime ShippedAt) : DomainEvent;
public record OrderCancelledEvent(Guid OrderId, string Reason) : DomainEvent;

// Aggregate
public class Order : AggregateRoot
{
    public Guid CustomerId { get; private set; }
    public OrderStatus Status { get; private set; }
    public List<OrderItem> Items { get; private set; } = [];
    public decimal Total => Items.Sum(i => i.Quantity * i.Price);
    public string? TrackingNumber { get; private set; }

    private Order() { } // For rehydration

    public static Order Create(Guid orderId, Guid customerId)
    {
        var order = new Order();
        order.RaiseEvent(new OrderCreatedEvent(orderId, customerId, DateTime.UtcNow));
        return order;
    }

    public void AddItem(Guid productId, string productName, int quantity, decimal price)
    {
        if (Status != OrderStatus.Draft)
            throw new InvalidOperationException("Cannot modify submitted order");

        RaiseEvent(new OrderItemAddedEvent(Id, productId, productName, quantity, price));
    }

    public void RemoveItem(Guid productId)
    {
        if (Status != OrderStatus.Draft)
            throw new InvalidOperationException("Cannot modify submitted order");

        if (Items.All(i => i.ProductId != productId))
            throw new InvalidOperationException("Item not in order");

        RaiseEvent(new OrderItemRemovedEvent(Id, productId));
    }

    public void Submit()
    {
        if (Status != OrderStatus.Draft)
            throw new InvalidOperationException("Order already submitted");

        if (!Items.Any())
            throw new InvalidOperationException("Cannot submit empty order");

        RaiseEvent(new OrderSubmittedEvent(Id, DateTime.UtcNow));
    }

    public void MarkPaid(decimal amount, string paymentReference)
    {
        if (Status != OrderStatus.Submitted)
            throw new InvalidOperationException("Order not awaiting payment");

        if (amount != Total)
            throw new InvalidOperationException("Payment amount mismatch");

        RaiseEvent(new OrderPaidEvent(Id, amount, paymentReference));
    }

    public void Ship(string trackingNumber)
    {
        if (Status != OrderStatus.Paid)
            throw new InvalidOperationException("Order not ready for shipping");

        RaiseEvent(new OrderShippedEvent(Id, trackingNumber, DateTime.UtcNow));
    }

    public void Cancel(string reason)
    {
        if (Status == OrderStatus.Shipped)
            throw new InvalidOperationException("Cannot cancel shipped order");

        RaiseEvent(new OrderCancelledEvent(Id, reason));
    }

    protected override void ApplyEvent(IEvent @event)
    {
        switch (@event)
        {
            case OrderCreatedEvent e:
                Id = e.OrderId;
                CustomerId = e.CustomerId;
                Status = OrderStatus.Draft;
                break;

            case OrderItemAddedEvent e:
                Items.Add(new OrderItem(e.ProductId, e.ProductName, e.Quantity, e.Price));
                break;

            case OrderItemRemovedEvent e:
                Items.RemoveAll(i => i.ProductId == e.ProductId);
                break;

            case OrderSubmittedEvent:
                Status = OrderStatus.Submitted;
                break;

            case OrderPaidEvent:
                Status = OrderStatus.Paid;
                break;

            case OrderShippedEvent e:
                Status = OrderStatus.Shipped;
                TrackingNumber = e.TrackingNumber;
                break;

            case OrderCancelledEvent:
                Status = OrderStatus.Cancelled;
                break;
        }
    }
}

public enum OrderStatus { Draft, Submitted, Paid, Shipped, Cancelled }
public record OrderItem(Guid ProductId, string ProductName, int Quantity, decimal Price);
```

### Repository

```csharp
public interface IRepository<T> where T : AggregateRoot
{
    Task<T?> LoadAsync(Guid id, CancellationToken ct = default);
    Task SaveAsync(T aggregate, CancellationToken ct = default);
}

public class EventSourcedRepository<T> : IRepository<T> where T : AggregateRoot
{
    private readonly IEventStore _eventStore;
    private readonly RxMessageBus _bus;
    private readonly string _streamType;

    public EventSourcedRepository(IEventStore eventStore, RxMessageBus bus)
    {
        _eventStore = eventStore;
        _bus = bus;
        _streamType = typeof(T).Name;
    }

    public async Task<T?> LoadAsync(Guid id, CancellationToken ct = default)
    {
        var storedEvents = await _eventStore.LoadAsync(id, 0, ct);

        if (storedEvents.Count == 0)
            return null;

        var events = storedEvents.Select(e => _eventStore.Deserialize(e));

        var aggregate = (T)Activator.CreateInstance(typeof(T), nonPublic: true)!;
        aggregate.Load(events);

        return aggregate;
    }

    public async Task SaveAsync(T aggregate, CancellationToken ct = default)
    {
        if (!aggregate.UncommittedEvents.Any())
            return;

        await _eventStore.AppendAsync(
            aggregate.Id,
            _streamType,
            aggregate.UncommittedEvents,
            aggregate.Version,
            ct);

        // Publish to message bus for projections
        foreach (var @event in aggregate.UncommittedEvents)
            _bus.Publish(@event);

        aggregate.MarkCommitted();
    }
}
```

### Command Handler with Event Sourcing

```csharp
public record AddOrderItemCommand(Guid OrderId, Guid ProductId, string ProductName, int Quantity, decimal Price) : ICommand;

public class AddOrderItemHandler : ICommandHandler<AddOrderItemCommand>
{
    private readonly IRepository<Order> _repository;

    public AddOrderItemHandler(IRepository<Order> repository) => _repository = repository;

    public async Task HandleAsync(AddOrderItemCommand cmd, CancellationToken ct)
    {
        var order = await _repository.LoadAsync(cmd.OrderId, ct)
            ?? throw new NotFoundException($"Order {cmd.OrderId} not found");

        order.AddItem(cmd.ProductId, cmd.ProductName, cmd.Quantity, cmd.Price);

        await _repository.SaveAsync(order, ct);
    }
}
```

### Projections with Rx

Subscribe to event store and build read models:

```csharp
public class OrderProjection : IHostedService
{
    private readonly IEventStore _eventStore;
    private readonly IServiceScopeFactory _scopeFactory;
    private IDisposable? _subscription;

    public OrderProjection(IEventStore eventStore, IServiceScopeFactory scopeFactory)
    {
        _eventStore = eventStore;
        _scopeFactory = scopeFactory;
    }

    public Task StartAsync(CancellationToken ct)
    {
        _subscription = _eventStore
            .Subscribe("Order")
            .Select(e => (stored: e, @event: _eventStore.Deserialize(e)))
            .SelectMany(x => ProjectAsync(x.stored, x.@event).ToObservable())
            .Retry()
            .Subscribe();

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken ct)
    {
        _subscription?.Dispose();
        return Task.CompletedTask;
    }

    private async Task ProjectAsync(StoredEvent stored, IEvent @event)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ReadDbContext>();

        switch (@event)
        {
            case OrderCreatedEvent e:
                db.OrderReadModels.Add(new OrderReadModel
                {
                    Id = e.OrderId,
                    CustomerId = e.CustomerId,
                    Status = "Draft",
                    Items = [],
                    Total = 0,
                    CreatedAt = e.CreatedAt,
                    LastEventVersion = stored.Version
                });
                break;

            case OrderItemAddedEvent e:
                var order = await db.OrderReadModels.FindAsync(e.OrderId);
                if (order is not null && stored.Version > order.LastEventVersion)
                {
                    order.Items.Add(new OrderItemReadModel(e.ProductId, e.ProductName, e.Quantity, e.Price));
                    order.Total = order.Items.Sum(i => i.Quantity * i.Price);
                    order.LastEventVersion = stored.Version;
                }
                break;

            case OrderSubmittedEvent e:
                await db.OrderReadModels
                    .Where(o => o.Id == e.OrderId)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(o => o.Status, "Submitted")
                        .SetProperty(o => o.LastEventVersion, stored.Version));
                break;

            case OrderShippedEvent e:
                await db.OrderReadModels
                    .Where(o => o.Id == e.OrderId)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(o => o.Status, "Shipped")
                        .SetProperty(o => o.TrackingNumber, e.TrackingNumber)
                        .SetProperty(o => o.LastEventVersion, stored.Version));
                break;
        }

        await db.SaveChangesAsync();
    }
}
```

### Snapshots

For aggregates with many events, periodically save snapshots:

```csharp
public interface ISnapshotStore
{
    Task<(T? Snapshot, int Version)> LoadAsync<T>(Guid streamId, CancellationToken ct = default);
    Task SaveAsync<T>(Guid streamId, T snapshot, int version, CancellationToken ct = default);
}

public class SnapshottingRepository<T> : IRepository<T> where T : AggregateRoot
{
    private readonly IEventStore _eventStore;
    private readonly ISnapshotStore _snapshotStore;
    private readonly RxMessageBus _bus;
    private readonly int _snapshotInterval;

    public SnapshottingRepository(
        IEventStore eventStore,
        ISnapshotStore snapshotStore,
        RxMessageBus bus,
        int snapshotInterval = 50)
    {
        _eventStore = eventStore;
        _snapshotStore = snapshotStore;
        _bus = bus;
        _snapshotInterval = snapshotInterval;
    }

    public async Task<T?> LoadAsync(Guid id, CancellationToken ct = default)
    {
        // Try load snapshot first
        var (snapshot, snapshotVersion) = await _snapshotStore.LoadAsync<T>(id, ct);

        // Load events after snapshot
        var storedEvents = await _eventStore.LoadAsync(id, snapshotVersion, ct);

        if (snapshot is null && storedEvents.Count == 0)
            return null;

        var aggregate = snapshot ?? (T)Activator.CreateInstance(typeof(T), nonPublic: true)!;

        if (snapshot is not null)
        {
            // Set version from snapshot
            typeof(AggregateRoot)
                .GetProperty(nameof(AggregateRoot.Version))!
                .SetValue(aggregate, snapshotVersion);
        }

        var events = storedEvents.Select(e => _eventStore.Deserialize(e));
        aggregate.Load(events);

        return aggregate;
    }

    public async Task SaveAsync(T aggregate, CancellationToken ct = default)
    {
        if (!aggregate.UncommittedEvents.Any())
            return;

        await _eventStore.AppendAsync(
            aggregate.Id,
            typeof(T).Name,
            aggregate.UncommittedEvents,
            aggregate.Version,
            ct);

        foreach (var @event in aggregate.UncommittedEvents)
            _bus.Publish(@event);

        var newVersion = aggregate.Version + aggregate.UncommittedEvents.Count;
        aggregate.MarkCommitted();

        // Save snapshot if interval reached
        if (newVersion % _snapshotInterval == 0)
        {
            await _snapshotStore.SaveAsync(aggregate.Id, aggregate, newVersion, ct);
        }
    }
}
```

### Temporal Queries

Query state at a point in time:

```csharp
public class TemporalQueryService
{
    private readonly IEventStore _eventStore;

    public async Task<T?> LoadAtAsync<T>(Guid id, DateTime pointInTime, CancellationToken ct = default)
        where T : AggregateRoot
    {
        var storedEvents = await _eventStore.LoadAsync(id, 0, ct);

        var eventsUntil = storedEvents
            .Where(e => e.Timestamp <= pointInTime)
            .Select(e => _eventStore.Deserialize(e));

        if (!eventsUntil.Any())
            return null;

        var aggregate = (T)Activator.CreateInstance(typeof(T), nonPublic: true)!;
        aggregate.Load(eventsUntil);

        return aggregate;
    }

    public async Task<List<IEvent>> GetHistoryAsync(Guid id, CancellationToken ct = default)
    {
        var storedEvents = await _eventStore.LoadAsync(id, 0, ct);
        return storedEvents.Select(e => _eventStore.Deserialize(e)).ToList();
    }
}

// Usage: "What was this order's state last Tuesday?"
var orderLastTuesday = await _temporal.LoadAtAsync<Order>(orderId, lastTuesday);
```

### Rebuilding Projections

When you need to fix or add a projection, replay all events:

```csharp
public class ProjectionRebuilder
{
    private readonly EventStoreDbContext _eventDb;
    private readonly IServiceScopeFactory _scopeFactory;

    public async Task RebuildAsync<TProjection>(CancellationToken ct = default)
        where TProjection : IProjection
    {
        using var scope = _scopeFactory.CreateScope();
        var readDb = scope.ServiceProvider.GetRequiredService<ReadDbContext>();
        var projection = scope.ServiceProvider.GetRequiredService<TProjection>();

        // Clear existing read model
        await projection.ClearAsync(readDb, ct);

        // Replay all events
        var events = _eventDb.Events
            .OrderBy(e => e.SequenceNumber)
            .AsAsyncEnumerable();

        await foreach (var stored in events.WithCancellation(ct))
        {
            await projection.ApplyAsync(readDb, stored, ct);
        }

        await readDb.SaveChangesAsync(ct);
    }
}

public interface IProjection
{
    Task ClearAsync(ReadDbContext db, CancellationToken ct);
    Task ApplyAsync(ReadDbContext db, StoredEvent @event, CancellationToken ct);
}
```

## Testing

```csharp
[Fact]
public async Task Pipeline_retries_on_failure()
{
    var scheduler = new TestScheduler();
    var attempts = 0;

    var source = scheduler.CreateColdObservable(
        OnNext(100, new TestCommand()));

    source
        .SelectMany(_ => ++attempts < 3
            ? Observable.Throw<Unit>(new Exception())
            : Observable.Return(Unit.Default))
        .WithRetry(3, TimeSpan.FromTicks(50), scheduler)
        .Subscribe();

    scheduler.AdvanceBy(1000);

    Assert.Equal(3, attempts);
}
```
