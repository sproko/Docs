# Dependency Injection & Composition Roots for Modular Monoliths

## MS DI vs Autofac

| Feature | MS DI | Autofac |
|---------|-------|---------|
| Built-in to ASP.NET Core | Yes | No (add package) |
| Performance | Fastest | Very fast |
| Module isolation | Manual (extension methods) | Native `Module` class |
| Assembly scanning | Basic | Powerful, filtered |
| Decorators | Manual wrapping | `RegisterDecorator` |
| Interceptors (AOP) | No | Yes |
| Child scopes | Limited | Full control |
| Conditional registration | Manual | Built-in predicates |
| Property injection | No | Yes |
| Multi-tenant | Manual | Native support |

**Recommendation:** Use Autofac for modular monoliths. MS DI for simple apps.

---

## MS DI Approach (Extension Methods)

Fake module isolation with extension methods:

```csharp
// Orders/OrdersModule.cs
public static class OrdersModule
{
    public static IServiceCollection AddOrdersModule(
        this IServiceCollection services,
        IConfiguration config)
    {
        services.Configure<OrdersOptions>(config.GetSection("Orders"));

        services.AddScoped<IOrderService, OrderService>();
        services.AddScoped<IOrderRepository, SqlOrderRepository>();

        // Register all handlers by convention
        services.Scan(scan => scan
            .FromAssemblyOf<CreateOrderHandler>()
            .AddClasses(c => c.AssignableTo(typeof(ICommandHandler<>)))
            .AsImplementedInterfaces()
            .WithScopedLifetime());

        return services;
    }
}

// Inventory/InventoryModule.cs
public static class InventoryModule
{
    public static IServiceCollection AddInventoryModule(
        this IServiceCollection services,
        IConfiguration config)
    {
        services.AddScoped<IInventoryService, InventoryService>();
        services.AddScoped<IInventoryRepository, SqlInventoryRepository>();
        return services;
    }
}

// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOrdersModule(builder.Configuration);
builder.Services.AddInventoryModule(builder.Configuration);
builder.Services.AddShippingModule(builder.Configuration);

var app = builder.Build();
```

### MS DI Manual Decorators

```csharp
// No built-in decorator support, must wrap manually
public static IServiceCollection AddOrdersModule(this IServiceCollection services)
{
    // Register base implementation
    services.AddScoped<OrderService>();

    // Wrap with decorator
    services.AddScoped<IOrderService>(sp =>
    {
        var inner = sp.GetRequiredService<OrderService>();
        var logger = sp.GetRequiredService<ILogger<LoggingOrderService>>();
        return new LoggingOrderService(inner, logger);
    });

    return services;
}

// Or use Scrutor for decoration
services.AddScoped<IOrderService, OrderService>();
services.Decorate<IOrderService, LoggingOrderService>();
services.Decorate<IOrderService, ValidationOrderService>();
```

---

## Autofac Module Approach

### Setup

```xml
<!-- Host.csproj -->
<PackageReference Include="Autofac" Version="8.0.0" />
<PackageReference Include="Autofac.Extensions.DependencyInjection" Version="9.0.0" />
```

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());

builder.Host.ConfigureContainer<ContainerBuilder>(container =>
{
    container.RegisterModule<SharedModule>();
    container.RegisterModule<OrdersModule>();
    container.RegisterModule<InventoryModule>();
    container.RegisterModule<ShippingModule>();
});

var app = builder.Build();
```

### Module Definition

```csharp
// Orders/OrdersModule.cs
public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Single registrations
        builder.RegisterType<OrderService>()
            .As<IOrderService>()
            .InstancePerLifetimeScope();

        builder.RegisterType<SqlOrderRepository>()
            .As<IOrderRepository>()
            .InstancePerLifetimeScope();

        // Assembly scanning
        var assembly = typeof(OrdersModule).Assembly;

        // Register all handlers
        builder.RegisterAssemblyTypes(assembly)
            .Where(t => t.Name.EndsWith("Handler"))
            .AsImplementedInterfaces()
            .InstancePerLifetimeScope();

        // Register all validators
        builder.RegisterAssemblyTypes(assembly)
            .Where(t => t.Name.EndsWith("Validator"))
            .AsImplementedInterfaces()
            .InstancePerLifetimeScope();
    }
}
```

### Module with Configuration

```csharp
public class OrdersModule : Module
{
    private readonly IConfiguration _configuration;

    public OrdersModule(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    protected override void Load(ContainerBuilder builder)
    {
        // Register options
        var options = _configuration.GetSection("Orders").Get<OrdersOptions>()
            ?? new OrdersOptions();

        builder.RegisterInstance(Options.Create(options))
            .As<IOptions<OrdersOptions>>();

        // Conditional registration based on config
        if (options.UseInMemoryRepository)
        {
            builder.RegisterType<InMemoryOrderRepository>()
                .As<IOrderRepository>()
                .SingleInstance();
        }
        else
        {
            builder.RegisterType<SqlOrderRepository>()
                .As<IOrderRepository>()
                .InstancePerLifetimeScope();
        }
    }
}

// Program.cs
builder.Host.ConfigureContainer<ContainerBuilder>((context, container) =>
{
    container.RegisterModule(new OrdersModule(context.Configuration));
});
```

---

## Assembly Scanning Patterns

### Basic Scanning

```csharp
protected override void Load(ContainerBuilder builder)
{
    var assembly = typeof(OrdersModule).Assembly;

    // All types ending with "Service"
    builder.RegisterAssemblyTypes(assembly)
        .Where(t => t.Name.EndsWith("Service"))
        .AsImplementedInterfaces();

    // All types implementing specific interface
    builder.RegisterAssemblyTypes(assembly)
        .AssignableTo<ICommandHandler>()
        .AsImplementedInterfaces();
}
```

### Generic Interface Scanning

```csharp
// Register all ICommandHandler<T> implementations
builder.RegisterAssemblyTypes(assembly)
    .AsClosedTypesOf(typeof(ICommandHandler<>))
    .InstancePerLifetimeScope();

// Register all IQueryHandler<TQuery, TResult> implementations
builder.RegisterAssemblyTypes(assembly)
    .AsClosedTypesOf(typeof(IQueryHandler<,>))
    .InstancePerLifetimeScope();
```

### Multiple Assemblies

```csharp
protected override void Load(ContainerBuilder builder)
{
    var assemblies = new[]
    {
        typeof(OrdersModule).Assembly,        // Orders.Core
        typeof(OrderRepository).Assembly,     // Orders.Infrastructure
    };

    builder.RegisterAssemblyTypes(assemblies)
        .Where(t => t.Name.EndsWith("Handler"))
        .AsImplementedInterfaces()
        .InstancePerLifetimeScope();
}
```

### Exclude Specific Types

```csharp
builder.RegisterAssemblyTypes(assembly)
    .Where(t => t.Name.EndsWith("Service"))
    .Except<LegacyService>()                    // Skip specific type
    .Where(t => !t.IsAbstract)                  // Skip abstract
    .Where(t => t.IsPublic)                     // Only public
    .AsImplementedInterfaces();
```

---

## Decorators

### Basic Decorator Chain

```csharp
public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Base implementation
        builder.RegisterType<OrderService>()
            .As<IOrderService>()
            .InstancePerLifetimeScope();

