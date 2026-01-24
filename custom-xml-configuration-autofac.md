# Custom XML Configuration with Autofac and XmlSerializer

This document outlines how to load custom XML configuration files into strongly-typed objects using `XmlSerializer`, and register them with Autofac for dependency injection.

## Overview

Instead of using `IConfiguration` (which flattens everything to `string` key-value pairs), we deserialize XML directly into objects and register them with Autofac.

## Example XML Configuration

```xml
<!-- features.xml -->
<AppConfig>
  <Features>
    <Feature>
      <Name>Auth</Name>
      <Enabled>true</Enabled>
      <Description>Authentication and authorization settings</Description>
      <Settings>
        <Setting>
          <Key>Timeout</Key>
          <Value>30</Value>
          <Type>int</Type>
        </Setting>
        <Setting>
          <Key>RetryCount</Key>
          <Value>3</Value>
          <Type>int</Type>
        </Setting>
        <Setting>
          <Key>Provider</Key>
          <Value>OAuth2</Value>
          <Type>string</Type>
        </Setting>
      </Settings>
      <Dependencies>
        <Dependency>
          <Name>Database</Name>
          <Required>true</Required>
        </Dependency>
        <Dependency>
          <Name>Caching</Name>
          <Required>false</Required>
        </Dependency>
      </Dependencies>
      <Endpoints>
        <Endpoint>
          <Path>/auth/login</Path>
          <Method>POST</Method>
          <RateLimit>100</RateLimit>
        </Endpoint>
        <Endpoint>
          <Path>/auth/refresh</Path>
          <Method>POST</Method>
          <RateLimit>50</RateLimit>
        </Endpoint>
      </Endpoints>
    </Feature>
    <Feature>
      <Name>Caching</Name>
      <Enabled>false</Enabled>
      <Description>Distributed caching configuration</Description>
      <Settings>
        <Setting>
          <Key>Duration</Key>
          <Value>600</Value>
          <Type>int</Type>
        </Setting>
        <Setting>
          <Key>Provider</Key>
          <Value>Redis</Value>
          <Type>string</Type>
        </Setting>
      </Settings>
      <Connection>
        <Host>localhost</Host>
        <Port>6379</Port>
        <Database>0</Database>
        <Ssl>false</Ssl>
      </Connection>
    </Feature>
  </Features>
</AppConfig>
```

## Configuration Classes

Decorate classes with `XmlSerializer` attributes to map XML elements to properties.

```csharp
using System.Xml.Serialization;

[XmlRoot("AppConfig")]
public class FeaturesOptions
{
    [XmlArray("Features")]
    [XmlArrayItem("Feature")]
    public List<FeatureConfig> FeatureList { get; set; } = [];

    /// <summary>
    /// Convenience property to access features by name.
    /// </summary>
    [XmlIgnore]
    public Dictionary<string, FeatureConfig> Features =>
        FeatureList.ToDictionary(f => f.Name);
}

public class FeatureConfig
{
    [XmlElement("Name")]
    public string Name { get; set; } = string.Empty;

    [XmlElement("Enabled")]
    public bool Enabled { get; set; }

    [XmlElement("Description")]
    public string Description { get; set; } = string.Empty;

    [XmlArray("Settings")]
    [XmlArrayItem("Setting")]
    public List<FeatureSetting> Settings { get; set; } = [];

    [XmlArray("Dependencies")]
    [XmlArrayItem("Dependency")]
    public List<FeatureDependency> Dependencies { get; set; } = [];

    [XmlArray("Endpoints")]
    [XmlArrayItem("Endpoint")]
    public List<FeatureEndpoint> Endpoints { get; set; } = [];

    [XmlElement("Connection")]
    public ConnectionConfig? Connection { get; set; }
}

public class FeatureSetting
{
    [XmlElement("Key")]
    public string Key { get; set; } = string.Empty;

    [XmlElement("Value")]
    public string Value { get; set; } = string.Empty;

    [XmlElement("Type")]
    public string Type { get; set; } = string.Empty;
}

public class FeatureDependency
{
    [XmlElement("Name")]
    public string Name { get; set; } = string.Empty;

    [XmlElement("Required")]
    public bool Required { get; set; }
}

public class FeatureEndpoint
{
    [XmlElement("Path")]
    public string Path { get; set; } = string.Empty;

    [XmlElement("Method")]
    public string Method { get; set; } = string.Empty;

    [XmlElement("RateLimit")]
    public int RateLimit { get; set; }
}

public class ConnectionConfig
{
    [XmlElement("Host")]
    public string Host { get; set; } = string.Empty;

    [XmlElement("Port")]
    public int Port { get; set; }

    [XmlElement("Database")]
    public int Database { get; set; }

    [XmlElement("Ssl")]
    public bool Ssl { get; set; }
}
```

