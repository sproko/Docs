# Modular Monolith Versioning & Release Strategy

## Goals

- Bundle everything for initial/major releases
- Update individual modules independently when contracts unchanged
- Each module as its own NuGet package (internal feed)
- Clear versioning per module
- GitHub Actions CI/CD

---

## Solution Structure

```
Solution/
├── src/
│   ├── Modules/
│   │   ├── Orders/
│   │   │   ├── Orders.Contracts/          # Public API for this module
│   │   │   │   ├── Commands/
│   │   │   │   ├── Queries/
│   │   │   │   ├── Events/
│   │   │   │   └── Orders.Contracts.csproj
│   │   │   ├── Orders.Core/               # Domain + Application logic
│   │   │   │   └── Orders.Core.csproj
│   │   │   └── Orders.Infrastructure/     # Persistence, external services
│   │   │       └── Orders.Infrastructure.csproj
│   │   │
│   │   ├── Inventory/
│   │   │   ├── Inventory.Contracts/
│   │   │   ├── Inventory.Core/
│   │   │   └── Inventory.Infrastructure/
│   │   │
│   │   └── Shipping/
│   │       ├── Shipping.Contracts/
│   │       ├── Shipping.Core/
│   │       └── Shipping.Infrastructure/
│   │
│   ├── SharedKernel/                      # Cross-cutting: base classes, common types
│   │   └── SharedKernel.csproj
│   │
│   └── Host/                              # Composition root, API endpoints
│       └── Host.csproj
│
├── tests/
│   ├── Orders.Tests/
│   ├── Inventory.Tests/
│   └── Integration.Tests/
│
├── Directory.Build.props                  # Shared build settings
├── Directory.Packages.props               # Central package management
└── global.json
```

### Key Principles

1. **Contracts projects are the public API** - Other modules only reference `*.Contracts`
2. **Core/Infrastructure are internal** - Never referenced directly by other modules
3. **SharedKernel is stable** - Rarely changes, all modules depend on it
4. **Host composes everything** - References all modules, wires DI

### Dependency Rules

```
Orders.Core         → Orders.Contracts, SharedKernel
Orders.Infrastructure → Orders.Core, SharedKernel
Orders.Contracts    → SharedKernel (minimal)

Inventory.Core      → Inventory.Contracts, Orders.Contracts, SharedKernel
                      ↑ depends on Orders via Contracts only
```

---

## Versioning Strategy

### Semantic Versioning per Module

Each module has its own version, tracked in its `.csproj`:

```xml
<!-- Orders.Contracts/Orders.Contracts.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Version>2.3.1</Version>
    <PackageId>YourCompany.Orders.Contracts</PackageId>
    <Description>Orders module public contracts</Description>
  </PropertyGroup>
</Project>
```

### Version Meaning

```
MAJOR.MINOR.PATCH

MAJOR - Breaking contract changes (requires coordinated release)
MINOR - New features, backward-compatible contract additions
PATCH - Bug fixes, internal changes, no contract changes
```

### What Triggers Version Bumps

| Change | Contracts | Core | Infrastructure |
|--------|-----------|------|----------------|
| New command/query/event added | MINOR | - | - |
| Command property added (optional) | MINOR | - | - |
| Command property removed/renamed | MAJOR | - | - |
| Bug fix in handler | - | PATCH | - |
| New handler logic | - | MINOR | - |
| DB schema change (backward compat) | - | - | MINOR |
| Performance optimization | - | - | PATCH |

### Contracts Versioning is Critical

```csharp
// Adding optional property = MINOR bump (backward compatible)
public record CreateOrderCommand(
    Guid CustomerId,
    List<OrderItem> Items,
    string? Notes = null       // Added in 2.4.0 - optional, safe
);

// Removing/renaming property = MAJOR bump (breaking)
public record CreateOrderCommand(
    Guid CustomerId,
    List<OrderItemDto> LineItems  // Renamed from Items = BREAKING
);
```

---

## NuGet Package Strategy

### Internal Feed Setup

Use GitHub Packages (free for private repos) or Azure Artifacts.

**GitHub Packages setup:**

```xml
<!-- nuget.config at solution root -->
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="github" value="https://nuget.pkg.github.com/YOUR_ORG/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <github>
      <add key="Username" value="YOUR_GITHUB_USERNAME" />
      <add key="ClearTextPassword" value="%GITHUB_TOKEN%" />
    </github>
  </packageSourceCredentials>
</configuration>
```

### What Gets Packaged

| Project | Packaged? | Consumers |
|---------|-----------|-----------|
| `*.Contracts` | Yes | Other modules, Host |
| `*.Core` | Yes | Same module's Infrastructure, Host |
| `*.Infrastructure` | Yes | Host |
| `SharedKernel` | Yes | All modules |
| `Host` | No | Deployed as application |

### Package References vs Project References

**During development (feature branch):** Use project references for fast iteration

```xml
<!-- Orders.Core.csproj during development -->
<ItemGroup>
  <ProjectReference Include="..\Orders.Contracts\Orders.Contracts.csproj" />
  <ProjectReference Include="..\..\SharedKernel\SharedKernel.csproj" />
</ItemGroup>
```