        // Decorators applied in registration order (bottom up)
        builder.RegisterDecorator<ValidationOrderService, IOrderService>();
        builder.RegisterDecorator<LoggingOrderService, IOrderService>();
        builder.RegisterDecorator<CachingOrderService, IOrderService>();

        // Call chain: Caching -> Logging -> Validation -> OrderService
    }
}
```

### Decorator Implementations

```csharp
public class LoggingOrderService : IOrderService
{
    private readonly IOrderService _inner;
    private readonly ILogger<LoggingOrderService> _logger;

    public LoggingOrderService(IOrderService inner, ILogger<LoggingOrderService> logger)
    {
        _inner = inner;
        _logger = logger;
    }

    public async Task<Guid> CreateOrderAsync(CreateOrderCommand cmd, CancellationToken ct)
    {
        _logger.LogInformation("Creating order for customer {CustomerId}", cmd.CustomerId);
        var sw = Stopwatch.StartNew();

        try
        {
            var result = await _inner.CreateOrderAsync(cmd, ct);
            _logger.LogInformation("Created order {OrderId} in {Elapsed}ms", result, sw.ElapsedMilliseconds);
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create order for customer {CustomerId}", cmd.CustomerId);
            throw;
        }
    }
}

public class ValidationOrderService : IOrderService
{
    private readonly IOrderService _inner;
    private readonly IValidator<CreateOrderCommand> _validator;

    public ValidationOrderService(IOrderService inner, IValidator<CreateOrderCommand> validator)
    {
        _inner = inner;
        _validator = validator;
    }

    public async Task<Guid> CreateOrderAsync(CreateOrderCommand cmd, CancellationToken ct)
    {
        var result = await _validator.ValidateAsync(cmd, ct);
        if (!result.IsValid)
            throw new ValidationException(result.Errors);

        return await _inner.CreateOrderAsync(cmd, ct);
    }
}
```

### Conditional Decorators

```csharp
// Only decorate in production
builder.RegisterDecorator<CachingOrderService, IOrderService>(
    context => !context.Resolve<IHostEnvironment>().IsDevelopment());

// Decorate based on resolved type
builder.RegisterDecorator<AuditingOrderService, IOrderService>(
    (context, parameters, instance) => instance is SqlOrderService);
```

### Open Generic Decorators

```csharp
// Decorate all command handlers
builder.RegisterGenericDecorator(
    typeof(LoggingCommandHandler<>),
    typeof(ICommandHandler<>));

builder.RegisterGenericDecorator(
    typeof(ValidationCommandHandler<>),
    typeof(ICommandHandler<>));

// Implementation
public class LoggingCommandHandler<TCommand> : ICommandHandler<TCommand>
    where TCommand : ICommand
{
    private readonly ICommandHandler<TCommand> _inner;
    private readonly ILogger<LoggingCommandHandler<TCommand>> _logger;

    public LoggingCommandHandler(
        ICommandHandler<TCommand> inner,
        ILogger<LoggingCommandHandler<TCommand>> logger)
    {
        _inner = inner;
        _logger = logger;
    }

    public async Task HandleAsync(TCommand command, CancellationToken ct)
    {
        _logger.LogInformation("Handling {CommandType}", typeof(TCommand).Name);
        await _inner.HandleAsync(command, ct);
        _logger.LogInformation("Handled {CommandType}", typeof(TCommand).Name);
    }
}
```

---

## Interceptors (AOP)

### Setup

```xml
<PackageReference Include="Autofac.Extras.DynamicProxy" Version="7.1.0" />
<PackageReference Include="Castle.Core" Version="5.1.1" />
```

### Interceptor Implementation

```csharp
public class LoggingInterceptor : IInterceptor
{
    private readonly ILogger<LoggingInterceptor> _logger;

    public LoggingInterceptor(ILogger<LoggingInterceptor> logger)
    {
        _logger = logger;
    }

    public void Intercept(IInvocation invocation)
    {
        _logger.LogDebug("Calling {Method} with args {@Args}",
            invocation.Method.Name,
            invocation.Arguments);

        var sw = Stopwatch.StartNew();

        try
        {
            invocation.Proceed();

            // Handle async methods
            if (invocation.ReturnValue is Task task)
            {
                task.ContinueWith(t =>
                {
                    if (t.IsFaulted)
                        _logger.LogError(t.Exception, "{Method} failed", invocation.Method.Name);
                    else
                        _logger.LogDebug("{Method} completed in {Elapsed}ms",
                            invocation.Method.Name, sw.ElapsedMilliseconds);
                });
            }
            else
            {
                _logger.LogDebug("{Method} completed in {Elapsed}ms",
                    invocation.Method.Name, sw.ElapsedMilliseconds);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "{Method} threw exception", invocation.Method.Name);
            throw;
        }
    }
}

