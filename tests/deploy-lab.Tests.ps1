#Requires -Module Pester
<#
.SYNOPSIS
    Pester v5 tests validating that scripts/deploy-lab.ps1 behaves correctly under -WhatIf with mocked Az context.

.DESCRIPTION
    Mocks Get-AzContext and every Az* resource cmdlet used by the AzHomeLab
    module so that deploy-lab.ps1 can be exercised end-to-end with -WhatIf
    and never makes a real Azure call. Verifies the script throws its
    documented instructive error when no Az context is present, and that it
    completes without throwing when a context exists and -WhatIf is used.
#>

BeforeAll {
    $script:DeployScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/deploy-lab.ps1'
    $script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1'
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'deploy-lab.ps1 context guard' {

    Context 'When no Az context is present' {
        BeforeAll {
            Mock -CommandName Get-AzContext -MockWith { $null } -ModuleName 'AzHomeLab'
        }

        It 'throws an instructive error telling the caller to run Connect-AzAccount' {
            Mock -CommandName Get-AzContext -MockWith { $null }
            { & $script:DeployScriptPath -ConfigPath $script:ConfigPath -Phase Foundation -WhatIf } | Should -Throw '*Connect-AzAccount*'
        }
    }
}

Describe 'deploy-lab.ps1 -WhatIf execution' {

    BeforeAll {
        Mock -CommandName Get-AzContext -MockWith {
            [PSCustomObject]@{
                Subscription = [PSCustomObject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'Mock Subscription' }
            }
        }
        Mock -CommandName Get-AzResourceProvider -MockWith {
            [PSCustomObject]@{ ProviderNamespace = 'Microsoft.Network'; RegistrationState = 'Registered' }
        }
        Mock -CommandName Register-AzResourceProvider -MockWith { }
        Mock -CommandName Get-AzResourceGroup -MockWith { $null }
        Mock -CommandName New-AzResourceGroup -MockWith {
            [PSCustomObject]@{ ResourceGroupName = 'rg-homelab-mgmt-eastus'; Location = 'eastus' }
        }
        Mock -CommandName Set-AzResourceGroup -MockWith { }
    }

    It 'runs the Foundation phase under -WhatIf without throwing' {
        { & $script:DeployScriptPath -ConfigPath $script:ConfigPath -Phase Foundation -WhatIf } | Should -Not -Throw
    }

    It 'defaults -SkipCompute to true from config so Compute is skipped on a plain run' {
        $config = Get-LabConfig -Path $script:ConfigPath
        $config.Compute.SkipComputeByDefault | Should -BeTrue
    }
}
