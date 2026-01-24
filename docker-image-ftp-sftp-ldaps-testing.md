# Integration Test Services Setup Guide

## Overview

This document describes the setup and usage of containerized test services (FTP, SFTP, LDAPS) for integration testing of our PVD system communication layers during the .NET Framework 4.8 to .NET 8+ migration.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Initial Setup](#initial-setup)
5. [Daily Usage](#daily-usage)
6. [Test Development](#test-development)
7. [CI/CD Integration](#cicd-integration)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Configuration](#advanced-configuration)

---

## Prerequisites

### Required Software
- **Podman Desktop** (or Docker Desktop) - [Download here](https://podman-desktop.io/)
- **.NET 8 SDK** - [Download here](https://dotnet.microsoft.com/download)
- **PowerShell 5.1+** (comes with Windows)
- **Visual Studio 2022** or **JetBrains Rider**

### Required Permissions
- Administrator access for one-time hosts file setup
- Ability to run containers on your Windows development machine

---

## Architecture

### Container Services

The `integration-test-services` container runs three services simultaneously using `supervisord`:

1. **vsftpd** (FTP server) - Port 21
2. **OpenSSH** (SFTP server) - Port 22
3. **OpenLDAP** (LDAPS server) - Port 636

All services run with test credentials and self-signed certificates suitable for integration testing.

### Test Framework

- **xUnit** - Modern .NET test framework (works with both .NET Framework 4.8 and .NET 8+)
- **FluentFTP** - FTP client library
- **SSH.NET** - SFTP client library
- **Novell.Directory.Ldap** - LDAP client library

### Service Hostnames

Instead of `localhost`, we use service-specific hostnames for clarity:

- `test-ftp.pvd.local:21` - FTP service
- `test-sftp.pvd.local:22` - SFTP service
- `test-ldap.pvd.local:636` - LDAPS service

---

## Project Structure
```
YourSolution/
├── src/
│   └── YourProject/
│       └── YourProject.csproj
│
├── tests/
│   └── IntegrationTests/
│       ├── IntegrationTests.csproj
│       ├── TestServicesFixture.cs
│       ├── FtpIntegrationTests.cs
│       ├── SftpIntegrationTests.cs
│       ├── LdapIntegrationTests.cs
│       └── appsettings.IntegrationTests.json (optional)
│
├── docker/                          # Container configuration
│   ├── Dockerfile.test
│   └── config/
│       ├── vsftpd.conf
│       ├── sshd_config
│       ├── supervisord.conf
│       ├── ldap-init.ldif
│       └── generate-certs.sh
│
├── scripts/                         # Helper scripts
│   ├── test.ps1                    # Main test runner
│   ├── build-test-container.ps1
│   ├── run-test-services.ps1
│   ├── stop-test-services.ps1
│   ├── setup-hosts.ps1
│   └── remove-hosts.ps1
│
├── .github/
│   └── workflows/
│       └── integration-tests.yml
│
└── README-IntegrationTests.md      # This file
```

---

## Initial Setup

### 1. Configure Hosts File (One-Time, Requires Admin)

Run PowerShell as Administrator:
```powershell
cd YourSolution
.\scripts\setup-hosts.ps1
```

This adds entries to `C:\Windows\System32\drivers\etc\hosts`:
```
127.0.0.1    test-ftp.pvd.local
127.0.0.1    test-sftp.pvd.local
127.0.0.1    test-ldap.pvd.local
```

### 2. Verify Podman Installation
```powershell
podman --version
# Should output: podman version 4.x.x or later
```

If not installed, download and install [Podman Desktop](https://podman-desktop.io/).

### 3. Initial Build and Test
```powershell
# This will:
# 1. Build the test services container
# 2. Start the container
# 3. Run all integration tests
.\scripts\test.ps1
```

First run takes ~2-3 minutes (building container). Subsequent runs are much faster (~15 seconds).

---

## Daily Usage

### Starting Your Development Session
```powershell
# Start test services
.\scripts\run-test-services.ps1
```

Or use the all-in-one test runner:
```powershell
.\scripts\test.ps1
```

### Running Tests

**From Command Line:**
```powershell
# Run all integration tests
dotnet test

# Run specific test class
dotnet test --filter "FtpIntegrationTests"

# Run specific test method
dotnet test --filter "Should_Upload_File_Via_FTP"

# Verbose output
dotnet test --logger "console;verbosity=detailed"
```

**From Visual Studio:**
- Open Test Explorer (Test → Test Explorer)
- Right-click test/class/project → Run Tests

**From Rider:**
- Click the green arrow next to any test method or class
- Or use Test Explorer tool window

### Stopping Services
```powershell
# Stop the container
.\scripts\stop-test-services.ps1

# Or leave it running - tests will reuse it for faster iteration
```

### Rebuilding After Container Changes
```powershell
# After modifying Dockerfile.test or config files
.\scripts\test.ps1 -Rebuild
```

---

## Test Development

### Test Project Configuration

**IntegrationTests.csproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <!-- When migrating to .NET 8+: <TargetFramework>net8.0</TargetFramework> -->
    <IsPackable>false</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="xunit" Version="2.6.6" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.5.6">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
    <PackageReference Include="FluentFTP" Version="49.0.2" />
    <PackageReference Include="SSH.NET" Version="2024.1.0" />
    <PackageReference Include="Novell.Directory.Ldap.NETStandard" Version="3.6.0" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\YourProject\YourProject.csproj" />
  </ItemGroup>

</Project>
```

### Test Credentials

All test services use these credentials:

**FTP/SFTP:**
- Username: `testuser`
- Password: `testpass123`
- Home directory: `/home/testuser`

**LDAPS:**
- Bind DN: `cn=admin,dc=test,dc=local`
- Password: `admin`
- Base DN: `dc=test,dc=local`

### Writing Tests

**Example FTP Test:**
```csharp
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using FluentFTP;
using Xunit;

namespace IntegrationTests
{
    [Collection("Integration Tests")]
    public class FtpIntegrationTests : IClassFixture<TestServicesFixture>
    {
        private readonly TestServicesFixture _fixture;

        public FtpIntegrationTests(TestServicesFixture fixture)
        {
            _fixture = fixture;
        }

        [Fact]
        public async Task Should_Upload_File_Via_FTP()
        {
            // Arrange
            var testFileName = $"test_{Guid.NewGuid()}.txt";
            var testContent = "Hello from integration test!";
            var bytes = Encoding.UTF8.GetBytes(testContent);

            using (var client = new FtpClient(_fixture.FtpHost, 
                _fixture.FtpUsername, _fixture.FtpPassword))
            {
                await client.ConnectAsync();

                // Act
                using (var stream = new MemoryStream(bytes))
                {
                    var result = await client.UploadAsync(stream, testFileName);
                    
                    // Assert
                    Assert.Equal(FtpStatus.Success, result);
                    Assert.True(await client.FileExistsAsync(testFileName));
                }

                // Cleanup
                await client.DeleteFileAsync(testFileName);
            }
        }
    }
}
```

### Test Fixture Lifecycle

The `TestServicesFixture` manages the container lifecycle:

1. **First test run:** Checks if container exists, builds if needed, starts container
2. **Subsequent runs:** Reuses running container for fast iteration
3. **CI environment:** Automatically cleans up after tests complete

This means:
- Local development: Container stays running between test runs (fast!)
- CI/CD: Container is cleaned up automatically (clean slate)

---

## CI/CD Integration

### GitHub Actions Workflow

**.github/workflows/integration-tests.yml:**
```yaml
name: Integration Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    paths:
      - 'src/**'
      - 'tests/**'
      - 'docker/**'

jobs:
  integration-tests:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.x'
    
    - name: Restore dependencies
      run: dotnet restore
    
    - name: Build
      run: dotnet build --configuration Release --no-restore
    
    - name: Run integration tests
      run: dotnet test --configuration Release --no-build --logger "trx;LogFileName=test-results.trx"
      env:
        CI: true
    
    - name: Publish test results
      uses: EnricoMi/publish-unit-test-result-action@v2
      if: always()
      with:
        files: '**/test-results.trx'
```

### Running on Build Server

If you have an on-premises build server:

1. Ensure Podman or Docker is installed
2. Add build agent to docker/podman group
3. Tests will automatically build and run the container

---

## Troubleshooting

### Container Won't Start

**Check if ports are in use:**
```powershell
netstat -ano | findstr ":21 :22 :636"
```

**View container logs:**
```powershell
podman logs integration-test-services
```

**Force rebuild:**
```powershell
.\scripts\test.ps1 -Clean
.\scripts\test.ps1 -Rebuild
```

### Tests Can't Connect to Services

**Verify container is running:**
```powershell
podman ps --filter name=integration-test-services
```

**Verify hosts file entries:**
```powershell
Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String "pvd.local"
```

**Test connectivity manually:**
```powershell
# Test FTP
Test-NetConnection -ComputerName test-ftp.pvd.local -Port 21

# Test SFTP
Test-NetConnection -ComputerName test-sftp.pvd.local -Port 22

# Test LDAPS
Test-NetConnection -ComputerName test-ldap.pvd.local -Port 636
```

### Windows Firewall Blocking Connections

If you have corporate security software:

1. Open Windows Defender Firewall
2. Add inbound rules for ports 21, 22, 636, 389, 21100-21110
3. Or whitelist `podman.exe`

### Podman Machine Issues

If Podman machine won't start:
```powershell
# Reset the Podman machine
podman machine stop
podman machine rm podman-machine-default
podman machine init
podman machine start
```

### Image Build Fails

**Check available disk space:**
```powershell
Get-PSDrive C | Select-Object Used,Free
```

**Clean old images:**
```powershell
podman image prune -a
```

**Rebuild from scratch:**
```powershell
podman rmi integration-test-services:latest
.\scripts\build-test-container.ps1
```

### Tests Timeout Waiting for Services

Increase wait time in `TestServicesFixture.cs`:
```csharp
private async Task WaitForServicesReady()
{
    var maxWaitSeconds = 60; // Increased from 30
    // ... rest of method
}
```

---

## Advanced Configuration

### Using Different Ports

If default ports conflict with other services, modify the run command:

**scripts/run-test-services.ps1:**
```powershell
podman run -d `
  --name integration-test-services `
  -p 2121:21 `      # FTP on 2121 instead of 21
  -p 2222:22 `      # SFTP on 2222 instead of 22
  -p 6636:636 `     # LDAPS on 6636 instead of 636
  # ... rest
```

Update fixture accordingly:
```csharp
public int FtpPort => 2121;
public int SftpPort => 2222;
public int LdapPort => 6636;
```

### Multiple Test Environments

Create different compose files for different scenarios:

**docker-compose.local.yml** - Local development
**docker-compose.ci.yml** - CI/CD
**docker-compose.staging.yml** - Staging environment tests

### Custom Test Data

Mount custom LDAP schemas or FTP directories:
```powershell
podman run -d `
  --name integration-test-services `
  -v "${PWD}/test-data/ldap:/ldap-data" `
  -v "${PWD}/test-data/ftp:/home/testuser/ftp" `
  # ... rest
```

### Running Tests in Parallel

xUnit runs tests in parallel by default. To control this:

**In test class:**
```csharp
[Collection("Sequential Tests")]  // Runs sequentially
public class MyTests
{
    // ...
}
```

**In project file:**
```xml
<ItemGroup>
  <AssemblyAttribute Include="Xunit.CollectionBehavior">
    <_Parameter1>CollectionBehavior.CollectionPerAssembly</_Parameter1>
  </AssemblyAttribute>
</ItemGroup>
```

### Adding More Services

To add additional services (e.g., MQTT, Redis):

1. Update `Dockerfile.test` to install the service
2. Add configuration to `config/supervisord.conf`
3. Expose the port in run scripts
4. Add connection properties to `TestServicesFixture`
5. Write integration tests

---

## Quick Reference

### Common Commands
```powershell
# Build container
.\scripts\build-test-container.ps1

# Start services
.\scripts\run-test-services.ps1

# Stop services
.\scripts\stop-test-services.ps1

# Run all tests
.\scripts\test.ps1

# Rebuild and test
.\scripts\test.ps1 -Rebuild

# Run specific tests
.\scripts\test.ps1 -Filter "FtpIntegrationTests"

# Clean everything
.\scripts\test.ps1 -Clean

# View logs
podman logs -f integration-test-services

# Check status
podman ps -a --filter name=integration-test-services

# Connect to container (debugging)
podman exec -it integration-test-services bash
```

### Service Endpoints

| Service | Hostname | Port | Credentials |
|---------|----------|------|-------------|
| FTP | test-ftp.pvd.local | 21 | testuser / testpass123 |
| SFTP | test-sftp.pvd.local | 22 | testuser / testpass123 |
| LDAPS | test-ldap.pvd.local | 636 | cn=admin,dc=test,dc=local / admin |

### Test Patterns
```csharp
// Arrange - Set up test data
var testFile = $"test_{Guid.NewGuid()}.txt";

// Act - Perform operation
var result = await client.UploadAsync(stream, testFile);

// Assert - Verify result
Assert.Equal(FtpStatus.Success, result);

// Cleanup - Remove test data
await client.DeleteFileAsync(testFile);
```

---

## Migration Path

### Current State (Framework 4.8)
- Tests run on .NET Framework 4.8
- xUnit 2.x compatible with Framework 4.8
- All libraries support .NET Standard 2.0+

### Migration to .NET 8+ (Future)
1. Update `IntegrationTests.csproj`:
```xml
   <TargetFramework>net8.0</TargetFramework>
```
2. Update package references if needed
3. Run tests - should work without code changes!
4. Consider upgrading to xUnit 3.x for better performance

---

## Best Practices

### Test Independence
- Each test should be self-contained
- Use unique file/object names (e.g., `Guid.NewGuid()`)
- Clean up all test data in the test itself
- Don't rely on test execution order

### Test Performance
- Container stays running between test runs (fast iteration)
- Tests run in parallel by default
- Use `[Collection]` attribute to control parallelization
- Consider using `[Theory]` for parameterized tests

### Debugging Tests
- Set breakpoints as normal in Visual Studio/Rider
- Container logs available: `podman logs -f integration-test-services`
- Exec into container: `podman exec -it integration-test-services bash`
- Manual service testing with CLI tools (lftp, sftp, ldapsearch)

### Version Control
- Commit all Dockerfile and config files
- Commit PowerShell scripts
- **Don't commit** the hosts file (each dev configures their own)
- **Don't commit** local test data or credentials

---

## Team Onboarding

### New Developer Setup (15 minutes)

1. **Clone repository:**
```powershell
   git clone your-repo-url
   cd your-repo
```

2. **Install Podman Desktop** (if needed):
   - Download from https://podman-desktop.io/
   - Install and start Podman Desktop
   - Verify: `podman --version`

3. **Configure hosts file:**
```powershell
   # Run PowerShell as Administrator
   .\scripts\setup-hosts.ps1
```

4. **Run tests:**
```powershell
   .\scripts\test.ps1
```

That's it! First run takes 2-3 minutes (building container), then you're ready to develop.

---

## Support

### Documentation
- This document: `README-IntegrationTests.md`
- Container config: `docker/Dockerfile.test` and `docker/config/`
- Test examples: `tests/IntegrationTests/`

### Getting Help
1. Check the [Troubleshooting](#troubleshooting) section
2. View container logs: `podman logs integration-test-services`
3. Ask in team chat/Slack
4. Create an issue in the repository

### Useful Links
- [xUnit Documentation](https://xunit.net/)
- [FluentFTP Documentation](https://github.com/robinrodricks/FluentFTP)
- [SSH.NET Documentation](https://github.com/sshnet/SSH.NET)
- [Podman Documentation](https://docs.podman.io/)
- [OpenLDAP Documentation](https://www.openldap.org/doc/)

---

## Changelog

### Version 1.0 (January 2026)
- Initial setup with FTP, SFTP, LDAPS services
- xUnit test framework
- PowerShell automation scripts
- GitHub Actions CI/CD integration
- Comprehensive documentation

---

## Contributing

When adding new integration tests:

1. Follow the existing test patterns (Arrange, Act, Assert, Cleanup)
2. Use the `TestServicesFixture` for service connection details
3. Ensure tests are independent and can run in parallel
4. Add cleanup code to remove test data
5. Update this documentation if adding new services or features

