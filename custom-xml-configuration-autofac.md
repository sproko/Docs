# Custom XML Configuration with Autofac and DataContractSerializer

Load custom XML configuration files into strongly-typed objects using `DataContractSerializer`, and register them with Autofac for dependency injection.

## Example XML Configuration

Clean XML - no attributes, just elements matching property names:

```xml
<!-- features.xml -->
<FeaturesOptions xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
  <Features>
    <FeatureConfig>
      <Name>Auth</Name>
      <Enabled>true</Enabled>
      <Description>Authentication and authorization settings</Description>
      <Settings>
        <FeatureSetting>
          <Key>Timeout</Key>
          <Value>30</Value>
        </FeatureSetting>
        <FeatureSetting>
          <Key>RetryCount</Key>
          <Value>3</Value>
        </FeatureSetting>
      </Settings>
      <Dependencies>
        <Dependency>
          <Name>Database</Name>
          <Required>true</Required>
        </Dependency>
      </Dependencies>
      <Connection>
        <Host>localhost</Host>
        <Port>6379</Port>
        <Ssl>false</Ssl>
      </Connection>
    </FeatureConfig>
    <FeatureConfig>
      <Name>Caching</Name>
      <Enabled>false</Enabled>
      <Description>Distributed caching</Description>
      <Settings>
        <FeatureSetting>
          <Key>Duration</Key>
          <Value>600</Value>
        </FeatureSetting>
      </Settings>
    </FeatureConfig>
  </Features>
</FeaturesOptions>
```

## Configuration Classes

Compose objects freely - just mark classes with `[DataContract]` and properties with `[DataMember]`:

```csharp
using System.Runtime.Serialization;

[DataContract]
public class FeaturesOptions
{
    [DataMember]
    public List<FeatureConfig> Features { get; set; } = [];
}

[DataContract]
public class FeatureConfig
{
    [DataMember]
    public string Name { get; set; } = string.Empty;

    [DataMember]
    public bool Enabled { get; set; }

    [DataMember]
    public string Description { get; set; } = string.Empty;

    [DataMember]
    public List<FeatureSetting> Settings { get; set; } = [];

    [DataMember]
    public List<Dependency> Dependencies { get; set; } = [];

    [DataMember]
    public ConnectionConfig? Connection { get; set; }
}

[DataContract]
public class FeatureSetting
{
    [DataMember]
    public string Key { get; set; } = string.Empty;

    [DataMember]
    public string Value { get; set; } = string.Empty;
}

[DataContract]
public class Dependency
{
    [DataMember]
    public string Name { get; set; } = string.Empty;

    [DataMember]
    public bool Required { get; set; }
}

[DataContract]
public class ConnectionConfig
{
    [DataMember]
    public string Host { get; set; } = string.Empty;

    [DataMember]
    public int Port { get; set; }

    [DataMember]
    public bool Ssl { get; set; }
}
```

### Optional: Customize Element Names

Override names only where needed:

```csharp
[DataContract(Name = "Feature")]
public class FeatureConfig
{
    [DataMember(Name = "host")]
    public string Host { get; set; } = string.Empty;
}
```

## Autofac Module

```csharp
using System.Runtime.Serialization;
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

        builder.RegisterInstance(options)
               .AsSelf()
               .SingleInstance();
    }

    private FeaturesOptions LoadFromXml()
    {
        var serializer = new DataContractSerializer(typeof(FeaturesOptions));
        using var stream = File.OpenRead(_xmlPath);
        return (FeaturesOptions)serializer.ReadObject(stream)!;
    }
}
```

## Registration

```csharp
var builder = new ContainerBuilder();
builder.RegisterModule(new FeaturesModule("features.xml"));
var container = builder.Build();
```

## Usage

```csharp
public class AuthService
{
    private readonly FeaturesOptions _options;

    public AuthService(FeaturesOptions options)
    {
        _options = options;
    }

    public void Init()
    {
        var auth = _options.Features.FirstOrDefault(f => f.Name == "Auth");
        if (auth?.Enabled == true)
        {
            var timeout = auth.Settings.FirstOrDefault(s => s.Key == "Timeout")?.Value;
            var conn = auth.Connection;
            // ...
        }
    }
}
```

## Varying Config Objects

If different features have different structures, use a base class or interface:

```csharp
[DataContract]
[KnownType(typeof(AuthConfig))]
[KnownType(typeof(CachingConfig))]
public abstract class FeatureConfigBase
{
    [DataMember]
    public string Name { get; set; } = string.Empty;

    [DataMember]
    public bool Enabled { get; set; }
}

[DataContract]
public class AuthConfig : FeatureConfigBase
{
    [DataMember]
    public int Timeout { get; set; }

    [DataMember]
    public string Provider { get; set; } = string.Empty;
}

[DataContract]
public class CachingConfig : FeatureConfigBase
{
    [DataMember]
    public int Duration { get; set; }

    [DataMember]
    public ConnectionConfig? Connection { get; set; }
}

[DataContract]
public class FeaturesOptions
{
    [DataMember]
    public List<FeatureConfigBase> Features { get; set; } = [];
}
```

XML with type hints:

```xml
<FeaturesOptions xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
  <Features>
    <FeatureConfigBase i:type="AuthConfig">
      <Name>Auth</Name>
      <Enabled>true</Enabled>
      <Timeout>30</Timeout>
      <Provider>OAuth2</Provider>
    </FeatureConfigBase>
    <FeatureConfigBase i:type="CachingConfig">
      <Name>Caching</Name>
      <Enabled>false</Enabled>
      <Duration>600</Duration>
      <Connection>
        <Host>localhost</Host>
        <Port>6379</Port>
        <Ssl>false</Ssl>
      </Connection>
    </FeatureConfigBase>
  </Features>
</FeaturesOptions>
```

## DataContract vs XmlSerializer

| | DataContract | XmlSerializer |
|---|---|---|
| Attributes | `[DataContract]`, `[DataMember]` | `[XmlRoot]`, `[XmlElement]`, `[XmlArray]`, etc. |
| Default naming | Property name | Property name |
| Polymorphism | `[KnownType]` + `i:type` attribute | `[XmlInclude]` |
| Opt-in/out | Opt-in (only `[DataMember]` serialized) | Opt-out (all public props by default) |
| Verbosity | Less | More |
