@{
    Severity = @('Error', 'Warning')

    IncludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseCmdletCorrectly',
        'PSAvoidUsingPositionalParameters',
        'PSUseApprovedVerbs',
        'PSAvoidGlobalVars',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingInvokeExpression',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidDefaultValueForMandatoryParameter',
        'PSReservedCmdletChar',
        'PSReservedParams'
    )

    Rules = @{
        # $TriggerMetadata is required by Azure Functions runtime but not used in code
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
    }
}