public class TransactionInterceptor : IInterceptor
{
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    public TransactionInterceptor(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    public void Intercept(IInvocation invocation)
    {
        using var db = _dbFactory.CreateDbContext();
        using var tx = db.Database.BeginTransaction();

        try
        {
            invocation.Proceed();

            if (invocation.ReturnValue is Task task)
            {
                task.ContinueWith(t =>
                {
                    if (t.IsCompletedSuccessfully)
                        tx.Commit();
                    else
                        tx.Rollback();
                }).Wait();
            }
            else
            {
                tx.Commit();
            }
        }
        catch
        {
            tx.Rollback();
            throw;
        }
    }
}
```

### Registering Interceptors

```csharp
public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Register interceptors
        builder.RegisterType<LoggingInterceptor>();
        builder.RegisterType<TransactionInterceptor>();

        // Apply to specific type
        builder.RegisterType<OrderService>()
            .As<IOrderService>()
            .EnableInterfaceInterceptors()
            .InterceptedBy(typeof(LoggingInterceptor))
            .InterceptedBy(typeof(TransactionInterceptor));

        // Apply to all handlers via scanning
        builder.RegisterAssemblyTypes(ThisAssembly)
            .Where(t => t.Name.EndsWith("Handler"))
            .AsImplementedInterfaces()
            .EnableInterfaceInterceptors()
            .InterceptedBy(typeof(LoggingInterceptor));
    }
}
```

### Attribute-Based Interception

```csharp
[AttributeUsage(AttributeTargets.Method)]
public class TransactionalAttribute : Attribute { }

public class AttributeBasedTransactionInterceptor : IInterceptor
{
    public void Intercept(IInvocation invocation)
    {
        var hasAttribute = invocation.Method
            .GetCustomAttributes(typeof(TransactionalAttribute), true)
            .Any();

        if (!hasAttribute)
        {
            invocation.Proceed();
            return;
        }

        // Wrap in transaction
        using var tx = BeginTransaction();
        try
        {
            invocation.Proceed();
            tx.Commit();
        }
        catch
        {
            tx.Rollback();
            throw;
        }
    }
}

// Usage
public class OrderService : IOrderService
{
    [Transactional]
    public virtual async Task<Guid> CreateOrderAsync(CreateOrderCommand cmd, CancellationToken ct)
    {
        // Method body
    }
}
```

---

## Module Dependencies

### Module Loading Order

```csharp
public class SharedModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<MessageBus>().As<IMessageBus>().SingleInstance();
        builder.RegisterType<EventStore>().As<IEventStore>().SingleInstance();
    }
}

public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Depends on SharedModule being loaded first
        builder.RegisterType<OrderService>().As<IOrderService>();
    }
}

// Program.cs - order matters!
container.RegisterModule<SharedModule>();      // First
container.RegisterModule<OrdersModule>();      // Depends on Shared
container.RegisterModule<InventoryModule>();   // Depends on Shared, may use Orders.Contracts
```

### Explicit Module Dependencies

```csharp
public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Explicitly load dependencies
        builder.RegisterModule<SharedModule>();

        // Then register own types
        builder.RegisterType<OrderService>().As<IOrderService>();
    }
}

// Autofac handles duplicate module registration gracefully
// SharedModule only loaded once even if multiple modules request it
```

### Cross-Module Communication via Contracts

```csharp
// Inventory needs to call Orders - only depends on Contracts
public class InventoryModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Register own types
        builder.RegisterType<InventoryService>().As<IInventoryService>();

        // DON'T register Orders types - they're in OrdersModule
        // Just depend on IOrderService being available (from Orders.Contracts)
    }
}

public class InventoryService : IInventoryService
{
    // Injected from OrdersModule registration
    // InventoryModule only knows about IOrderService interface (from Contracts)
    private readonly IOrderService _orderService;

    public InventoryService(IOrderService orderService)
    {
        _orderService = orderService;
    }
}
```

---

## Multi-Tenant / Customer-Specific Composition

### Tenant-Based Module Loading

```csharp
// Program.cs
builder.Host.ConfigureContainer<ContainerBuilder>((context, container) =>
{
    // Base modules for all tenants
    container.RegisterModule<SharedModule>();
    container.RegisterModule<OrdersModule>();
    container.RegisterModule<InventoryModule>();

    // Load tenant-specific overrides
    var tenantModules = LoadTenantModules(context.Configuration);
    foreach (var module in tenantModules)
    {
        container.RegisterModule(module);
    }
});

private static IEnumerable<Module> LoadTenantModules(IConfiguration config)
{
    var tenant = config["TenantId"];

    return tenant switch
    {
        "acme" => [new AcmeCustomizationsModule()],
        "bigcorp" => [new BigCorpCustomizationsModule(), new BigCorpReportingModule()],
        _ => []
    };
}
```

### Customer Override Module

```csharp
public class AcmeCustomizationsModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Override default order service with ACME-specific logic
        builder.RegisterType<AcmeOrderService>()
            .As<IOrderService>()
            .InstancePerLifetimeScope()
            .PreserveExistingDefaults(); // Or remove this to fully replace

        // Add ACME-specific services
        builder.RegisterType<AcmeLegacyIntegration>()
            .As<IAcmeLegacyIntegration>()
            .SingleInstance();

        // ACME-specific decorator
        builder.RegisterDecorator<AcmeAuditingDecorator, IOrderService>();
    }
}
```

### Runtime Tenant Resolution

```csharp
public class MultiTenantModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Register tenant-specific factories
        builder.Register<IOrderRepository>(context =>
        {
            var tenantContext = context.Resolve<ITenantContext>();

            return tenantContext.TenantId switch
            {
                "acme" => new AcmeOrderRepository(/* ... */),
                "bigcorp" => new BigCorpOrderRepository(/* ... */),
                _ => new SqlOrderRepository(/* ... */)
            };
        }).InstancePerLifetimeScope();
    }
}
```

### Keyed Services (Per-Tenant)

```csharp
public class OrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Default
        builder.RegisterType<SqlOrderRepository>()
            .Keyed<IOrderRepository>("default");

        // ACME-specific
        builder.RegisterType<AcmeOrderRepository>()
            .Keyed<IOrderRepository>("acme");

        // BigCorp-specific
        builder.RegisterType<BigCorpOrderRepository>()
            .Keyed<IOrderRepository>("bigcorp");

        // Factory that resolves based on tenant
        builder.Register<IOrderRepository>(context =>
        {
            var tenant = context.Resolve<ITenantContext>().TenantId;
            return context.ResolveKeyed<IOrderRepository>(tenant)
                ?? context.ResolveKeyed<IOrderRepository>("default");
        }).InstancePerLifetimeScope();
    }
}
```

---

## Child Scopes / Lifetime Scopes

### Per-Request Scope (Default in ASP.NET Core)

```csharp
// InstancePerLifetimeScope = scoped to HTTP request
builder.RegisterType<OrderService>()
    .As<IOrderService>()
    .InstancePerLifetimeScope();