**For release builds:** CI publishes packages, consumers use PackageReference

```xml
<!-- Inventory.Core.csproj referencing Orders contracts -->
<ItemGroup>
  <PackageReference Include="YourCompany.Orders.Contracts" Version="2.3.*" />
  <PackageReference Include="YourCompany.SharedKernel" Version="1.0.*" />
</ItemGroup>
```

### Version Ranges

```xml
<!-- Exact version (not recommended - too rigid) -->
<PackageReference Include="YourCompany.Orders.Contracts" Version="2.3.1" />

<!-- Patch wildcard (recommended for internal) -->
<PackageReference Include="YourCompany.Orders.Contracts" Version="2.3.*" />

<!-- Minor wildcard (if you trust backward compat) -->
<PackageReference Include="YourCompany.Orders.Contracts" Version="2.*" />

<!-- Range (most flexible) -->
<PackageReference Include="YourCompany.Orders.Contracts" Version="[2.3.0, 3.0.0)" />
```

---

## Branching Strategy

### Trunk-Based with Release Branches

```
main (trunk)
  │
  ├── Always deployable
  ├── All development merges here
  ├── CI runs on every push
  │
  ├──→ release/2024.1  (cut when ready for major release)
  │     ├── Only bug fixes cherry-picked
  │     ├── Tags: v2024.1.0, v2024.1.1, etc.
  │     └── Hotfixes merged back to main
  │
  └──→ release/2024.2
        └── Next major release
```

### Branch Types

| Branch | Purpose | Lifetime | Merges to |
|--------|---------|----------|-----------|
| `main` | Trunk, always releasable | Forever | - |
| `feature/*` | New features | Days | main |
| `fix/*` | Bug fixes | Days | main (and cherry-pick to release if needed) |
| `release/YYYY.N` | Release stabilization | Until EOL | main (hotfixes) |

### Workflow

```
1. Developer creates feature/add-order-notes
2. Works on Orders module, bumps Orders.Contracts to 2.4.0
3. PR to main, CI builds & tests
4. Merge to main
5. CI publishes Orders.Contracts 2.4.0-preview.{build} to feed
6. When ready for release:
   - Cut release/2024.2 from main
   - CI publishes Orders.Contracts 2.4.0 (stable)
   - Tag v2024.2.0
   - Build full bundle
```

---

## GitHub Actions CI/CD

### Workflow Structure

```
.github/
└── workflows/
    ├── ci.yml                    # PR validation
    ├── publish-packages.yml      # Publish NuGet packages
    ├── release-bundle.yml        # Full release bundle
    └── hotfix-module.yml         # Single module hotfix
```

