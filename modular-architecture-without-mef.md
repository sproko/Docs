# Modular Architecture Without MEF

A practical guide to building a plugin-style modular architecture using plain C# and Microsoft DI - no MEF required. Works in both .NET Framework 4.8 and .NET 8+.

## Overview

This pattern allows you to:
- Break a monolith into independent modules
- Discover and load modules automatically at startup
- Update individual modules by replacing DLLs and restarting
- Enforce decoupling through contracts assemblies
- Avoid MEF's complexity and performance issues

---

## Table of Contents

1. [Architecture](#architecture)
2. [Project Structure](#project-structure)
3. [Step 1: Create the Contracts Assembly](#step-1-create-the-contracts-assembly)
4. [Step 2: Create the Common Infrastructure](#step-2-create-the-common-infrastructure)
5. [Step 3: Create a Module](#step-3-create-a-module)
6. [Step 4: Wire Up the Host](#step-4-wire-up-the-host)
7. [Step 5: Deploy and Update Modules](#step-5-deploy-and-update-modules)
8. [Migration from MEF](#migration-from-mef)
9. [Performance Comparison](#performance-comparison)
10. [Best Practices](#best-practices)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Host Application                      │
│  - Scans Modules folder                                     │
│  - Loads assemblies                                         │
│  - Discovers IModule implementations                        │
│  - Registers services via MS DI                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Contracts Assembly                        │
│  - IModule interface                                        │
│  - IEndpoint interface                                      │
│  - Shared DTOs / models                                     │
│  - Service interfaces (rarely changes)                      │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌───────────┐       ┌───────────┐       ┌───────────┐
    │  Module A │       │  Module B │       │  Module C │
    │  ───────  │       │  ───────  │       │  ───────  │
    │  Events   │       │  Users    │       │  Tickets  │
    └───────────┘       └───────────┘       └───────────┘
```

**Key principle:** Modules only communicate through the Contracts assembly. They never reference each other directly.

---

## Project Structure

```
Solution/
├── src/
│   ├── Host/
│   │   └── MyApp.Host/
│   │       ├── MyApp.Host.csproj
│   │       └── Program.cs
│   │
│   ├── Common/
│   │   ├── MyApp.Contracts/              ← Shared interfaces & DTOs
│   │   │   ├── MyApp.Contracts.csproj
│   │   │   ├── IModule.cs
│   │   │   ├── IEndpoint.cs
│   │   │   └── Models/
│   │   │
│   │   └── MyApp.Common/                 ← Shared utilities
│   │       ├── MyApp.Common.csproj
│   │       └── Extensions/
│   │           └── ModuleExtensions.cs
│   │
│   └── Modules/
│       ├── MyApp.Modules.Events/
│       │   ├── MyApp.Modules.Events.csproj
│       │   ├── EventsModule.cs
│       │   ├── Endpoints/
│       │   ├── Services/
│       │   └── Data/
│       │
│       ├── MyApp.Modules.Users/
│       │   └── ...
│       │
│       └── MyApp.Modules.Tickets/
│           └── ...
│
├── deploy/
│   ├── MyApp.Host.dll
│   ├── MyApp.Contracts.dll
│   ├── MyApp.Common.dll
│   └── Modules/                          ← Drop updated DLLs here
│       ├── MyApp.Modules.Events.dll
│       ├── MyApp.Modules.Users.dll
│       └── MyApp.Modules.Tickets.dll
│
└── Solution.sln
```

---

## Step 1: Create the Contracts Assembly

This assembly defines the interfaces that modules must implement. It should be **stable** and change infrequently.

**MyApp.Contracts.csproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <!-- Use net48 now, change to net8.0 when migrating -->
    <TargetFramework>net48</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="8.0.0" />
    <!-- For IEndpointRouteBuilder in web scenarios -->
    <PackageReference Include="Microsoft.AspNetCore.Routing.Abstractions" Version="2.2.0" />
  </ItemGroup>
</Project>
```

**IModule.cs:**
```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace MyApp.Contracts
{
    /// <summary>
    /// Implement this interface in each module to enable auto-discovery.
    /// </summary>
    public interface IModule
    {
        /// <summary>
        /// Register the module's services with the DI container.
        /// </summary>
        void AddModule(IServiceCollection services, IConfiguration configuration);

        /// <summary>
        /// Optional: Module name for logging/diagnostics.
        /// </summary>
        string Name { get; }
    }
}
```

**IEndpoint.cs (for web APIs):**
```csharp
using Microsoft.AspNetCore.Routing;

namespace MyApp.Contracts
{
    /// <summary>
    /// Implement this interface to auto-register API endpoints.
    /// </summary>
    public interface IEndpoint
    {
        void MapEndpoint(IEndpointRouteBuilder app);
    }
}
```

---

## Step 2: Create the Common Infrastructure

This assembly contains the scanning and registration logic.

**MyApp.Common.csproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="8.0.0" />
    <ProjectReference Include="..\MyApp.Contracts\MyApp.Contracts.csproj" />
  </ItemGroup>
</Project>
```

**ModuleExtensions.cs:**
```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MyApp.Contracts;

namespace MyApp.Common.Extensions
{
    public static class ModuleExtensions
    {
        /// <summary>
        /// Scan a folder for module DLLs and register all discovered modules.
        /// </summary>
        public static IServiceCollection AddModulesFromFolder(
            this IServiceCollection services,
            IConfiguration configuration,
            string modulesPath = "Modules")
        {
            if (!Directory.Exists(modulesPath))
            {
                throw new DirectoryNotFoundException(
                    $"Modules folder not found: {Path.GetFullPath(modulesPath)}");
            }

            var dllFiles = Directory.GetFiles(modulesPath, "*.Modules.*.dll");
            var assemblies = new List<Assembly>();

            foreach (var dllFile in dllFiles)
            {
                try
                {
                    var assembly = Assembly.LoadFrom(dllFile);
                    assemblies.Add(assembly);
                    Console.WriteLine($"Loaded module assembly: {Path.GetFileName(dllFile)}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Failed to load {dllFile}: {ex.Message}");
                }
            }

            return services.AddModules(configuration, assemblies.ToArray());
        }

        /// <summary>
        /// Register modules from the provided assemblies.
        /// </summary>
        public static IServiceCollection AddModules(
            this IServiceCollection services,
            IConfiguration configuration,
            params Assembly[] assemblies)
        {
            foreach (var assembly in assemblies)
            {
                var moduleTypes = assembly.GetTypes()
                    .Where(t => !t.IsAbstract &&
                                !t.IsInterface &&
                                typeof(IModule).IsAssignableFrom(t));

                foreach (var type in moduleTypes)
                {
                    var module = (IModule)Activator.CreateInstance(type);
                    Console.WriteLine($"Registering module: {module.Name}");
                    module.AddModule(services, configuration);
                }
            }

            return services;
        }

        /// <summary>
        /// Scan assemblies for IEndpoint implementations and register them.
        /// </summary>
        public static IServiceCollection AddEndpoints(
            this IServiceCollection services,
            params Assembly[] assemblies)
        {
            var serviceDescriptors = assemblies
                .SelectMany(a => a.GetTypes())
                .Where(t => !t.IsAbstract &&
                            !t.IsInterface &&
                            typeof(IEndpoint).IsAssignableFrom(t))
                .Select(t => ServiceDescriptor.Transient(typeof(IEndpoint), t))
                .ToArray();

            services.TryAddEnumerable(serviceDescriptors);

            return services;
        }
    }
}
```

**EndpointExtensions.cs (for web APIs):**
```csharp
using System.Collections.Generic;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using MyApp.Contracts;

namespace MyApp.Common.Extensions
{
    public static class EndpointExtensions
    {
        /// <summary>
        /// Map all discovered endpoints to the application.
        /// </summary>
        public static IApplicationBuilder MapModuleEndpoints(this IApplicationBuilder app)
        {
            var endpoints = app.ApplicationServices.GetRequiredService<IEnumerable<IEndpoint>>();

            foreach (var endpoint in endpoints)
            {
                endpoint.MapEndpoint((IEndpointRouteBuilder)app);
            }

            return app;
        }
    }
}
```

---

## Step 3: Create a Module

Each module is self-contained and only references the Contracts assembly.

**MyApp.Modules.Events.csproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\Common\MyApp.Contracts\MyApp.Contracts.csproj" />
    <!-- Module-specific dependencies -->
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="8.0.0" />
  </ItemGroup>
</Project>
```

**EventsModule.cs:**
```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MyApp.Contracts;
using MyApp.Modules.Events.Services;
using MyApp.Modules.Events.Data;

namespace MyApp.Modules.Events
{
    public class EventsModule : IModule
    {
        public string Name => "Events";

        public void AddModule(IServiceCollection services, IConfiguration configuration)
        {
            // Register module-specific services
            services.AddScoped<IEventService, EventService>();
            services.AddScoped<IEventRepository, EventRepository>();

            // Register endpoints for this module
            services.AddEndpoints(typeof(EventsModule).Assembly);

            // Module-specific configuration
            var connectionString = configuration.GetConnectionString("Events");
            services.AddDbContext<EventsDbContext>(options =>
                options.UseNpgsql(connectionString));
        }
    }
}
```

**Endpoints/GetEventsEndpoint.cs:**
```csharp
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using MyApp.Contracts;
using MyApp.Modules.Events.Services;

namespace MyApp.Modules.Events.Endpoints
{
    public class GetEventsEndpoint : IEndpoint
    {
        public void MapEndpoint(IEndpointRouteBuilder app)
        {
            app.MapGet("/api/events", async (IEventService eventService) =>
            {
                var events = await eventService.GetAllAsync();
                return Results.Ok(events);
            });
        }
    }
}
```

---

## Step 4: Wire Up the Host

The host application loads and registers all modules.

**Program.cs (.NET 6+ style):**
```csharp
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using MyApp.Common.Extensions;

var builder = WebApplication.CreateBuilder(args);

// Auto-discover and register all modules from the Modules folder
builder.Services.AddModulesFromFolder(builder.Configuration, "Modules");

var app = builder.Build();

// Map all discovered endpoints
app.MapModuleEndpoints();

app.Run();
```

**Startup.cs (.NET Framework 4.8 / older style):**
```csharp
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MyApp.Common.Extensions;

public class Startup
{
    private readonly IConfiguration _configuration;

    public Startup(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public void ConfigureServices(IServiceCollection services)
    {
        // Auto-discover and register all modules
        services.AddModulesFromFolder(_configuration, "Modules");
    }

    public void Configure(IApplicationBuilder app)
    {
        // Map all discovered endpoints
        app.MapModuleEndpoints();
    }
}
```

---

## Step 5: Deploy and Update Modules

### Initial Deployment

```
/app
  MyApp.Host.exe (or .dll)
  MyApp.Contracts.dll
  MyApp.Common.dll
  /Modules
    MyApp.Modules.Events.dll
    MyApp.Modules.Users.dll
    MyApp.Modules.Tickets.dll
```

### Updating a Single Module

1. **Stop the application**
   ```bash
   systemctl stop myapp
   # or stop the IIS app pool, Windows service, etc.
   ```

2. **Replace the module DLL**
   ```bash
   cp /updates/MyApp.Modules.Events.dll /app/Modules/
   ```

3. **Start the application**
   ```bash
   systemctl start myapp
   ```

The host will scan the Modules folder and load the updated assembly.

### Rollback

Keep previous versions in a backup folder:
```bash
# Before update
cp /app/Modules/MyApp.Modules.Events.dll /app/Modules/backup/

# To rollback
cp /app/Modules/backup/MyApp.Modules.Events.dll /app/Modules/
```

---

## Migration from MEF

### Before (MEF)

```csharp
// Module registration
[Export(typeof(IModule))]
public class EventsModule : IModule
{
    [ImportMany]
    public IEnumerable<IEventHandler> Handlers { get; set; }

    public void Initialize()
    {
        // ...
    }
}

// Host
var catalog = new AggregateCatalog();
catalog.Catalogs.Add(new DirectoryCatalog("Modules"));
var container = new CompositionContainer(catalog);
container.ComposeParts(this);

[ImportMany]
public IEnumerable<IModule> Modules { get; set; } // 3+ seconds per ImportMany!
```

### After (This Pattern)

```csharp
// Module registration
public class EventsModule : IModule
{
    public string Name => "Events";

    public void AddModule(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IEventHandler, EventHandler>();
        // ...
    }
}

// Host
services.AddModulesFromFolder(configuration, "Modules"); // ~50ms total
```

### Migration Steps

1. **Create Contracts assembly** with `IModule` interface
2. **Create Common assembly** with `ModuleExtensions`
3. **For each MEF module:**
   - Remove `[Export]` and `[Import]` attributes
   - Implement `IModule` interface
   - Move `[ImportMany]` dependencies to constructor injection via DI
   - Replace `[Export]` services with `services.AddScoped<>()` etc.
4. **Update host** to use `AddModulesFromFolder()` instead of MEF catalogs
5. **Remove MEF packages** (System.ComponentModel.Composition)

---

## Performance Comparison

| Operation | MEF (uncached) | MEF (cached) | This Pattern |
|-----------|----------------|--------------|--------------|
| Initial scan | 5-15 seconds | 1-3 seconds | 50-200ms |
| ImportMany resolution | 3+ seconds each | ~500ms each | N/A (standard DI) |
| Service resolution | Container overhead | Container overhead | Dictionary lookup |
| Memory overhead | High (catalogs, lazy proxies) | Medium | Low |

### Why It's Faster

1. **No attribute scanning** - just `IsAssignableFrom()` type checks
2. **No composition graph** - direct instantiation with `Activator.CreateInstance()`
3. **Standard MS DI** - highly optimized, no MEF container overhead
4. **One-time cost** - scanning happens once at startup, then it's pure DI

---

## Best Practices

### DO

- **Keep Contracts stable** - changing interfaces requires updating all modules
- **Version your modules** - include version in assembly name or metadata
- **Log module loading** - helps diagnose startup issues
- **Validate on startup** - check required modules are present
- **Use constructor injection** - let MS DI handle dependencies

### DON'T

- **Don't reference modules directly** - always go through Contracts
- **Don't share state between modules** - use messaging/events if needed
- **Don't put business logic in Common** - it's for infrastructure only
- **Don't skip integration tests** - test module combinations before deploying

### Module Isolation

Modules should only depend on:
- `MyApp.Contracts` (required)
- Their own internal types
- External NuGet packages

Never:
```csharp
// BAD - direct module reference
using MyApp.Modules.Users.Services;
```

Instead, define shared interfaces in Contracts:
```csharp
// In MyApp.Contracts
public interface IUserService
{
    Task<UserDto> GetByIdAsync(Guid id);
}

// Events module can depend on IUserService without knowing the implementation
```

---

## Troubleshooting

### Module Not Loading

Check:
1. DLL is in the Modules folder
2. DLL naming matches pattern (`*.Modules.*.dll`)
3. Module class implements `IModule`
4. Module class has parameterless constructor

### Type Load Exceptions

Usually caused by missing dependencies:
```bash
# Check what a module needs
dotnet publish MyApp.Modules.Events -o ./publish
# Copy all DLLs from publish folder to Modules folder
```

### Version Conflicts

If modules need different versions of a package:
1. Use binding redirects (4.8) or runtime config (.NET 6+)
2. Or keep shared dependencies in the host, not modules

---

## Example: Complete Minimal Setup

A working minimal example:

```
MinimalModular/
├── src/
│   ├── Host/
│   │   └── Program.cs
│   ├── Contracts/
│   │   └── IModule.cs
│   └── Modules/
│       └── HelloModule/
│           └── HelloModule.cs
└── MinimalModular.sln
```

**IModule.cs:**
```csharp
public interface IModule
{
    string Name { get; }
    void AddModule(IServiceCollection services, IConfiguration configuration);
}
```

**HelloModule.cs:**
```csharp
public class HelloModule : IModule
{
    public string Name => "Hello";

    public void AddModule(IServiceCollection services, IConfiguration configuration)
    {
        Console.WriteLine("Hello Module registered!");
    }
}
```

**Program.cs:**
```csharp
var builder = WebApplication.CreateBuilder(args);

// Scan and register
var modulesDll = Directory.GetFiles("Modules", "*.dll");
foreach (var dll in modulesDll)
{
    var assembly = Assembly.LoadFrom(dll);
    var moduleTypes = assembly.GetTypes()
        .Where(t => typeof(IModule).IsAssignableFrom(t) && !t.IsAbstract);

    foreach (var type in moduleTypes)
    {
        var module = (IModule)Activator.CreateInstance(type)!;
        module.AddModule(builder.Services, builder.Configuration);
    }
}

var app = builder.Build();
app.Run();
```

That's it. No MEF, no magic, just plain C#.

---

**Document Version:** 1.0
**Last Updated:** January 2026
**Compatibility:** .NET Framework 4.8, .NET 6, .NET 8+