```

### Named Scopes

```csharp
// Register for specific named scope
builder.RegisterType<UnitOfWork>()
    .As<IUnitOfWork>()
    .InstancePerMatchingLifetimeScope("transaction");

// Create and use named scope
using (var scope = container.BeginLifetimeScope("transaction"))
{
    var uow = scope.Resolve<IUnitOfWork>();
    // All resolutions in this scope share same UnitOfWork
}
```

### Module-Specific Scopes

```csharp
public class OrdersModule : Module
{
    public const string ScopeName = "orders";

    protected override void Load(ContainerBuilder builder)
    {
        // Services scoped to Orders operations
        builder.RegisterType<OrderContext>()
            .InstancePerMatchingLifetimeScope(ScopeName);
    }
}

// Usage in handler
public class CreateOrderHandler : ICommandHandler<CreateOrderCommand>
{
    private readonly ILifetimeScope _scope;

    public async Task HandleAsync(CreateOrderCommand cmd, CancellationToken ct)
    {
        using var orderScope = _scope.BeginLifetimeScope(OrdersModule.ScopeName);

        var context = orderScope.Resolve<OrderContext>();
        // All operations share this context
    }
}
```

---

## Testing with Module Overrides

### Test Module

```csharp
public class TestOrdersModule : Module
{
    protected override void Load(ContainerBuilder builder)
    {
        // Load real module first
        builder.RegisterModule<OrdersModule>();

        // Override with test doubles
        builder.RegisterType<InMemoryOrderRepository>()
            .As<IOrderRepository>()
            .SingleInstance();

        builder.RegisterInstance(new FakeMessageBus())
            .As<IMessageBus>();
    }
}
```

### Integration Test Setup

```csharp
public class OrdersIntegrationTests : IDisposable
{
    private readonly IContainer _container;
    private readonly ILifetimeScope _scope;

    public OrdersIntegrationTests()
    {
        var builder = new ContainerBuilder();

        // Real modules
        builder.RegisterModule<SharedModule>();
        builder.RegisterModule<OrdersModule>();

        // Test overrides
        builder.RegisterType<InMemoryOrderRepository>()
            .As<IOrderRepository>()
            .SingleInstance();

        builder.RegisterInstance(Substitute.For<IMessageBus>())
            .As<IMessageBus>();

        _container = builder.Build();
        _scope = _container.BeginLifetimeScope();
    }

    [Fact]
    public async Task CreateOrder_ShouldPersistOrder()
    {
        var service = _scope.Resolve<IOrderService>();
        var repo = _scope.Resolve<IOrderRepository>();

        var orderId = await service.CreateOrderAsync(new CreateOrderCommand(...));

        var order = await repo.GetByIdAsync(orderId);
        Assert.NotNull(order);
    }

    public void Dispose()
    {
        _scope.Dispose();
        _container.Dispose();
    }
}
```

### WebApplicationFactory with Autofac

```csharp
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            // MS DI overrides if needed
        });

        builder.ConfigureContainer<ContainerBuilder>(container =>
        {
            // Autofac overrides
            container.RegisterType<InMemoryOrderRepository>()
                .As<IOrderRepository>()
                .SingleInstance();
        });
    }
}

public class ApiIntegrationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ApiIntegrationTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task PostOrder_ReturnsCreated()
    {
        var response = await _client.PostAsJsonAsync("/api/orders", new { ... });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }
}
```

---

## Module Registration Patterns

### Self-Registering Modules via Assembly Scanning

```csharp
// Program.cs - auto-discover all modules
builder.Host.ConfigureContainer<ContainerBuilder>(container =>
{
    var moduleAssemblies = Directory.GetFiles(AppContext.BaseDirectory, "*.dll")
        .Select(Assembly.LoadFrom)
        .Where(a => a.GetName().Name?.StartsWith("YourCompany.") == true);

    foreach (var assembly in moduleAssemblies)
    {
        var moduleTypes = assembly.GetTypes()
            .Where(t => typeof(Module).IsAssignableFrom(t) && !t.IsAbstract);

        foreach (var moduleType in moduleTypes)
        {
            container.RegisterModule((Module)Activator.CreateInstance(moduleType)!);
        }
    }
});
```

### Module Interface for Initialization

```csharp
public interface IModuleInitializer
{
    int Order { get; }  // Loading order
    void Initialize(ContainerBuilder builder);
    Task OnApplicationStartAsync(IServiceProvider services);
}

public class OrdersModuleInitializer : IModuleInitializer
{
    public int Order => 10;

    public void Initialize(ContainerBuilder builder)
    {
        builder.RegisterModule<OrdersModule>();
    }

    public async Task OnApplicationStartAsync(IServiceProvider services)
    {
        // Run migrations, seed data, etc.
        var db = services.GetRequiredService<OrdersDbContext>();
        await db.Database.MigrateAsync();
    }
}

// Program.cs
var initializers = DiscoverModuleInitializers()
    .OrderBy(i => i.Order)
    .ToList();

