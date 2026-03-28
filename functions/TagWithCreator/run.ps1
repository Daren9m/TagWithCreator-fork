<#
.SYNOPSIS
    Tags Azure resources with the identity of their creator.

.DESCRIPTION
    Event Grid triggered function that receives ResourceWriteSuccess events,
    resolves the caller identity (UPN or Service Principal), and applies a
    Creator tag to the resource. Skips resource types in the configurable
    ignore list.

.PARAMETER eventGridEvent
    The Event Grid event object containing resource and caller data.

.PARAMETER TriggerMetadata
    Azure Functions trigger metadata (unused but required by runtime).
#>
[CmdletBinding()]
param($eventGridEvent, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

# --- Validate input ---
if ($null -eq $eventGridEvent -or $null -eq $eventGridEvent.data) {
    Write-Warning "Received null or malformed Event Grid event — exiting"
    exit
}

# --- Resolve caller identity ---
$caller = $eventGridEvent.data.claims."http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"
if ($null -eq $caller) {
    if ($eventGridEvent.data.authorization.evidence.principalType -eq "ServicePrincipal") {
        $principalId = $eventGridEvent.data.authorization.evidence.principalId
        try {
            $caller = (Get-AzADServicePrincipal -ObjectId $principalId).DisplayName
        }
        catch {
            Write-Warning "Failed to resolve Service Principal display name: $_"
        }
        if ($null -eq $caller) {
            Write-Warning "Could not resolve display name for principal $principalId — using raw ID"
            $caller = $principalId
        }
    }
}

Write-Information "Caller: $caller"
$resourceId = $eventGridEvent.data.resourceUri
Write-Information "ResourceId: $resourceId"

if (($null -eq $caller) -or [string]::IsNullOrEmpty($resourceId)) {
    Write-Warning "ResourceId or Caller is null — exiting"
    exit
}

# --- Check ignore list ---
$ignorePatterns = $env:TAG_IGNORE_PATTERNS
if ($ignorePatterns) {
    $ignore = $ignorePatterns -split ','
}
else {
    $ignore = @(
        "providers/Microsoft.Resources/deployments",
        "providers/Microsoft.Resources/tags",
        "providers/Microsoft.Network/frontdoor"
    )
}

foreach ($case in $ignore) {
    if ($resourceId -match $case) {
        Write-Information "Skipping event — resourceId matches ignore pattern: $case"
        exit
    }
}

# --- Apply Creator tag ---
$newTag = @{ Creator = $caller }

try {
    $tags = Get-AzTag -ResourceId $resourceId
}
catch {
    Write-Warning "Failed to read tags for ${resourceId}: $_"
    exit
}

if ($tags) {
    if ($tags.properties) {
        if ($tags.properties.TagsProperty) {
            if (-not $tags.properties.TagsProperty.ContainsKey('Creator')) {
                try {
                    Update-AzTag -ResourceId $resourceId -Operation Merge -Tag $newTag | Out-Null
                    Write-Information "Added Creator tag with user: $caller"
                }
                catch {
                    Write-Warning "Failed to update tags on ${resourceId}: $_"
                }
            }
            else {
                Write-Information "Creator tag already exists on $resourceId"
            }
        }
        else {
            try {
                New-AzTag -ResourceId $resourceId -Tag $newTag | Out-Null
                Write-Information "Added Creator tag with user: $caller"
            }
            catch {
                Write-Warning "Failed to create tags on ${resourceId}: $_"
            }
        }
    }
    else {
        Write-Warning "Resource $resourceId may not support tags (`$tags.properties is null)"
    }
}
else {
    Write-Warning "$resourceId does not support tags"
}
