BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\environment\deploy.ps1'
}

Describe 'Deploy.ps1 Parameter Validation' {

    It 'Has CmdletBinding attribute' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $paramBlock = $ast.ParamBlock
        $paramBlock | Should -Not -BeNullOrEmpty
        $cmdletBinding = $paramBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        $cmdletBinding | Should -Not -BeNullOrEmpty
    }

    It 'Requires ResourceGroupName as mandatory' {
        $cmd = Get-Command $script:ScriptPath
        $param = $cmd.Parameters['ResourceGroupName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Mandatory | Should -Contain $true
    }

    It 'Requires Location as mandatory' {
        $cmd = Get-Command $script:ScriptPath
        $param = $cmd.Parameters['Location']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Mandatory | Should -Contain $true
    }

    It 'Requires StorageAccountName as mandatory with length validation' {
        $cmd = Get-Command $script:ScriptPath
        $param = $cmd.Parameters['StorageAccountName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Mandatory | Should -Contain $true
        $lengthAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateLengthAttribute] }
        $lengthAttr | Should -Not -BeNullOrEmpty
    }

    It 'Requires FunctionName as mandatory with length validation' {
        $cmd = Get-Command $script:ScriptPath
        $param = $cmd.Parameters['FunctionName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Mandatory | Should -Contain $true
        $lengthAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateLengthAttribute] }
        $lengthAttr | Should -Not -BeNullOrEmpty
    }

    It 'Has Environment parameter with ValidateSet' {
        $cmd = Get-Command $script:ScriptPath
        $param = $cmd.Parameters['Environment']
        $param | Should -Not -BeNullOrEmpty
        $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'dev'
        $validateSet.ValidValues | Should -Contain 'test'
        $validateSet.ValidValues | Should -Contain 'prod'
    }
}