builder.Host.ConfigureContainer<ContainerBuilder>(container =>
{
    foreach (var initializer in initializers)
        initializer.Initialize(container);
});

var app = builder.Build();

// Run startup tasks
foreach (var initializer in initializers)
    await initializer.OnApplicationStartAsync(app.Services);
```

---

## Dynamic Module Loading (Plugin Architecture)

Host only references Contracts, discovers implementations at runtime.

### Project Structure

```
Solution/
├── src/
│   ├── Host/
│   │   ├── Host.csproj              # References ALL Contracts, NO Core/Infrastructure
│   │   └── Program.cs
│   │
│   ├── SharedKernel/
│   │   ├── SharedKernel.csproj
│   │   └── IModule.cs               # Base module interface
│   │
│   └── Modules/
│       ├── Orders/
│       │   ├── Orders.Contracts/    # Referenced by Host
│       │   │   ├── IOrderService.cs
│       │   │   ├── Commands/
│       │   │   └── Orders.Contracts.csproj
│       │   ├── Orders.Core/         # NOT referenced by Host - discovered at runtime
│       │   │   ├── OrdersModule.cs
│       │   │   ├── OrderService.cs
│       │   │   └── Orders.Core.csproj
│       │   └── Orders.Infrastructure/
│       │       └── Orders.Infrastructure.csproj
│       │
│       └── Inventory/
│           ├── Inventory.Contracts/ # Referenced by Host
│           ├── Inventory.Core/      # NOT referenced - discovered
│           └── Inventory.Infrastructure/
│
└── modules/                         # Output folder for module DLLs
    ├── Orders.Core.dll
    ├── Orders.Infrastructure.dll
    ├── Inventory.Core.dll
    └── Inventory.Infrastructure.dll
```

### Host Project References

```xml
<!-- Host.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <!-- Contracts only - NO Core/Infrastructure references -->
    <ProjectReference Include="..\SharedKernel\SharedKernel.csproj" />
    <ProjectReference Include="..\Modules\Orders\Orders.Contracts\Orders.Contracts.csproj" />
    <ProjectReference Include="..\Modules\Inventory\Inventory.Contracts\Inventory.Contracts.csproj" />
    <ProjectReference Include="..\Modules\Shipping\Shipping.Contracts\Shipping.Contracts.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Autofac" Version="8.0.0" />
    <PackageReference Include="Autofac.Extensions.DependencyInjection" Version="9.0.0" />
    <!-- MEF2 for discovery (optional) -->
    <PackageReference Include="System.Composition" Version="8.0.0" />
  </ItemGroup>
</Project>
```

### Base Module Interface

```csharp
// SharedKernel/IModule.cs
public interface IModule
{
    string Name { get; }
    void RegisterServices(ContainerBuilder builder, IConfiguration configuration);
}

// Optional: for modules that need startup/shutdown hooks
public interface IModuleLifecycle : IModule
{
    int LoadOrder { get; }
    Task OnStartAsync(IServiceProvider services, CancellationToken ct);
    Task OnStopAsync(IServiceProvider services, CancellationToken ct);
}
```

---

### Approach 1: Pure Autofac + Assembly Scanning

No MEF, just load assemblies and scan for IModule implementations.

```csharp
// Host/ModuleLoader.cs
public class ModuleLoader
{
    private readonly List<Assembly> _loadedAssemblies = [];
    private readonly List<IModule> _modules = [];

    public IReadOnlyList<IModule> Modules => _modules;

    public void DiscoverModules(string modulesPath, IConfiguration configuration)
    {
        var moduleFiles = Directory.GetFiles(modulesPath, "*.Core.dll")
            .Concat(Directory.GetFiles(modulesPath, "*.Infrastructure.dll"));

        foreach (var file in moduleFiles)
        {
            try
            {
                var assembly = Assembly.LoadFrom(file);
                _loadedAssemblies.Add(assembly);

                // Find IModule implementations
                var moduleTypes = assembly.GetTypes()
                    .Where(t => typeof(IModule).IsAssignableFrom(t)
                             && !t.IsAbstract
                             && !t.IsInterface);

                foreach (var moduleType in moduleTypes)
                {
                    var module = (IModule)Activator.CreateInstance(moduleType)!;
                    _modules.Add(module);
                    Console.WriteLine($"Discovered module: {module.Name}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to load {file}: {ex.Message}");
            }
        }

        // Sort by load order if IModuleLifecycle
        _modules.Sort((a, b) =>
        {
            var orderA = (a as IModuleLifecycle)?.LoadOrder ?? 100;
            var orderB = (b as IModuleLifecycle)?.LoadOrder ?? 100;
            return orderA.CompareTo(orderB);
        });
    }

    public void RegisterModules(ContainerBuilder builder, IConfiguration configuration)
    {
        foreach (var module in _modules)
        {
            module.RegisterServices(builder, configuration);
        }
    }

    public IReadOnlyList<Assembly> GetAssemblies() => _loadedAssemblies;
}

// Host/Program.cs
var builder = WebApplication.CreateBuilder(args);

var moduleLoader = new ModuleLoader();
moduleLoader.DiscoverModules(
    Path.Combine(AppContext.BaseDirectory, "modules"),
    builder.Configuration);

builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
builder.Host.ConfigureContainer<ContainerBuilder>(container =>
{
    // Register shared services
    container.RegisterModule<SharedModule>();

    // Register discovered modules
    moduleLoader.RegisterModules(container, builder.Configuration);
});

var app = builder.Build();

// Run startup hooks
foreach (var module in moduleLoader.Modules.OfType<IModuleLifecycle>())
{
    await module.OnStartAsync(app.Services, CancellationToken.None);
}

app.Run();
```

### Module Implementation

```csharp
// Orders.Core/OrdersModule.cs
public class OrdersModule : IModuleLifecycle
{
    public string Name => "Orders";
    public int LoadOrder => 10;

