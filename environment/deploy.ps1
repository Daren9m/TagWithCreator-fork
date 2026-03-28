<#
.SYNOPSIS
    Deploys the TagWithCreator Azure Function and assigns required RBAC roles.

.DESCRIPTION
    Creates or updates the resource group, deploys the ARM template, assigns
    Reader and Tag Contributor roles to the Function App's managed identity
    (scoped to the resource group), and publishes the function code as a ZIP.

.PARAMETER ResourceGroupName
    Name of the Azure resource group to create or use.

.PARAMETER Location
    Azure region for the resource group (e.g., eastus, westus2).

.PARAMETER StorageAccountName
    Globally unique name for the storage account (3-24 lowercase alphanumeric).

.PARAMETER AppServicePlanName
    Name for the consumption App Service Plan.

.PARAMETER AppInsightsName
    Name for the Application Insights resource.

.PARAMETER FunctionName
    Name for the Azure Function App (2-60 characters).

.PARAMETER Environment
    Deployment environment: dev, test, or prod. Defaults to dev.

.EXAMPLE
    ./deploy.ps1 -ResourceGroupName "rg-tagcreator-dev" -Location "eastus" `
        -StorageAccountName "sttagcreatordev" -AppServicePlanName "plan-tagcreator-dev" `
        -AppInsightsName "ai-tagcreator-dev" -FunctionName "func-tagcreator-dev"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [ValidateLength(3, 24)]
    [string]$StorageAccountName,

    [Parameter(Mandatory)]
    [string]$AppServicePlanName,

    [Parameter(Mandatory)]
    [string]$AppInsightsName,

    [Parameter(Mandatory)]
    [ValidateLength(2, 60)]
    [string]$FunctionName,

    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'

# --- Create resource group ---
Write-Information "Creating resource group '$ResourceGroupName' in '$Location'..."
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -Verbose

# --- Deploy ARM template ---
Write-Information "Deploying ARM template..."
$params = @{
    storageAccountName = $StorageAccountName.ToLower()
    appServicePlanName = $AppServicePlanName
    appInsightsName    = $AppInsightsName
    functionName       = $FunctionName
    environment        = $Environment
}

$output = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
    -TemplateFile "$PSScriptRoot\azuredeploy.json" `
    -TemplateParameterObject $params -Verbose

$principalId = $output.Outputs.managedIdentityId.Value
$rgScope = (Get-AzResourceGroup -Name $ResourceGroupName).ResourceId

# --- Assign RBAC roles (scoped to resource group, idempotent) ---
$roles = @('Reader', 'Tag Contributor')
foreach ($role in $roles) {
    $existing = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $role -Scope $rgScope -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Information "Assigning '$role' role to managed identity..."
        New-AzRoleAssignment -RoleDefinitionName $role -ObjectId $principalId -Scope $rgScope -Verbose
    }
    else {
        Write-Information "'$role' role already assigned — skipping"
    }
}

# --- Package and publish function code ---
Write-Information "Packaging function code..."
$zipPath = Join-Path $PSScriptRoot 'functions.zip'
$functionsPath = Join-Path $PSScriptRoot '..\functions'

Compress-Archive -Path (Join-Path $functionsPath '*') -DestinationPath $zipPath -Force -Verbose

try {
    Write-Information "Publishing to '$FunctionName'..."
    Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionName -ArchivePath $zipPath -Verbose -Force
}
finally {
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
}

Write-Information "Deployment complete."
