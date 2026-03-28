# TagWithCreator

Automatically tags Azure resources with the identity of their creator using an Event Grid-triggered Azure Function.

Forked from [anwather/TagWithCreator](https://github.com/anwather/TagWithCreator) for private corporate deployment. Original blog post: [Tagging Azure Resources with a Creator](https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/tagging-azure-resources-with-a-creator/ba-p/1479819).

## Architecture

```
Azure Resource Created
  → Azure Event Grid (ResourceWriteSuccess)
    → Azure Function (PowerShell 7.4, Functions v4)
      → Resolves caller identity (UPN or Service Principal)
        → Applies "Creator" tag to the resource
```

## Prerequisites

- Azure subscription with Owner or Contributor role
- [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) (`func`)
- [PowerShell 7.x](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) (`pwsh`)
- Az PowerShell modules: `Az.Accounts`, `Az.Resources`
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) or Azure PowerShell for deployment

## Quick Start

### Deploy

```powershell
cd environment
./deploy.ps1 -ResourceGroupName "rg-tagcreator-dev" `
    -Location "eastus" `
    -StorageAccountName "sttagcreatordev" `
    -AppServicePlanName "plan-tagcreator-dev" `
    -AppInsightsName "ai-tagcreator-dev" `
    -FunctionName "func-tagcreator-dev"
```

After deployment, set up the Event Grid subscription — see [docs/event-grid-setup.md](docs/event-grid-setup.md).

### Local Development

```bash
cd functions
func start
```

### Run Tests

```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

### Lint

```powershell
Invoke-ScriptAnalyzer -Path ./functions -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `TAG_IGNORE_PATTERNS` | Comma-separated resource provider patterns to skip | `providers/Microsoft.Resources/deployments,providers/Microsoft.Resources/tags,providers/Microsoft.Network/frontdoor` |
| `PSWorkerInProcConcurrencyUpperBound` | Max parallel PowerShell runspaces | `5` |

## RBAC Requirements

The Function App's managed identity requires these roles:

| Role | Purpose | Scope |
|------|---------|-------|
| Reader | Resolve Service Principal display names | Resource group or subscription |
| Tag Contributor | Create and update resource tags | Resource group or subscription |

## CI/CD

- **CI**: PSScriptAnalyzer, ARM template validation, and Pester tests run on every push and PR via [GitHub Actions](.github/workflows/ci.yml)
- **Deploy**: Manual deployment via [workflow dispatch](.github/workflows/deploy.yml) with environment selection (dev/test/prod)

## Disclaimer

The sample scripts are not supported under any Microsoft standard support program or service. The sample scripts are provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

## License

[MIT](LICENSE) — Original work Copyright 2020 Anthony Watherston.
