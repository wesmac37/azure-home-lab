#Requires -Module Pester
<#
.SYNOPSIS
    Pester v5 tests for the AzHomeLab PowerShell module's naming, tagging, and configuration helpers.

.DESCRIPTION
    Mocks all Az* cmdlets so the suite makes no real Azure calls and can run
    unattended in CI (see .github/workflows/powershell-ci.yml). Focuses on
    the pure-logic public functions: Get-LabResourceName, New-LabTag,
    Get-LabConfig, and Register-LabResourceProvider's idempotent skip path.
#>

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
    Import-Module -Name $modulePath -Force

    $script:TestConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1'
}

Describe 'AzHomeLab module manifest' {

    It 'imports without error and exports the expected functions' {
        Get-Module -Name 'AzHomeLab' | Should -Not -BeNullOrEmpty
        (Get-Command -Module 'AzHomeLab' -Name 'New-LabResourceGroup' -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-LabResourceName' {

    Context 'Standard naming style' {
        It 'produces the documented <resType>-<workload>-<env>-<region> pattern' {
            $name = Get-LabResourceName -ResourceType 'rg' -Workload 'homelab' -Environment 'dev' -Region 'eastus'
            $name | Should -Be 'rg-homelab-dev-eastus'
        }

        It 'lowercases all segments regardless of input casing' {
            $name = Get-LabResourceName -ResourceType 'RG' -Workload 'HomeLab' -Environment 'DEV' -Region 'EastUS'
            $name | Should -Be 'rg-homelab-dev-eastus'
        }
    }

    Context 'Compressed naming style (storage accounts)' {
        It 'produces a dash-free lowercase name at or under 24 characters' {
            $name = Get-LabResourceName -Style Compressed -ResourceType 'st' -Workload 'homelab' -Environment 'dev' -UniqueSuffix 'lab01'
            $name | Should -Be 'sthomelabdevlab01'
            $name.Length | Should -BeLessOrEqual 24
            $name | Should -Not -Match '-'
        }

        It 'throws when -UniqueSuffix is not supplied for Compressed style' {
            { Get-LabResourceName -Style Compressed -ResourceType 'st' -Workload 'homelab' -Environment 'dev' } | Should -Throw
        }
    }

    Context 'Key Vault naming style' {
        It 'produces the kv-<workload>-<env>-<suffix> pattern' {
            $name = Get-LabResourceName -Style KeyVault -ResourceType 'kv' -Workload 'homelab' -Environment 'dev' -UniqueSuffix 'lab01'
            $name | Should -Be 'kv-homelab-dev-lab01'
        }
    }
}

Describe 'New-LabTag' {

    BeforeAll {
        $script:BaseTags = @{
            Environment  = 'Lab'
            Project      = 'AzureHomeLab'
            Owner        = 'test-owner@example.com'
            CostCenter   = 'Personal'
            AutoShutdown = 'false'
            CreatedBy    = 'IaC'
            DeployPhase  = 'Foundation'
        }
    }

    It 'returns a hashtable containing all seven required tag keys' {
        $tags = New-LabTag -BaseTags $script:BaseTags
        foreach ($key in @('Environment', 'Project', 'Owner', 'CostCenter', 'AutoShutdown', 'CreatedBy', 'DeployPhase')) {
            $tags.ContainsKey($key) | Should -BeTrue
        }
    }

    It 'allows Override values to take precedence over BaseTags' {
        $tags = New-LabTag -BaseTags $script:BaseTags -Override @{ DeployPhase = 'Network'; AutoShutdown = 'true' }
        $tags.DeployPhase | Should -Be 'Network'
        $tags.AutoShutdown | Should -Be 'true'
        $tags.Project | Should -Be 'AzureHomeLab'
    }

    It 'throws if the merged tag set is missing a required key' {
        $incompleteTags = @{ Environment = 'Lab' }
        { New-LabTag -BaseTags $incompleteTags } | Should -Throw
    }
}

Describe 'Get-LabConfig' {

    It 'loads config/lab.config.psd1 and returns all required top-level keys' {
        $config = Get-LabConfig -Path $script:TestConfigPath
        foreach ($key in @('Workload', 'Environment', 'Region', 'ResourceGroups', 'Tags', 'Network', 'Storage', 'KeyVault', 'Monitoring', 'Compute', 'Governance', 'Budget')) {
            $config.ContainsKey($key) | Should -BeTrue
        }
    }

    It 'throws a clear error when the file path does not exist' {
        { Get-LabConfig -Path (Join-Path -Path $PSScriptRoot -ChildPath 'does-not-exist.psd1') } | Should -Throw
    }
}

Describe 'Register-LabResourceProvider' {

    BeforeAll {
        Mock -CommandName Get-AzResourceProvider -ModuleName 'AzHomeLab' -MockWith {
            [PSCustomObject]@{ ProviderNamespace = 'Microsoft.KeyVault'; RegistrationState = 'Registered' }
        }
        Mock -CommandName Register-AzResourceProvider -ModuleName 'AzHomeLab' -MockWith { }
    }

    It 'does not call Register-AzResourceProvider when the provider is already Registered' {
        Register-LabResourceProvider -ProviderNamespace 'Microsoft.KeyVault' -Confirm:$false
        Should -Invoke -CommandName Register-AzResourceProvider -ModuleName 'AzHomeLab' -Times 0
    }
}
