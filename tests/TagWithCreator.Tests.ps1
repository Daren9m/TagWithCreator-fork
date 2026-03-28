BeforeAll {
    # Path to the function script under test
    $script:ScriptPath = Join-Path $PSScriptRoot '..\functions\TagWithCreator\run.ps1'

    # Helper to invoke the script with mocked parameters
    function Invoke-TagWithCreator {
        param($EventGridEvent)
        & $script:ScriptPath -eventGridEvent $EventGridEvent -TriggerMetadata @{}
    }

    # Build a standard test event
    function New-TestEvent {
        param(
            [string]$Caller = 'user@contoso.com',
            [string]$ResourceUri = '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1',
            [string]$PrincipalType = $null,
            [string]$PrincipalId = $null
        )
        $claims = @{}
        if ($Caller) {
            $claims['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'] = $Caller
        }
        $evidence = @{}
        if ($PrincipalType) { $evidence['principalType'] = $PrincipalType }
        if ($PrincipalId) { $evidence['principalId'] = $PrincipalId }

        return [PSCustomObject]@{
            data = [PSCustomObject]@{
                claims        = [PSCustomObject]$claims
                resourceUri   = $ResourceUri
                authorization = [PSCustomObject]@{
                    evidence = [PSCustomObject]$evidence
                }
            }
        }
    }
}

Describe 'TagWithCreator Function' {

    BeforeEach {
        # Mock all Azure cmdlets by default
        Mock Get-AzTag { $null }
        Mock Update-AzTag { }
        Mock New-AzTag { }
        Mock Get-AzADServicePrincipal { $null }

        # Clear TAG_IGNORE_PATTERNS so default list applies
        $env:TAG_IGNORE_PATTERNS = $null
    }

    Context 'Caller identity resolution' {

        It 'Extracts caller from UPN claim' {
            $event = New-TestEvent -Caller 'alice@contoso.com'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzADServicePrincipal -Times 0 -Exactly
        }

        It 'Falls back to Service Principal DisplayName when UPN is null' {
            $event = New-TestEvent -Caller $null -PrincipalType 'ServicePrincipal' -PrincipalId 'sp-id-123'
            $event.data.claims = [PSCustomObject]@{}

            Mock Get-AzADServicePrincipal {
                [PSCustomObject]@{ DisplayName = 'MyServicePrincipal' }
            }

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzADServicePrincipal -Times 1 -Exactly -ParameterFilter {
                $ObjectId -eq 'sp-id-123'
            }
        }

        It 'Falls back to raw principalId when Get-AzADServicePrincipal returns null' {
            $event = New-TestEvent -Caller $null -PrincipalType 'ServicePrincipal' -PrincipalId 'sp-id-456'
            $event.data.claims = [PSCustomObject]@{}

            Mock Get-AzADServicePrincipal { $null }

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzADServicePrincipal -Times 1 -Exactly
        }
    }

    Context 'Input validation' {

        It 'Exits early when event is null' {
            { Invoke-TagWithCreator -EventGridEvent $null } | Should -Not -Throw
            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Exits early when caller is null and not a service principal' {
            $event = New-TestEvent -Caller $null
            $event.data.claims = [PSCustomObject]@{}

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Exits early when resourceUri is null' {
            $event = New-TestEvent -ResourceUri $null

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }
    }

    Context 'Ignore list' {

        It 'Skips Microsoft.Resources/deployments' {
            $event = New-TestEvent -ResourceUri '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Resources/deployments/deploy1'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Skips Microsoft.Resources/tags' {
            $event = New-TestEvent -ResourceUri '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Resources/tags/default'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Skips Microsoft.Network/frontdoor' {
            $event = New-TestEvent -ResourceUri '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/frontdoor/fd1'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Reads TAG_IGNORE_PATTERNS from environment variable' {
            $env:TAG_IGNORE_PATTERNS = 'providers/Microsoft.Compute/virtualMachines'
            $event = New-TestEvent -ResourceUri '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 0 -Exactly
        }

        It 'Does not skip resource types not in ignore list' {
            $event = New-TestEvent -ResourceUri '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1'

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Get-AzTag -Times 1 -Exactly
        }
    }

    Context 'Tag operations' {

        It 'Merges Creator tag when resource has tags but no Creator' {
            $event = New-TestEvent -Caller 'bob@contoso.com'

            Mock Get-AzTag {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        TagsProperty = @{ Environment = 'dev' }
                    }
                }
            }

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Update-AzTag -Times 1 -Exactly -ParameterFilter {
                $Operation -eq 'Merge' -and $Tag.Creator -eq 'bob@contoso.com'
            }
        }

        It 'Does not overwrite existing Creator tag' {
            $event = New-TestEvent -Caller 'carol@contoso.com'

            Mock Get-AzTag {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        TagsProperty = @{ Creator = 'original@contoso.com' }
                    }
                }
            }

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke Update-AzTag -Times 0 -Exactly
            Should -Invoke New-AzTag -Times 0 -Exactly
        }

        It 'Creates new tag when resource has properties but no TagsProperty' {
            $event = New-TestEvent -Caller 'dave@contoso.com'

            Mock Get-AzTag {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        TagsProperty = $null
                    }
                }
            }

            Invoke-TagWithCreator -EventGridEvent $event

            Should -Invoke New-AzTag -Times 1 -Exactly -ParameterFilter {
                $Tag.Creator -eq 'dave@contoso.com'
            }
        }

        It 'Handles Get-AzTag returning object with null properties' {
            $event = New-TestEvent

            Mock Get-AzTag {
                [PSCustomObject]@{ properties = $null }
            }

            { Invoke-TagWithCreator -EventGridEvent $event } | Should -Not -Throw
            Should -Invoke Update-AzTag -Times 0 -Exactly
            Should -Invoke New-AzTag -Times 0 -Exactly
        }

        It 'Handles resource that does not support tags (Get-AzTag returns null)' {
            $event = New-TestEvent

            Mock Get-AzTag { $null }

            { Invoke-TagWithCreator -EventGridEvent $event } | Should -Not -Throw
            Should -Invoke Update-AzTag -Times 0 -Exactly
            Should -Invoke New-AzTag -Times 0 -Exactly
        }
    }

    Context 'Error handling' {

        It 'Handles Get-AzTag failure gracefully' {
            $event = New-TestEvent

            Mock Get-AzTag { throw "Access denied" }

            { Invoke-TagWithCreator -EventGridEvent $event } | Should -Not -Throw
        }

        It 'Handles Update-AzTag failure gracefully' {
            $event = New-TestEvent

            Mock Get-AzTag {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        TagsProperty = @{ Environment = 'dev' }
                    }
                }
            }
            Mock Update-AzTag { throw "Tag update failed" }

            { Invoke-TagWithCreator -EventGridEvent $event } | Should -Not -Throw
        }

        It 'Handles New-AzTag failure gracefully' {
            $event = New-TestEvent

            Mock Get-AzTag {
                [PSCustomObject]@{
                    properties = [PSCustomObject]@{
                        TagsProperty = $null
                    }
                }
            }
            Mock New-AzTag { throw "Tag creation failed" }

            { Invoke-TagWithCreator -EventGridEvent $event } | Should -Not -Throw
        }
    }
}
