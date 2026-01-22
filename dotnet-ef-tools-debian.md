# .NET EF Core Tools Setup for Debian

## Installation
```bash
# Install EF Core CLI tools globally
dotnet tool install --global dotnet-ef

# Verify installation
dotnet ef --version
```

## Updating EF Tools
```bash
# Update to latest version
dotnet tool update --global dotnet-ef
```

## PATH Configuration

If `dotnet ef` command is not found after installation, add .NET tools to your PATH:
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:$HOME/.dotnet/tools"

# Reload shell configuration
source ~/.bashrc
# or
source ~/.zshrc
```

## Common Commands
```bash
# Create a migration
dotnet ef migrations add MigrationName

# Update database
dotnet ef database update

# Remove last migration
dotnet ef migrations remove

# List migrations
dotnet ef migrations list

# Generate SQL script
dotnet ef migrations script
```

## Project Requirements

Your project needs the following package for EF tools to work:
```bash
dotnet add package Microsoft.EntityFrameworkCore.Design
```

## Troubleshooting

### Command not found
- Ensure tools are installed: `dotnet tool list --global`
- Check PATH includes `~/.dotnet/tools`
- Restart terminal after adding to PATH

### Tools version mismatch
- EF tools version should match your EF Core package version
- Example: EF Core 9.0.x → dotnet-ef 9.0.x
- Update tools: `dotnet tool update --global dotnet-ef`

## Notes

- EF tools are installed per-user, not system-wide
- Tools are stored in `~/.dotnet/tools`
- Always run `dotnet ef` commands from your project directory
