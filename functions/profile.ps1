# Azure Functions profile - runs on cold start
# Authenticates using the Function App's system-assigned managed identity

$isManagedIdentity = $env:IDENTITY_ENDPOINT -or $env:MSI_SECRET
if ($isManagedIdentity -and (Get-Module -ListAvailable Az.Accounts)) {
    try {
        Connect-AzAccount -Identity
    }
    catch {
        Write-Error "Failed to authenticate with managed identity: $_"
    }
}