    public void RegisterServices(ContainerBuilder builder, IConfiguration configuration)
    {
        var assembly = typeof(OrdersModule).Assembly;

        // Register services
        builder.RegisterType<OrderService>()
            .As<IOrderService>()
            .InstancePerLifetimeScope();

        // Scan for handlers
        builder.RegisterAssemblyTypes(assembly)
            .AsClosedTypesOf(typeof(ICommandHandler<>))
            .InstancePerLifetimeScope();

        builder.RegisterAssemblyTypes(assembly)
            .AsClosedTypesOf(typeof(IQueryHandler<,>))
            .InstancePerLifetimeScope();
    }

    public async Task OnStartAsync(IServiceProvider services, CancellationToken ct)
    {
        // Run migrations, warm up caches, etc.
        var db = services.GetRequiredService<OrdersDbContext>();
        await db.Database.MigrateAsync(ct);
    }

    public Task OnStopAsync(IServiceProvider services, CancellationToken ct)
    {
        return Task.CompletedTask;
    }
}
```

---

### Approach 2: MEF (System.Composition) for Discovery

Use MEF attributes for cleaner discovery, then register in Autofac.

```csharp
// SharedKernel/IModule.cs
using System.Composition;

public interface IModule
{
    string Name { get; }
    void RegisterServices(ContainerBuilder builder, IConfiguration configuration);
}

// Metadata for discovery
public interface IModuleMetadata
{
    string Name { get; }
    int LoadOrder { get; }
}

// Attribute for modules
[MetadataAttribute]
[AttributeUsage(AttributeTargets.Class)]
public class ModuleAttribute : ExportAttribute, IModuleMetadata
{
    public string Name { get; }
    public int LoadOrder { get; }

    public ModuleAttribute(string name, int loadOrder = 100)
        : base(typeof(IModule))
    {
        Name = name;
        LoadOrder = loadOrder;
    }
}
```

```csharp
// Orders.Core/OrdersModule.cs
using System.Composition;

[Module("Orders", LoadOrder = 10)]
public class OrdersModule : IModule
{
    public string Name => "Orders";

    public void RegisterServices(ContainerBuilder builder, IConfiguration configuration)
    {
        builder.RegisterType<OrderService>().As<IOrderService>();
        // ...
    }
}
```

```csharp
// Host/MefModuleLoader.cs
using System.Composition;
using System.Composition.Hosting;

public class MefModuleLoader
{
    private CompositionHost? _container;
    private IEnumerable<Lazy<IModule, IModuleMetadata>> _modules = [];

    public void DiscoverModules(string modulesPath)
    {
        var assemblies = Directory.GetFiles(modulesPath, "*.dll")
            .Select(Assembly.LoadFrom)
            .ToList();

        var configuration = new ContainerConfiguration()
            .WithAssemblies(assemblies);

        _container = configuration.CreateContainer();

        _modules = _container
            .GetExports<Lazy<IModule, IModuleMetadata>>()
            .OrderBy(m => m.Metadata.LoadOrder);

        foreach (var module in _modules)
        {
            Console.WriteLine($"Discovered: {module.Metadata.Name} (order: {module.Metadata.LoadOrder})");
        }
    }

    public void RegisterModules(ContainerBuilder builder, IConfiguration configuration)
    {
        foreach (var module in _modules)
        {
            // Lazy<> means module isn't instantiated until .Value accessed
            module.Value.RegisterServices(builder, configuration);
        }
    }
}

// Host/Program.cs
var mefLoader = new MefModuleLoader();
mefLoader.DiscoverModules(Path.Combine(AppContext.BaseDirectory, "modules"));

builder.Host.ConfigureContainer<ContainerBuilder>(container =>
{
    mefLoader.RegisterModules(container, builder.Configuration);
});
```

---

### Approach 3: Configuration-Based Module Selection

Select which modules/implementations to load based on config.

```json
// appsettings.json
{
  "Modules": {
    "Orders": {
      "Enabled": true,
      "Implementation": "Default",
      "Settings": {
        "MaxOrderItems": 100
      }
    },
    "Inventory": {
      "Enabled": true,
      "Implementation": "Warehouse",  // Could be "Warehouse" or "Dropship"
      "Settings": {
        "SyncInterval": "00:05:00"
      }
    },
    "Shipping": {
      "Enabled": false  // Disabled for this deployment
    }
  }
}
```

```csharp
// SharedKernel/ModuleConfig.cs
public class ModuleConfig
{
    public bool Enabled { get; set; } = true;
    public string Implementation { get; set; } = "Default";
    public Dictionary<string, object> Settings { get; set; } = [];
}

public class ModulesConfig : Dictionary<string, ModuleConfig> { }
```

```csharp
// Host/ConfigurableModuleLoader.cs
public class ConfigurableModuleLoader
{
    private readonly List<IModule> _modules = [];

    public void DiscoverAndFilter(string modulesPath, IConfiguration configuration)
    {
        var modulesConfig = configuration
            .GetSection("Modules")
            .Get<ModulesConfig>() ?? [];

        var assemblies = Directory.GetFiles(modulesPath, "*.dll")
            .Select(Assembly.LoadFrom);

        foreach (var assembly in assemblies)
        {
            var moduleTypes = assembly.GetTypes()
                .Where(t => typeof(IModule).IsAssignableFrom(t) && !t.IsAbstract);

            foreach (var moduleType in moduleTypes)
            {
                var module = (IModule)Activator.CreateInstance(moduleType)!;

                // Check if enabled in config
                if (modulesConfig.TryGetValue(module.Name, out var config))
                {
                    if (!config.Enabled)
                    {
                        Console.WriteLine($"Skipping disabled module: {module.Name}");
                        continue;
                    }

                    // Check if this is the configured implementation
                    var implAttr = moduleType.GetCustomAttribute<ModuleImplementationAttribute>();
                    if (implAttr != null && implAttr.Name != config.Implementation)
                    {
                        Console.WriteLine($"Skipping {module.Name}/{implAttr.Name} (want {config.Implementation})");
                        continue;
                    }
                }

                _modules.Add(module);
                Console.WriteLine($"Loaded module: {module.Name}");
            }
        }
    }

