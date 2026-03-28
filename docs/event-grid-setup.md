# Event Grid Subscription Setup

The TagWithCreator function is triggered by Azure Event Grid when resources are created. This document explains how to create the required Event Grid subscription.

## Prerequisites

- Azure subscription with Owner or Contributor role
- The TagWithCreator Function App deployed (via `deploy.ps1` or GitHub Actions)
- Azure CLI or Azure PowerShell installed

## Architecture

```
Azure Subscription Activity Log
  → Event Grid System Topic (subscription-scoped)
    → Event Subscription (filtered to ResourceWriteSuccess)
      → Azure Function (TagWithCreator)
```

## Setup Steps

### 1. Create the Event Grid System Topic

The system topic connects to the Azure subscription's activity log.

```powershell
# Using Azure CLI
az eventgrid system-topic create `
    --name "evgt-resource-activity" `
    --resource-group "<FUNCTION_RESOURCE_GROUP>" `
    --location global `
    --topic-type "Microsoft.Resources.Subscriptions" `
    --source "/subscriptions/<SUBSCRIPTION_ID>"
```

### 2. Get the Function App Endpoint

```powershell
# Get the function URL with access key
$funcApp = Get-AzFunctionApp -ResourceGroupName "<RG>" -Name "<FUNCTION_NAME>"
$keys = Invoke-AzResourceAction -ResourceId "$($funcApp.Id)/functions/TagWithCreator" `
    -Action listKeys -Force
$endpoint = "https://<FUNCTION_NAME>.azurewebsites.net/runtime/webhooks/EventGrid?functionName=TagWithCreator&code=$($keys.systemKeys.'eventgrid_extension')"
```

### 3. Create the Event Subscription

```powershell
az eventgrid system-topic event-subscription create `
    --name "evgs-tag-with-creator" `
    --system-topic-name "evgt-resource-activity" `
    --resource-group "<FUNCTION_RESOURCE_GROUP>" `
    --endpoint "$endpoint" `
    --endpoint-type "webhook" `
    --included-event-types "Microsoft.Resources.ResourceWriteSuccess" `
    --advanced-filter data.operationName StringContains "Microsoft.Resources/tags/write" `
    --advanced-filter data.operationName StringNotContains "Microsoft.Resources/deployments"
```

### Event Types

| Event Type | Description |
|------------|-------------|
| `Microsoft.Resources.ResourceWriteSuccess` | Fired when a resource is created or updated successfully |

The function's internal ignore list (`TAG_IGNORE_PATTERNS`) provides additional filtering for resource types that should not be tagged (deployments, tags, front doors).

## Permissions Required

| Role | Scope | Purpose |
|------|-------|---------|
| Owner or Contributor | Subscription | Create system topic and event subscription |
| Microsoft.EventGrid/systemTopics/write | Subscription | Create the system topic |
| Microsoft.EventGrid/systemTopics/eventSubscriptions/write | Resource Group | Create the event subscription |

## Verification

After setup, create a test resource (e.g., a storage account) and check:

1. The Event Grid system topic shows event deliveries in the Azure Portal
2. The Function App shows invocations in Application Insights
3. The test resource has a `Creator` tag with the deployer's identity

## Notes

- The system topic is **subscription-scoped**, which is why it cannot be included in the resource-group-scoped ARM template (`azuredeploy.json`). Automating this requires a subscription-level deployment template (planned for a future sprint).
- Event Grid has a built-in retry policy (24 hours, exponential backoff). If the function is temporarily unavailable, events will be retried.
- High-volume subscriptions may generate significant event traffic. Consider adding more `--advanced-filter` conditions to reduce unnecessary function invocations.
