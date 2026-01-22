# Software Architecture Patterns

## Vertical Slice Architecture

Organize by feature, not layer. Each slice contains everything for one use case.

```
Features/
├── CreateOrder/
│   ├── CreateOrderCommand.cs
│   ├── CreateOrderHandler.cs
│   ├── CreateOrderValidator.cs
│   └── CreateOrderEndpoint.cs
├── GetOrder/
│   ├── GetOrderQuery.cs
│   └── GetOrderHandler.cs
├── CancelOrder/
│   ├── CancelOrderCommand.cs
│   ├── CancelOrderHandler.cs
│   └── CancelOrderEndpoint.cs
```

**Pros:**
- Low coupling between features
- Easy to understand one feature in isolation
- Natural fit for CQRS
- Changes to one feature don't affect others
- Easy to delete a feature entirely

**Cons:**
- Can lead to duplication across slices
- Shared concerns need careful handling
- Less obvious where cross-cutting code lives

**When to use:**
- CQRS-based systems
- Teams organized by feature
- Microservice extraction candidates

---

## Hexagonal Architecture (Ports & Adapters)

Domain at the center, isolated from infrastructure. Ports define interfaces, adapters implement them.

```
         [HTTP Adapter]  [CLI Adapter]  [gRPC Adapter]
               ↓              ↓              ↓
            ┌─────────────────────────────────┐
            │       Input Ports (interfaces)  │
            ├─────────────────────────────────┤
            │                                 │
            │          Domain Core            │
            │    (entities, business logic)   │
            │                                 │
            ├─────────────────────────────────┤
            │      Output Ports (interfaces)  │
            └─────────────────────────────────┘
               ↓              ↓              ↓
         [DB Adapter]  [Email Adapter]  [Queue Adapter]
```

### Ports

Interfaces defined by the domain:

```csharp
// Input port (driving) - how outside world calls us
public interface IOrderService
{
    Task<Guid> CreateOrderAsync(CreateOrderRequest request);
    Task CancelOrderAsync(Guid orderId);
}

// Output port (driven) - how we call outside world
public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(Guid id);
    Task SaveAsync(Order order);
}

public interface IPaymentGateway
{
    Task<PaymentResult> ChargeAsync(Guid customerId, decimal amount);
}
```

### Adapters

Implementations that connect to real infrastructure:

```csharp
// Input adapter (driving)
[ApiController]
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orderService; // input port

    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest request)
    {
        var id = await _orderService.CreateOrderAsync(request);
        return Created($"/orders/{id}", new { id });
    }
}

// Output adapter (driven)
public class PostgresOrderRepository : IOrderRepository
{
    private readonly DbContext _db;

    public async Task<Order?> GetByIdAsync(Guid id) =>
        await _db.Orders.FindAsync(id);

    public async Task SaveAsync(Order order)
    {
        _db.Orders.Update(order);
        await _db.SaveChangesAsync();
    }
}

public class StripePaymentGateway : IPaymentGateway
{
    public async Task<PaymentResult> ChargeAsync(Guid customerId, decimal amount)
    {
        // Stripe API calls
    }
}
```

**Pros:**
- Domain has zero external dependencies
- Easy to swap infrastructure (swap Postgres for Mongo)
- Highly testable (mock ports)
- Clear boundaries

**Cons:**
- More indirection
- Can feel over-engineered for simple apps
- Lots of interfaces

**When to use:**
- Long-lived applications
- Infrastructure likely to change
- Multiple entry points (API, CLI, queue consumers)

---

## Clean Architecture

Layers with strict dependency rule: outer layers depend on inner, never reverse.

```
┌─────────────────────────────────────────────────────────┐
│              Frameworks & Drivers                       │
│         (DB, Web Framework, External APIs)              │
├─────────────────────────────────────────────────────────┤
│              Interface Adapters                         │
│      (Controllers, Gateways, Presenters, Repos)         │
├─────────────────────────────────────────────────────────┤
│              Application (Use Cases)                    │
│         (Application-specific business rules)           │
├─────────────────────────────────────────────────────────┤
│              Entities (Domain)                          │
│          (Enterprise-wide business rules)               │
└─────────────────────────────────────────────────────────┘
              ↑ dependencies point inward ↑
```

### Project Structure

```
Solution/
├── Domain/                    # Entities, value objects, domain events
│   ├── Entities/
│   ├── ValueObjects/
│   └── Events/
├── Application/               # Use cases, interfaces, DTOs
│   ├── UseCases/
│   │   ├── CreateOrder/
│   │   └── GetOrder/
│   ├── Interfaces/            # Repository interfaces, service interfaces
│   └── DTOs/
├── Infrastructure/            # Implementations
│   ├── Persistence/
│   ├── ExternalServices/
│   └── Messaging/
└── Presentation/              # Controllers, API
    ├── Controllers/
    └── Middleware/
```

### Dependency Rule