    public void RegisterModules(ContainerBuilder builder, IConfiguration configuration)
    {
        foreach (var module in _modules)
        {
            module.RegisterServices(builder, configuration);
        }
    }
}

// Attribute to mark implementation variants
[AttributeUsage(AttributeTargets.Class)]
public class ModuleImplementationAttribute : Attribute
{
    public string Name { get; }
    public ModuleImplementationAttribute(string name) => Name = name;
}
```

```csharp
// Multiple implementations of same module

// Inventory.Core/WarehouseInventoryModule.cs
[ModuleImplementation("Warehouse")]
public class WarehouseInventoryModule : IModule
{
    public string Name => "Inventory";

    public void RegisterServices(ContainerBuilder builder, IConfiguration configuration)
    {
        builder.RegisterType<WarehouseInventoryService>().As<IInventoryService>();
        builder.RegisterType<WarehouseStockRepository>().As<IStockRepository>();
    }
}

// Inventory.Dropship/DropshipInventoryModule.cs
[ModuleImplementation("Dropship")]
public class DropshipInventoryModule : IModule
{
    public string Name => "Inventory";

    public void RegisterServices(ContainerBuilder builder, IConfiguration configuration)
    {
        builder.RegisterType<DropshipInventoryService>().As<IInventoryService>();
        builder.RegisterType<SupplierApiClient>().As<IStockRepository>();
    }
}
```

---

### Same Interface, Multiple Configurations (Keyed Services)

When you need the same interface with different configurations.

```csharp
// Scenario: Multiple payment gateways
public interface IPaymentGateway
{
    Task<PaymentResult> ProcessAsync(PaymentRequest request);
}

// Configuration
{
  "PaymentGateways": {
    "Stripe": {
      "Enabled": true,
      "ApiKey": "sk_test_...",
      "Primary": true
    },
    "PayPal": {
      "Enabled": true,
      "ClientId": "...",
      "Primary": false
    },
    "Square": {
      "Enabled": false
    }
  }
}
```

```csharp
// Payments.Core/PaymentsModule.cs
public class PaymentsModule : IModule
{
    public string Name => "Payments";

    public void RegisterServices(ContainerBuilder builder, IConfiguration configuration)
    {
        var gatewaysConfig = configuration
            .GetSection("PaymentGateways")
            .Get<Dictionary<string, PaymentGatewayConfig>>() ?? [];

        // Register each enabled gateway as keyed service
        foreach (var (name, config) in gatewaysConfig.Where(g => g.Value.Enabled))
        {
            switch (name)
            {
                case "Stripe":
                    builder.RegisterType<StripeGateway>()
                        .WithParameter("apiKey", config.ApiKey)
                        .Keyed<IPaymentGateway>(name)
                        .SingleInstance();
                    break;

                case "PayPal":
                    builder.RegisterType<PayPalGateway>()
                        .WithParameter("clientId", config.ClientId)
                        .Keyed<IPaymentGateway>(name)
                        .SingleInstance();
                    break;

                case "Square":
                    builder.RegisterType<SquareGateway>()
                        .Keyed<IPaymentGateway>(name)
                        .SingleInstance();
                    break;
            }

            // Register primary as default (non-keyed)
            if (config.Primary)
            {
                builder.Register(ctx => ctx.ResolveKeyed<IPaymentGateway>(name))
                    .As<IPaymentGateway>()
                    .SingleInstance();
            }
        }

        // Register composite that tries multiple gateways
        builder.RegisterType<CompositePaymentGateway>()
            .Named<IPaymentGateway>("composite")
            .SingleInstance();

        // Register factory for resolving by name
        builder.Register<Func<string, IPaymentGateway>>(ctx =>
        {
            var context = ctx.Resolve<IComponentContext>();
            return name => context.ResolveKeyed<IPaymentGateway>(name);
        });
    }
}

// Usage
public class PaymentService
{
    private readonly IPaymentGateway _defaultGateway;
    private readonly Func<string, IPaymentGateway> _gatewayFactory;

    public PaymentService(
        IPaymentGateway defaultGateway,                    // Primary gateway
        Func<string, IPaymentGateway> gatewayFactory)      // Factory for specific
    {
        _defaultGateway = defaultGateway;
        _gatewayFactory = gatewayFactory;
    }

    public async Task<PaymentResult> ProcessAsync(PaymentRequest request)
    {
        // Use default
        return await _defaultGateway.ProcessAsync(request);
    }

    public async Task<PaymentResult> ProcessWithGatewayAsync(
        PaymentRequest request,
        string gatewayName)
    {
        // Use specific gateway
        var gateway = _gatewayFactory(gatewayName);
        return await gateway.ProcessAsync(request);
    }
}
```

### Injecting All Implementations

```csharp
// Get all registered implementations of an interface
public class PaymentGatewayRegistry
{
    private readonly IEnumerable<IPaymentGateway> _gateways;

    public PaymentGatewayRegistry(IEnumerable<IPaymentGateway> gateways)
    {
        _gateways = gateways;
    }

    public IEnumerable<string> AvailableGateways =>
        _gateways.Select(g => g.GetType().Name);
}

// Registration
builder.RegisterType<StripeGateway>().As<IPaymentGateway>();
builder.RegisterType<PayPalGateway>().As<IPaymentGateway>();
// IEnumerable<IPaymentGateway> will resolve all
```

### Metadata-Based Selection

```csharp
// Attribute with metadata
[AttributeUsage(AttributeTargets.Class)]
public class PaymentGatewayAttribute : Attribute
{
    public string Name { get; }
    public string[] SupportedCurrencies { get; }
    public decimal MaxAmount { get; }