## Autofac Module

Encapsulate the loading and registration logic in an Autofac module.

```csharp
using System.Xml.Serialization;
using Autofac;

public class FeaturesModule : Module
{
    private readonly string _xmlPath;

    public FeaturesModule(string xmlPath)
    {
        _xmlPath = xmlPath;
    }

    protected override void Load(ContainerBuilder builder)
    {
        var options = LoadFromXml();

        // Register the entire options object
        builder.RegisterInstance(options)
               .AsSelf()
               .SingleInstance();

        // Optionally register individual features by name (keyed)
        foreach (var (name, config) in options.Features)
        {
            builder.RegisterInstance(config)
                   .Keyed<FeatureConfig>(name)
                   .SingleInstance();
        }
    }

    private FeaturesOptions LoadFromXml()
    {
        using var stream = File.OpenRead(_xmlPath);
        var serializer = new XmlSerializer(typeof(FeaturesOptions));
        return (FeaturesOptions)serializer.Deserialize(stream)!;
    }
}
```

## Registration

Register the module when building your container.

```csharp
var builder = new ContainerBuilder();

// Register the features module
builder.RegisterModule(new FeaturesModule("features.xml"));

// Register other services...
builder.RegisterType<AuthService>().As<IAuthService>();

var container = builder.Build();
```

## Usage

### Inject the entire configuration

```csharp
public class MyService
{
    private readonly FeaturesOptions _features;

    public MyService(FeaturesOptions features)
    {
        _features = features;
    }

    public void DoSomething()
    {
        if (_features.Features.TryGetValue("Auth", out var authConfig) && authConfig.Enabled)
        {
            // Use auth configuration
            var timeout = authConfig.Settings
                .FirstOrDefault(s => s.Key == "Timeout")?.Value;
        }
    }
}
```

### Resolve a specific feature by key

```csharp
// Resolve directly from container
var authConfig = container.ResolveKeyed<FeatureConfig>("Auth");

// Or inject using Autofac's keyed resolution
public class AuthService
{
    private readonly FeatureConfig _config;

    public AuthService([KeyFilter("Auth")] FeatureConfig config)
    {
        _config = config;
    }
}
```

> **Note:** For `KeyFilter` to work, register the service with `.WithAttributeFiltering()`:
> ```csharp
> builder.RegisterType<AuthService>()
>        .As<IAuthService>()
>        .WithAttributeFiltering();
> ```

## Comparison with IConfiguration

| Approach | Pros | Cons |
|----------|------|------|
| **IConfiguration + Custom Provider** | Works with `IOptions<T>`, supports layering/overrides from multiple sources | Everything is flattened to strings, more boilerplate |
| **XmlSerializer + Autofac** | Strongly-typed from the start, zero parsing code, clean module encapsulation | No built-in layering, no environment variable overrides |

Use `IConfiguration` when you need to merge configs from multiple sources (JSON, env vars, command line). Use `XmlSerializer` when you have a fixed XML schema and want direct object mapping.