### CI Workflow (PRs and main)

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      orders: ${{ steps.filter.outputs.orders }}
      inventory: ${{ steps.filter.outputs.inventory }}
      shipping: ${{ steps.filter.outputs.shipping }}
      sharedkernel: ${{ steps.filter.outputs.sharedkernel }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            orders:
              - 'src/Modules/Orders/**'
            inventory:
              - 'src/Modules/Inventory/**'
            shipping:
              - 'src/Modules/Shipping/**'
            sharedkernel:
              - 'src/SharedKernel/**'

  build-and-test:
    needs: detect-changes
    runs-on: ubuntu-latest
    strategy:
      matrix:
        module:
          - name: Orders
            path: src/Modules/Orders
            changed: ${{ needs.detect-changes.outputs.orders }}
          - name: Inventory
            path: src/Modules/Inventory
            changed: ${{ needs.detect-changes.outputs.inventory }}
          - name: Shipping
            path: src/Modules/Shipping
            changed: ${{ needs.detect-changes.outputs.shipping }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Restore
        run: dotnet restore

      - name: Build ${{ matrix.module.name }}
        if: matrix.module.changed == 'true'
        run: dotnet build ${{ matrix.module.path }} --no-restore

      - name: Test ${{ matrix.module.name }}
        if: matrix.module.changed == 'true'
        run: dotnet test tests/${{ matrix.module.name }}.Tests --no-restore

  integration-tests:
    needs: build-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'
      - run: dotnet test tests/Integration.Tests
```

### Publish Packages Workflow

```yaml
# .github/workflows/publish-packages.yml
name: Publish Packages

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
  workflow_dispatch:
    inputs:
      module:
        description: 'Module to publish (or "all")'
        required: true
        default: 'all'
      prerelease:
        description: 'Publish as prerelease'
        type: boolean
        default: true

env:
  NUGET_SOURCE: https://nuget.pkg.github.com/${{ github.repository_owner }}/index.json

jobs:
  determine-versions:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Determine changed modules and versions
        id: set-matrix
        run: |
          # Script to detect which modules changed and need publishing
          # Reads version from each .csproj, checks if that version exists in feed
          # Outputs matrix of modules to publish
          echo "matrix={...}" >> $GITHUB_OUTPUT

  publish:
    needs: determine-versions
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.determine-versions.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Pack ${{ matrix.project }}
        run: |
          VERSION=${{ matrix.version }}
          if [ "${{ inputs.prerelease }}" == "true" ]; then
            VERSION="${VERSION}-preview.${{ github.run_number }}"
          fi
          dotnet pack ${{ matrix.path }} \
            -c Release \
            -p:Version=$VERSION \
            -o ./artifacts

      - name: Publish to GitHub Packages
        run: |
          dotnet nuget push ./artifacts/*.nupkg \
            --source ${{ env.NUGET_SOURCE }} \
            --api-key ${{ secrets.GITHUB_TOKEN }} \
            --skip-duplicate
```

### Full Release Bundle Workflow

```yaml
# .github/workflows/release-bundle.yml
name: Release Bundle

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 2024.2.0)'
        required: true

jobs:
  build-bundle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Restore from internal feed
        run: |
          dotnet nuget add source ${{ env.NUGET_SOURCE }} \
            -n github \
            -u ${{ github.actor }} \
            -p ${{ secrets.GITHUB_TOKEN }} \
            --store-password-in-clear-text
          dotnet restore

      - name: Publish Host
        run: |
          dotnet publish src/Host/Host.csproj \
            -c Release \
            -o ./publish \
            -p:Version=${{ inputs.version || github.ref_name }}

      - name: Create release manifest
        run: |
          # Generate manifest listing all module versions included
          cat > ./publish/manifest.json << EOF
          {
            "version": "${{ inputs.version || github.ref_name }}",
            "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "modules": {
              $(dotnet list src/Host/Host.csproj package --format json | jq -r '.projects[].frameworks[].topLevelPackages[] | select(.id | startswith("YourCompany.")) | "\"\(.id)\": \"\(.resolvedVersion)\""' | paste -sd,)
            }
          }
          EOF

      - name: Package bundle
        run: |
          cd publish
          zip -r ../release-${{ inputs.version || github.ref_name }}.zip .

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-bundle
          path: release-*.zip

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
          files: release-*.zip
          generate_release_notes: true
```

### Hotfix Single Module Workflow

```yaml
# .github/workflows/hotfix-module.yml
name: Hotfix Module

on:
  workflow_dispatch:
    inputs:
      module:
        description: 'Module to hotfix'
        required: true
        type: choice
        options:
          - Orders
          - Inventory
          - Shipping
      release_branch:
        description: 'Release branch (e.g., release/2024.1)'
        required: true
      bump_type:
        description: 'Version bump type'
        required: true
        type: choice
        options:
          - patch
          - minor

jobs:
  hotfix:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.release_branch }}

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Bump version
        id: bump
        run: |
          MODULE_PATH="src/Modules/${{ inputs.module }}"
          # Find all csproj files in module and bump version
          for proj in $(find $MODULE_PATH -name "*.csproj"); do
            CURRENT=$(grep -oP '(?<=<Version>)[^<]+' $proj)
            # Bump logic here based on ${{ inputs.bump_type }}
            NEW_VERSION="..."
            sed -i "s/<Version>$CURRENT</<Version>$NEW_VERSION</" $proj
            echo "Bumped $proj from $CURRENT to $NEW_VERSION"
          done

      - name: Build and test
        run: |
          dotnet build src/Modules/${{ inputs.module }}
          dotnet test tests/${{ inputs.module }}.Tests

      - name: Pack and publish
        run: |
          for proj in $(find src/Modules/${{ inputs.module }} -name "*.csproj"); do
            dotnet pack $proj -c Release -o ./artifacts
          done
          dotnet nuget push ./artifacts/*.nupkg \
            --source ${{ env.NUGET_SOURCE }} \
            --api-key ${{ secrets.GITHUB_TOKEN }}

      - name: Commit version bump
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add -A
          git commit -m "chore(${{ inputs.module }}): bump version for hotfix"
          git push
```

---

## Release Process

### Major Release (Full Bundle)

```
1. All development complete on main
2. Cut release branch:
   git checkout -b release/2024.2
   git push -u origin release/2024.2

3. CI publishes all packages as stable (non-preview)

4. QA tests release branch

5. Tag when approved:
   git tag v2024.2.0
   git push --tags

6. release-bundle workflow creates full bundle

7. Deploy bundle to customers
```

### Hotfix (Single Module)

```
1. Bug reported in Orders module at customer site
2. Customer is on release/2024.1

3. Fix bug on main:
   git checkout -b fix/order-calculation-bug
   # fix code
   # bump Orders.Core version 2.3.1 → 2.3.2
   git commit -m "fix(orders): correct calculation"
   # PR and merge to main

4. Cherry-pick to release branch:
   git checkout release/2024.1
   git cherry-pick <commit-hash>
   git push

5. Run hotfix-module workflow:
   - Module: Orders
   - Release branch: release/2024.1
   - Bump type: patch

6. CI publishes:
   - YourCompany.Orders.Core 2.3.2
   - YourCompany.Orders.Infrastructure 2.3.2

7. Provide customer with updated DLLs:
   - Orders.Core.dll
   - Orders.Infrastructure.dll

   They can drop-in replace without touching other modules
   (as long as Orders.Contracts didn't change)
```

### Contract Breaking Change (Coordinated Release)

```
1. Breaking change needed in Orders.Contracts

2. Bump MAJOR version:
   Orders.Contracts 2.x → 3.0.0

3. Update all consumers in same PR:
   - Inventory.Core (references Orders.Contracts)
   - Shipping.Core (references Orders.Contracts)
   - Host

4. All affected modules get version bumps

5. This becomes a coordinated release:
   - Cannot hotfix Orders independently until all
     consumers are also deployed with new versions
```

---

## Manifest & Compatibility

### Release Manifest

Every bundle includes a manifest:

```json
{
  "version": "2024.2.0",
  "built": "2024-06-15T10:30:00Z",
  "commit": "abc123",
  "modules": {
    "YourCompany.SharedKernel": "1.2.0",
    "YourCompany.Orders.Contracts": "2.4.0",
    "YourCompany.Orders.Core": "2.4.1",
    "YourCompany.Orders.Infrastructure": "2.4.0",
    "YourCompany.Inventory.Contracts": "1.1.0",
    "YourCompany.Inventory.Core": "1.1.3",
    "YourCompany.Inventory.Infrastructure": "1.1.2",
    "YourCompany.Shipping.Contracts": "3.0.0",
    "YourCompany.Shipping.Core": "3.0.1",
    "YourCompany.Shipping.Infrastructure": "3.0.0"
  }
}
```

### Compatibility Matrix

Track which module versions are compatible:

```json
{
  "compatibility": {
    "Orders.Core": {
      "2.4.*": {
        "requires": {
          "Orders.Contracts": "[2.4.0, 3.0.0)",
          "SharedKernel": "[1.2.0, 2.0.0)"
        }
      }
    },
    "Inventory.Core": {
      "1.1.*": {
        "requires": {
          "Inventory.Contracts": "[1.1.0, 2.0.0)",
          "Orders.Contracts": "[2.0.0, 3.0.0)",
          "SharedKernel": "[1.2.0, 2.0.0)"
        }
      }
    }
  }
}
```

---

## Directory.Build.props

Shared settings at solution root:

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>

    <!-- Package metadata -->
    <Authors>YourCompany</Authors>
    <Company>YourCompany</Company>
    <PackageProjectUrl>https://github.com/yourorg/yourrepo</PackageProjectUrl>
    <RepositoryUrl>https://github.com/yourorg/yourrepo</RepositoryUrl>
    <RepositoryType>git</RepositoryType>
  </PropertyGroup>

  <!-- Central package management -->
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
</Project>
```

---

## Customer-Specific Releases

When customers have unique release versions that diverge from mainline.

### Branch Strategy for Customer Releases

```
main
  │
  ├──→ release/2024.2           (standard release)
  │     │
  │     └──→ customer/acme-2024.2    (ACME's fork of 2024.2)
  │           ├── Custom config
  │           ├── Specific module patches
  │           └── Tags: acme-2024.2.1, acme-2024.2.2
  │
  └──→ release/2024.3
        │
        └──→ customer/bigcorp-2024.3
```

### Customer Manifest

Track each customer's exact module versions:

```json
// customers/acme/manifest.json
{
  "customer": "ACME Corp",
  "customerId": "acme",
  "basedOn": "release/2024.2",
  "installedVersion": "acme-2024.2.3",
  "deployedAt": "2024-07-15T14:30:00Z",
  "modules": {
    "YourCompany.SharedKernel": "1.2.0",
    "YourCompany.Orders.Contracts": "2.4.0",
    "YourCompany.Orders.Core": "2.4.3",        // Patched for ACME
    "YourCompany.Orders.Infrastructure": "2.4.0",
    "YourCompany.Inventory.Contracts": "1.1.0",
    "YourCompany.Inventory.Core": "1.1.5",     // Patched for ACME
    "YourCompany.Inventory.Infrastructure": "1.1.2",
    "YourCompany.Shipping.Contracts": "3.0.0",
    "YourCompany.Shipping.Core": "3.0.1",
    "YourCompany.Shipping.Infrastructure": "3.0.0"
  },
  "pendingUpdates": [],
  "history": [
    {
      "version": "acme-2024.2.2",
      "date": "2024-06-20",
      "changes": ["Orders.Core 2.4.2 → 2.4.3: fix calculation bug"]
    }
  ]
}
```

### Updating a Customer

```
1. Customer ACME reports bug in Orders module
2. They're on customer/acme-2024.2 branch

3. Check if fix already exists:
   - Is Orders.Core 2.4.4+ on release/2024.2?
   - If yes, can we just update their manifest?

4. If fix doesn't exist:
   a. Fix on main, cherry-pick to release/2024.2
   b. Cherry-pick to customer/acme-2024.2
   c. Bump Orders.Core version
   d. Run compatibility check
   e. Build module update package
   f. Update customer manifest

5. Deliver update to customer
```

---

## Automated Compatibility Checking

Prevent deploying incompatible module combinations.

### Compatibility Database

```json
// compatibility-db.json
{
  "modules": {
    "Orders.Contracts": {
      "2.4.0": { "minSharedKernel": "1.2.0", "maxSharedKernel": "2.0.0" },
      "3.0.0": { "minSharedKernel": "1.3.0", "maxSharedKernel": "2.0.0" }
    },
    "Orders.Core": {
      "2.4.0": { "Orders.Contracts": "2.4.*", "SharedKernel": "1.2.*" },
      "2.4.1": { "Orders.Contracts": "2.4.*", "SharedKernel": "1.2.*" },
      "2.4.2": { "Orders.Contracts": "2.4.*", "SharedKernel": "1.2.*" }
    },
    "Inventory.Core": {
      "1.1.0": {
        "Inventory.Contracts": "1.1.*",
        "Orders.Contracts": "[2.0.0, 3.0.0)",
        "SharedKernel": "1.2.*"
      }
    }
  }
}
```

### Compatibility Checker Tool

```csharp
// tools/CompatibilityChecker/Program.cs
public class CompatibilityChecker
{
    public CompatibilityResult Check(
        CustomerManifest current,
        Dictionary<string, string> proposedUpdates)
    {
        var result = new CompatibilityResult();
        var newManifest = current.Modules.ToDictionary(k => k.Key, v => v.Value);

        // Apply proposed updates
        foreach (var update in proposedUpdates)
            newManifest[update.Key] = update.Value;

        // Check each module's dependencies
        foreach (var (module, version) in newManifest)
        {
            var requirements = GetRequirements(module, version);

            foreach (var (dependency, versionRange) in requirements)
            {
                if (!newManifest.TryGetValue(dependency, out var depVersion))
                {
                    result.AddError($"{module} requires {dependency} but it's not installed");
                    continue;
                }

                if (!SemVer.Satisfies(depVersion, versionRange))
                {
                    result.AddError(
                        $"{module}@{version} requires {dependency}@{versionRange}, " +
                        $"but {depVersion} is installed");

                    // Suggest resolution
                    var compatible = FindCompatibleVersion(dependency, versionRange);
                    if (compatible != null)
                        result.AddSuggestion($"Update {dependency} to {compatible}");
                }
            }
        }

        // Check for contract breaking changes
        foreach (var update in proposedUpdates.Where(u => u.Key.EndsWith(".Contracts")))
        {
            var currentVersion = current.Modules.GetValueOrDefault(update.Key);
            if (currentVersion != null && IsMajorBump(currentVersion, update.Value))
            {
                result.AddWarning(
                    $"BREAKING: {update.Key} {currentVersion} → {update.Value}. " +
                    "All consumers must be updated.");

                var consumers = FindConsumers(update.Key);
                result.AddRequiredUpdates(consumers);
            }
        }

        return result;
    }
}

public class CompatibilityResult
{
    public bool IsCompatible => !Errors.Any();
    public List<string> Errors { get; } = [];
    public List<string> Warnings { get; } = [];
    public List<string> Suggestions { get; } = [];
    public List<string> RequiredUpdates { get; } = [];
}
```

### GitHub Action for Compatibility Check

```yaml
# .github/workflows/check-compatibility.yml
name: Check Module Compatibility

on:
  workflow_dispatch:
    inputs:
      customer:
        description: 'Customer ID'
        required: true
      updates:
        description: 'Updates JSON (e.g., {"Orders.Core": "2.4.5"})'
        required: true

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Load customer manifest
        id: manifest
        run: |
          MANIFEST=$(cat customers/${{ inputs.customer }}/manifest.json)
          echo "manifest=$MANIFEST" >> $GITHUB_OUTPUT

      - name: Run compatibility check
        id: check
        run: |
          dotnet run --project tools/CompatibilityChecker -- \
            --manifest '${{ steps.manifest.outputs.manifest }}' \
            --updates '${{ inputs.updates }}' \
            --output result.json

          RESULT=$(cat result.json)
          echo "result=$RESULT" >> $GITHUB_OUTPUT

          if [ "$(jq -r '.isCompatible' result.json)" != "true" ]; then
            echo "::error::Compatibility check failed"
            jq -r '.errors[]' result.json | while read err; do
              echo "::error::$err"
            done
            exit 1
          fi

      - name: Output warnings
        if: success()
        run: |
          jq -r '.warnings[]' result.json | while read warn; do
            echo "::warning::$warn"
          done

      - name: Show required updates
        if: failure()
        run: |
          echo "## Required Updates" >> $GITHUB_STEP_SUMMARY
          jq -r '.requiredUpdates[]' result.json >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "## Suggestions" >> $GITHUB_STEP_SUMMARY
          jq -r '.suggestions[]' result.json >> $GITHUB_STEP_SUMMARY
```

### Assembly-Level Compatibility Attributes

Embed compatibility info in assemblies:

```csharp
// In Orders.Core.csproj
<ItemGroup>
  <AssemblyAttribute Include="System.Reflection.AssemblyMetadataAttribute">
    <_Parameter1>CompatibleWith.Orders.Contracts</_Parameter1>
    <_Parameter2>[2.4.0, 3.0.0)</_Parameter2>
  </AssemblyAttribute>
  <AssemblyAttribute Include="System.Reflection.AssemblyMetadataAttribute">
    <_Parameter1>CompatibleWith.SharedKernel</_Parameter1>
    <_Parameter2>[1.2.0, 2.0.0)</_Parameter2>
  </AssemblyAttribute>
</ItemGroup>
```

Runtime validation on startup:

```csharp
public class CompatibilityValidator : IHostedService
{
    public Task StartAsync(CancellationToken ct)
    {
        var assemblies = AppDomain.CurrentDomain.GetAssemblies()
            .Where(a => a.GetName().Name?.StartsWith("YourCompany.") == true);

        foreach (var assembly in assemblies)
        {
            var compatAttrs = assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
                .Where(a => a.Key.StartsWith("CompatibleWith."));

            foreach (var attr in compatAttrs)
            {
                var dependency = attr.Key.Replace("CompatibleWith.", "");
                var versionRange = attr.Value;

                var depAssembly = assemblies.FirstOrDefault(
                    a => a.GetName().Name == $"YourCompany.{dependency}");

                if (depAssembly == null)
                    throw new Exception($"{assembly.GetName().Name} requires {dependency}");

                var depVersion = depAssembly.GetName().Version;
                if (!SemVer.Satisfies(depVersion, versionRange))
                {
                    throw new Exception(
                        $"{assembly.GetName().Name} requires {dependency}@{versionRange}, " +
                        $"but {depVersion} is loaded");
                }
            }
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;
}
```

---

## NSIS Installer Strategy

### Installer Types

| Type | Use Case | Contents |
|------|----------|----------|
| **Full Installer** | Initial install, major upgrades | Everything |
| **Module Update** | Hotfix, minor updates | Single module DLLs |
| **Patch Bundle** | Multiple module updates | Selected modules |

### Directory Structure (Installed)

```
C:\Program Files\YourProduct\
├── YourProduct.exe                    # Host
├── manifest.json                       # Current versions
├── Modules/
│   ├── Orders/
│   │   ├── Orders.Contracts.dll
│   │   ├── Orders.Core.dll
│   │   └── Orders.Infrastructure.dll
│   ├── Inventory/
│   │   ├── Inventory.Contracts.dll
│   │   ├── Inventory.Core.dll
│   │   └── Inventory.Infrastructure.dll
│   └── Shipping/
│       └── ...
├── Shared/
│   └── SharedKernel.dll
└── Updates/
    └── (staging area for updates)
```

### Full Installer NSIS Script

```nsis
# full-installer.nsi
!include "MUI2.nsh"

Name "YourProduct ${VERSION}"
OutFile "YourProduct-${VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES\YourProduct"

# Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

Section "Core" SecCore
  SetOutPath "$INSTDIR"
  File "publish\YourProduct.exe"
  File "publish\manifest.json"
  File "publish\appsettings.json"
SectionEnd

Section "Shared Components" SecShared
  SetOutPath "$INSTDIR\Shared"
  File "publish\Shared\*.dll"
SectionEnd

Section "Orders Module" SecOrders
  SetOutPath "$INSTDIR\Modules\Orders"
  File "publish\Modules\Orders\*.dll"
SectionEnd

Section "Inventory Module" SecInventory
  SetOutPath "$INSTDIR\Modules\Inventory"
  File "publish\Modules\Inventory\*.dll"
SectionEnd

Section "Shipping Module" SecShipping
  SetOutPath "$INSTDIR\Modules\Shipping"
  File "publish\Modules\Shipping\*.dll"
SectionEnd

# Verify after install
Section "-Verify"
  nsExec::ExecToLog '"$INSTDIR\YourProduct.exe" --verify-compatibility'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "Compatibility check failed. Installation may be corrupt."
    Abort
  ${EndIf}
SectionEnd
```

### Module Update Installer

```nsis
# module-update.nsi
!include "MUI2.nsh"
!include "FileFunc.nsh"

Name "YourProduct Module Update"
OutFile "YourProduct-${MODULE}-${VERSION}-Update.exe"

Var INSTALL_DIR
Var CURRENT_MANIFEST
Var BACKUP_DIR

# Find existing installation
Function .onInit
  ReadRegStr $INSTALL_DIR HKLM "Software\YourProduct" "InstallDir"
  ${If} $INSTALL_DIR == ""
    MessageBox MB_OK|MB_ICONSTOP "YourProduct is not installed."
    Abort
  ${EndIf}

  # Read current manifest
  FileOpen $0 "$INSTALL_DIR\manifest.json" r
  FileRead $0 $CURRENT_MANIFEST
  FileClose $0
FunctionEnd

Section "Compatibility Check" SecCheck
  # Extract checker and run it
  SetOutPath "$TEMP\YourProductUpdate"
  File "tools\CompatibilityChecker.exe"
  File "update-manifest.json"

  nsExec::ExecToLog '"$TEMP\YourProductUpdate\CompatibilityChecker.exe" \
    --current "$INSTALL_DIR\manifest.json" \
    --update "update-manifest.json"'
  Pop $0

  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "This update is not compatible with your installation.$\n$\nPlease contact support."
    Abort
  ${EndIf}
SectionEnd

Section "Backup" SecBackup
  # Backup current module
  StrCpy $BACKUP_DIR "$INSTALL_DIR\Backups\${MODULE}-${{TIMESTAMP}}"
  CreateDirectory $BACKUP_DIR
  CopyFiles "$INSTALL_DIR\Modules\${MODULE}\*.*" $BACKUP_DIR
SectionEnd

Section "Update ${MODULE}" SecUpdate
  # Stop the application if running
  nsExec::Exec 'taskkill /F /IM YourProduct.exe'
  Sleep 1000

  # Update module files
  SetOutPath "$INSTALL_DIR\Modules\${MODULE}"
  File "modules\${MODULE}\*.dll"

  # Update manifest
  SetOutPath "$INSTALL_DIR"
  File "manifest.json"
SectionEnd

Section "Verify" SecVerify
  nsExec::ExecToLog '"$INSTALL_DIR\YourProduct.exe" --verify-compatibility'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_YESNO "Compatibility check failed. Restore backup?" IDYES restore IDNO done
    restore:
      CopyFiles "$BACKUP_DIR\*.*" "$INSTALL_DIR\Modules\${MODULE}"
      # Restore original manifest
    done:
  ${EndIf}
SectionEnd

Section "-Cleanup"
  RMDir /r "$TEMP\YourProductUpdate"
SectionEnd

# Rollback function
Function Rollback
  CopyFiles "$BACKUP_DIR\*.*" "$INSTALL_DIR\Modules\${MODULE}"
  MessageBox MB_OK "Update rolled back. Previous version restored."
FunctionEnd
```

### GitHub Action to Build Installers

```yaml
# .github/workflows/build-installer.yml
name: Build Installer

on:
  workflow_dispatch:
    inputs:
      type:
        description: 'Installer type'
        type: choice
        options:
          - full
          - module-update
          - patch-bundle
      customer:
        description: 'Customer ID (optional, for customer-specific build)'
        required: false
      modules:
        description: 'Modules to include (comma-separated, for module-update/patch-bundle)'
        required: false
      version:
        description: 'Version tag'
        required: true

jobs:
  build-full:
    if: inputs.type == 'full'
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Restore and publish
        run: |
          dotnet restore
          dotnet publish src/Host/Host.csproj -c Release -o publish

      - name: Organize modules
        shell: pwsh
        run: |
          # Move DLLs to module folders
          $modules = @('Orders', 'Inventory', 'Shipping')
          foreach ($m in $modules) {
            New-Item -ItemType Directory -Force -Path "publish/Modules/$m"
            Move-Item "publish/*$m*.dll" "publish/Modules/$m/"
          }
          New-Item -ItemType Directory -Force -Path "publish/Shared"
          Move-Item "publish/SharedKernel.dll" "publish/Shared/"

      - name: Generate manifest
        shell: pwsh
        run: |
          $manifest = @{
            version = "${{ inputs.version }}"
            built = (Get-Date -Format "o")
            modules = @{}
          }
          Get-ChildItem -Recurse -Filter "*.dll" publish/Modules, publish/Shared | ForEach-Object {
            $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($_.FullName).FileVersion
            $manifest.modules[$_.BaseName] = $version
          }
          $manifest | ConvertTo-Json -Depth 10 | Set-Content "publish/manifest.json"

      - name: Build NSIS installer
        uses: joncloud/makensis-action@v4
        with:
          script-file: installer/full-installer.nsi
          arguments: /DVERSION=${{ inputs.version }}

      - name: Upload installer
        uses: actions/upload-artifact@v4
        with:
          name: full-installer
          path: installer/*.exe

  build-module-update:
    if: inputs.type == 'module-update'
    runs-on: windows-latest
    strategy:
      matrix:
        module: ${{ fromJson(format('["{0}"]', replace(inputs.modules, ',', '","'))) }}
    steps:
      - uses: actions/checkout@v4

      - name: Get customer manifest
        if: inputs.customer != ''
        run: |
          cp customers/${{ inputs.customer }}/manifest.json current-manifest.json

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Build module
        run: |
          dotnet build src/Modules/${{ matrix.module }} -c Release

      - name: Run compatibility check
        run: |
          dotnet run --project tools/CompatibilityChecker -- \
            --current current-manifest.json \
            --module ${{ matrix.module }} \
            --version ${{ inputs.version }}

      - name: Prepare update package
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Force -Path "update/modules/${{ matrix.module }}"
          Copy-Item "src/Modules/${{ matrix.module }}/**/bin/Release/**/*.dll" "update/modules/${{ matrix.module }}/"

          # Create update manifest
          $updateManifest = @{
            module = "${{ matrix.module }}"
            version = "${{ inputs.version }}"
            files = (Get-ChildItem -Recurse update/modules/${{ matrix.module }} -Filter "*.dll").Name
          }
          $updateManifest | ConvertTo-Json | Set-Content "update/update-manifest.json"

      - name: Build NSIS update installer
        uses: joncloud/makensis-action@v4
        with:
          script-file: installer/module-update.nsi
          arguments: /DMODULE=${{ matrix.module }} /DVERSION=${{ inputs.version }}

      - name: Upload update installer
        uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.module }}-update
          path: installer/*-Update.exe
```

### Update Manifest Format

```json
// update-manifest.json (included in module update installer)
{
  "module": "Orders",
  "version": "2.4.5",
  "previousVersions": ["2.4.4", "2.4.3", "2.4.2", "2.4.1", "2.4.0"],
  "requires": {
    "Orders.Contracts": "[2.4.0, 3.0.0)",
    "SharedKernel": "[1.2.0, 2.0.0)"
  },
  "files": [
    { "name": "Orders.Core.dll", "version": "2.4.5", "hash": "sha256:abc123..." },
    { "name": "Orders.Infrastructure.dll", "version": "2.4.5", "hash": "sha256:def456..." }
  ],
  "changelog": [
    "Fixed calculation bug in order totals",
    "Improved performance of order queries"
  ],
  "rollbackSupported": true
}
```

---

## Snowball Prevention

When a contract change triggers cascading updates:

### Impact Analysis Tool

```csharp
public class ImpactAnalyzer
{
    public ImpactReport Analyze(string module, string changeType)
    {
        var report = new ImpactReport { Module = module, ChangeType = changeType };

        if (changeType == "contract-breaking")
        {
            // Find all modules that depend on this contract
            var consumers = _dependencyGraph
                .GetDependents($"{module}.Contracts")
                .ToList();

            report.DirectlyAffected = consumers;

            // Find transitive dependents
            var allAffected = new HashSet<string>(consumers);
            var queue = new Queue<string>(consumers);

            while (queue.Count > 0)
            {
                var current = queue.Dequeue();
                var dependents = _dependencyGraph.GetDependents(current);

                foreach (var dep in dependents.Where(d => allAffected.Add(d)))
                    queue.Enqueue(dep);
            }

            report.TransitivelyAffected = allAffected.Except(consumers).ToList();
            report.RequiresCoordinatedRelease = true;
            report.EstimatedScope = allAffected.Count > 3 ? "Large" : "Medium";
        }

        return report;
    }
}
```

### GitHub Action for Impact Analysis

```yaml
# .github/workflows/impact-analysis.yml
name: Impact Analysis

on:
  pull_request:
    paths:
      - 'src/Modules/**/Contracts/**'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect contract changes
        id: changes
        run: |
          CHANGED=$(git diff --name-only origin/main...HEAD | grep "Contracts" | head -1)
          MODULE=$(echo $CHANGED | sed 's/.*Modules\/\([^/]*\).*/\1/')
          echo "module=$MODULE" >> $GITHUB_OUTPUT

          # Check if breaking change (major version bump)
          BEFORE=$(git show origin/main:src/Modules/$MODULE/$MODULE.Contracts/$MODULE.Contracts.csproj | grep -oP '(?<=<Version>)[^<]+')
          AFTER=$(grep -oP '(?<=<Version>)[^<]+' src/Modules/$MODULE/$MODULE.Contracts/$MODULE.Contracts.csproj)

          if [ "${BEFORE%%.*}" != "${AFTER%%.*}" ]; then
            echo "breaking=true" >> $GITHUB_OUTPUT
          else
            echo "breaking=false" >> $GITHUB_OUTPUT
          fi

      - name: Run impact analysis
        if: steps.changes.outputs.breaking == 'true'
        run: |
          dotnet run --project tools/ImpactAnalyzer -- \
            --module ${{ steps.changes.outputs.module }} \
            --change-type contract-breaking \
            --output impact-report.md

      - name: Comment on PR
        if: steps.changes.outputs.breaking == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('impact-report.md', 'utf8');
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## ⚠️ Breaking Contract Change Detected\n\n${report}`
            });
```

---

## Summary

| Aspect | Approach |
|--------|----------|
| **Versioning** | SemVer per module, version in .csproj |
| **Contracts** | Separate `*.Contracts` projects, versioned carefully |
| **Packages** | Internal NuGet feed (GitHub Packages) |
| **Branching** | Trunk-based + release branches + customer branches |
| **CI** | Per-module builds, change detection |
| **Full Release** | Tag triggers bundle build |
| **Hotfix** | Cherry-pick to release branch, publish affected modules only |
| **Breaking Changes** | MAJOR bump, coordinated release required |
| **Customer Releases** | Customer-specific branches forked from release |
| **Compatibility** | Automated checker, assembly attributes, runtime validation |
| **Installers** | NSIS: full, module-update, patch-bundle |
| **Snowball Prevention** | Impact analysis on contract changes |