    public PaymentGatewayAttribute(
        string name,
        string[] currencies,
        decimal maxAmount = decimal.MaxValue)
    {
        Name = name;
        SupportedCurrencies = currencies;
        MaxAmount = maxAmount;
    }
}

[PaymentGateway("Stripe", new[] { "USD", "EUR", "GBP" }, MaxAmount = 999999)]
public class StripeGateway : IPaymentGateway { }

[PaymentGateway("PayPal", new[] { "USD", "EUR" }, MaxAmount = 10000)]
public class PayPalGateway : IPaymentGateway { }
```

```csharp
// Registration with metadata
builder.RegisterAssemblyTypes(assembly)
    .Where(t => typeof(IPaymentGateway).IsAssignableFrom(t))
    .As<IPaymentGateway>()
    .WithMetadataFrom<PaymentGatewayAttribute>();

// Resolution with metadata
public class SmartPaymentRouter
{
    private readonly IEnumerable<Lazy<IPaymentGateway, PaymentGatewayAttribute>> _gateways;

    public SmartPaymentRouter(
        IEnumerable<Lazy<IPaymentGateway, PaymentGatewayAttribute>> gateways)
    {
        _gateways = gateways;
    }

    public IPaymentGateway SelectGateway(string currency, decimal amount)
    {
        var suitable = _gateways
            .Where(g => g.Metadata.SupportedCurrencies.Contains(currency))
            .Where(g => g.Metadata.MaxAmount >= amount)
            .OrderByDescending(g => g.Metadata.MaxAmount)  // Prefer higher limits
            .FirstOrDefault();

        return suitable?.Value
            ?? throw new InvalidOperationException($"No gateway for {currency}/{amount}");
    }
}
```

---

### AssemblyLoadContext for Isolation (Unloadable Modules)

For true plugin isolation with ability to unload:

```csharp
public class ModuleLoadContext : AssemblyLoadContext
{
    private readonly AssemblyDependencyResolver _resolver;

    public ModuleLoadContext(string modulePath) : base(isCollectible: true)
    {
        _resolver = new AssemblyDependencyResolver(modulePath);
    }

    protected override Assembly? Load(AssemblyName assemblyName)
    {
        var path = _resolver.ResolveAssemblyToPath(assemblyName);
        return path != null ? LoadFromAssemblyPath(path) : null;
    }
}

public class IsolatedModuleLoader
{
    private readonly Dictionary<string, (ModuleLoadContext Context, IModule Module)> _loaded = [];

    public IModule LoadModule(string modulePath)
    {
        var context = new ModuleLoadContext(modulePath);
        var assembly = context.LoadFromAssemblyPath(modulePath);

        var moduleType = assembly.GetTypes()
            .First(t => typeof(IModule).IsAssignableFrom(t) && !t.IsAbstract);

        var module = (IModule)Activator.CreateInstance(moduleType)!;
        _loaded[module.Name] = (context, module);

        return module;
    }

    public void UnloadModule(string moduleName)
    {
        if (_loaded.TryGetValue(moduleName, out var entry))
        {
            _loaded.Remove(moduleName);
            entry.Context.Unload();

            // Force GC to actually unload
            GC.Collect();
            GC.WaitForPendingFinalizers();
        }
    }
}
```

---

### Complete Host Program.cs

Putting it all together:

```csharp
// Host/Program.cs
using Autofac;
using Autofac.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);

// Discover modules from configured path
var modulesPath = builder.Configuration["ModulesPath"]
    ?? Path.Combine(AppContext.BaseDirectory, "modules");

var moduleLoader = new ConfigurableModuleLoader();
moduleLoader.DiscoverAndFilter(modulesPath, builder.Configuration);

// Setup Autofac
builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
builder.Host.ConfigureContainer<ContainerBuilder>((context, container) =>
{
    // Shared services
    container.RegisterType<MessageBus>().As<IMessageBus>().SingleInstance();
    container.RegisterType<EventStore>().As<IEventStore>().SingleInstance();

    // Discovered modules
    moduleLoader.RegisterModules(container, context.Configuration);

    // Register all handlers from loaded assemblies
    var assemblies = moduleLoader.GetLoadedAssemblies();
    container.RegisterAssemblyTypes(assemblies.ToArray())
        .AsClosedTypesOf(typeof(ICommandHandler<>))
        .InstancePerLifetimeScope();

    container.RegisterAssemblyTypes(assemblies.ToArray())
        .AsClosedTypesOf(typeof(IQueryHandler<,>))
        .InstancePerLifetimeScope();
});

var app = builder.Build();

// Module startup hooks
foreach (var module in moduleLoader.GetModules().OfType<IModuleLifecycle>())
{
    await module.OnStartAsync(app.Services, CancellationToken.None);
}

// Standard ASP.NET Core setup
app.UseRouting();
app.MapControllers();

// Graceful shutdown
var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
lifetime.ApplicationStopping.Register(async () =>
{
    foreach (var module in moduleLoader.GetModules().OfType<IModuleLifecycle>().Reverse())
    {
        await module.OnStopAsync(app.Services, CancellationToken.None);
    }
});

app.Run();
```

---

### Build Output Structure

Configure modules to output to modules folder:

```xml
<!-- Orders.Core.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <!-- Output to modules folder -->
    <OutputPath>..\..\..\..\modules\</OutputPath>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\Orders.Contracts\Orders.Contracts.csproj" />
    <ProjectReference Include="..\..\SharedKernel\SharedKernel.csproj" />
  </ItemGroup>
</Project>
```

Or use post-build to copy:

```xml
<Target Name="CopyToModules" AfterTargets="Build">
  <Copy
    SourceFiles="$(OutputPath)$(AssemblyName).dll"
    DestinationFolder="$(SolutionDir)modules\" />
</Target>
```

---

## Summary

| Pattern | When to Use |
|---------|-------------|
| **MS DI + Extensions** | Simple apps, few modules, no advanced needs |
| **Autofac Modules** | Modular monolith, need isolation |
| **Decorators** | Cross-cutting concerns (logging, validation, caching) |
| **Interceptors** | AOP, attribute-based behavior |
| **Keyed Services** | Multi-tenant, variant implementations |
| **Child Scopes** | Transaction boundaries, operation contexts |
| **Module Scanning** | Plugin architecture, dynamic loading |
| **MEF + Autofac** | Attribute-based discovery, lazy loading |
| **Config-Based Loading** | Enable/disable modules, select implementations |
| **AssemblyLoadContext** | Hot reload, unloadable plugins |
