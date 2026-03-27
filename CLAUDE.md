# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Azure Function (PowerShell 7.4, Functions v4 runtime) triggered by Event Grid that automatically tags Azure resources with a "Creator" tag identifying who created them. Forked from [anwather/TagWithCreator](https://github.com/anwather/TagWithCreator) for private corporate use.

**Architecture**: Azure Resource Created → Event Grid → Azure Function → Reads caller identity from event claims → Applies `Creator` tag via Az.Resources module.

**Identity resolution order**: UPN claim → Service Principal DisplayName (via `Get-AzADServicePrincipal`) → raw `principalId` fallback.

## Repository Layout

```
functions/                    # Azure Functions app root (deployed as ZIP)
  TagWithCreator/
    run.ps1                   # Main function logic (Event Grid trigger)
    function.json             # Binding metadata (eventGridTrigger)
  host.json                   # Runtime config (extension bundle 4.x, managed deps)
  requirements.psd1           # PowerShell module deps (Az.Accounts, Az.Resources)
  profile.ps1                 # Managed identity bootstrap (Connect-AzAccount -Identity)
  local.settings.json         # Local dev settings
environment/
  azuredeploy.json            # ARM template (Storage, App Service Plan, App Insights, Function App)
  deploy.ps1                  # Deployment script (ARM deploy + RBAC + ZIP publish)
```

## Development

### Prerequisites
- Azure Functions Core Tools v4 (`func`)
- PowerShell 7.x (`pwsh`)
- Az PowerShell modules: `Az.Accounts`, `Az.Resources`

### Local Run
```bash
cd functions
func start
```

### Test Event Grid Trigger Locally
Use `func` CLI or POST to the local endpoint with a sample Event Grid event payload. See [Azure docs on testing Event Grid triggers locally](https://learn.microsoft.com/en-us/azure/azure-functions/event-grid-how-tos?tabs=v2%2Cportal#local-testing-with-viewer-web-app).

### Lint
```powershell
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path ./functions -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

### Test
```powershell
Install-Module Pester -Force -Scope CurrentUser
Invoke-Pester -Path ./tests -Output Detailed
```

### Deploy
```powershell
cd environment
./deploy.ps1 -ResourceGroupName <rg> -Location <region> -StorageAccountName <sa> -AppServicePlanName <plan> -AppInsightsName <ai> -FunctionName <func>
```

## Conventions

### Commits
Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `ci:`. Branch prefixes: `feat/`, `fix/`, `chore/`.

### PowerShell
- `[CmdletBinding()]` and comment-based help on scripts
- `Write-Information`/`Write-Warning`/`Write-Error` — never `Write-Host`
- `$ErrorActionPreference = 'Stop'` with try-catch around Azure API calls
- No aliases, no backtick line continuations, no `$global:` scope
- Pester v5 for tests, PSScriptAnalyzer for linting

### ARM Templates
- Use latest stable API versions (check [Azure REST API reference](https://learn.microsoft.com/en-us/rest/api/))
- All parameters must have `metadata.description`
- All resources must have tags
- Use `APPLICATIONINSIGHTS_CONNECTION_STRING` (not `APPINSIGHTS_INSTRUMENTATIONKEY`)
- Workspace-based Application Insights (linked to Log Analytics)

## Key Design Decisions

- **Ignore list**: Resource types that should not be tagged are configured via `TAG_IGNORE_PATTERNS` environment variable (comma-separated provider paths). Defaults: `providers/Microsoft.Resources/deployments`, `providers/Microsoft.Resources/tags`, `providers/Microsoft.Network/frontdoor`.
- **RBAC**: Function's managed identity needs `Reader` (to resolve Service Principal names) and `Tag Contributor` (to write tags). Scoped to the resource group or subscription being monitored.
- **Concurrency**: `PSWorkerInProcConcurrencyUpperBound = 5` in app settings controls parallel PowerShell runspaces.