```csharp
// Domain - no dependencies
public class Order
{
    public Guid Id { get; }
    public List<OrderItem> Items { get; }
    public decimal Total => Items.Sum(i => i.Price * i.Quantity);
}

// Application - depends only on Domain
public class CreateOrderUseCase
{
    private readonly IOrderRepository _repo;  // interface defined in Application
    private readonly IPaymentService _payment;

    public async Task<Guid> ExecuteAsync(CreateOrderCommand cmd)
    {
        var order = new Order(cmd.CustomerId, cmd.Items);
        await _payment.ChargeAsync(order.CustomerId, order.Total);
        await _repo.SaveAsync(order);
        return order.Id;
    }
}

// Infrastructure - depends on Application (implements its interfaces)
public class SqlOrderRepository : IOrderRepository { }

// Presentation - depends on Application (calls use cases)
public class OrdersController
{
    private readonly CreateOrderUseCase _createOrder;
}
```

**Pros:**
- Clear boundaries and dependencies
- Testable at every layer
- Framework-agnostic core
- Forces thinking about dependencies

**Cons:**
- Lots of mapping between layers
- Verbose for small projects
- Can lead to over-abstraction

**When to use:**
- Large, complex domains
- Long-lived enterprise applications
- Multiple teams working on different layers

---

## Onion Architecture

Predecessor to Clean Architecture (Jeffrey Palermo, 2008). Nearly identical concept.

```
┌─────────────────────────────────────────────────────────┐
│                    Infrastructure                       │
│              (UI, DB, External Services)                │
├─────────────────────────────────────────────────────────┤
│                 Application Services                    │
│                 (Use case orchestration)                │
├─────────────────────────────────────────────────────────┤
│                   Domain Services                       │
│              (Domain logic using entities)              │
├─────────────────────────────────────────────────────────┤
│                    Domain Model                         │
│              (Entities, Value Objects)                  │
└─────────────────────────────────────────────────────────┘
```

### Clean vs Onion

| Aspect | Onion | Clean |
|--------|-------|-------|
| Innermost | Domain Model | Entities |
| Second layer | Domain Services | Use Cases |
| Third layer | Application Services | Interface Adapters |
| Outermost | Infrastructure | Frameworks & Drivers |
| Emphasis | Domain services | Use cases as first-class |
| Prescriptiveness | Less explicit | More explicit boundaries |

**In practice:** Terms used interchangeably. Same fundamental structure—dependencies point inward, domain has no external dependencies.

---

## Comparison

| Architecture | Organizes by | Key idea | Best for |
|--------------|--------------|----------|----------|
| Vertical Slice | Feature/use case | Minimize cross-feature coupling | CQRS, feature teams |
| Hexagonal | Ports/adapters | Domain isolated via interfaces | Swappable infrastructure |
| Clean | Concentric layers | Dependencies point inward only | Large enterprise apps |
| Onion | Concentric layers | Domain at center | Same as Clean |

---

## Combining Architectures

These aren't mutually exclusive. Common combinations:

### Vertical Slices + Clean

```
Features/
├── CreateOrder/
│   ├── CreateOrderCommand.cs      # Application layer
│   ├── CreateOrderHandler.cs      # Application layer
│   ├── CreateOrderValidator.cs    # Application layer
│   └── CreateOrderEndpoint.cs     # Presentation layer
Domain/
├── Order.cs                       # Domain layer
Infrastructure/
├── OrderRepository.cs             # Infrastructure layer
```

### Hexagonal + CQRS

```
Domain/
├── Order.cs
Ports/
├── Input/
│   ├── ICommandHandler.cs
│   └── IQueryHandler.cs
├── Output/
│   ├── IOrderRepository.cs
│   └── IEventPublisher.cs
Adapters/
├── Input/
│   ├── Http/
│   └── Grpc/
├── Output/
│   ├── Postgres/
│   └── RabbitMq/
```

### Modular Monolith with Clean per Module

```
Modules/
├── Orders/
│   ├── Orders.Domain/
│   ├── Orders.Application/
│   ├── Orders.Infrastructure/
│   └── Orders.Api/
├── Inventory/
│   ├── Inventory.Domain/
│   ├── Inventory.Application/
│   ├── Inventory.Infrastructure/
│   └── Inventory.Api/
SharedKernel/
├── Domain/
└── Infrastructure/
```

---

## Decision Guide

**Start with Vertical Slices if:**
- Greenfield project
- Using CQRS
- Want fast feature delivery
- Team organized by feature

**Add Hexagonal patterns if:**
- Multiple entry points (API, CLI, workers)
- Infrastructure likely to change
- Need high testability

**Go full Clean/Onion if:**
- Complex domain logic
- Large team needs clear boundaries
- Long-term enterprise application
- Regulatory/audit requirements

**Keep it simple if:**
- Small app or prototype
- Short-lived project
- Solo developer
- Simple CRUD with little domain logic
