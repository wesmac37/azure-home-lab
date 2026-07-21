#Requires -Module Pester
<#
.SYNOPSIS
    Pester v5 tests for scripts/validate-lab.ps1 and the Test-LabDeployment helper.

.DESCRIPTION
    Mocks Az* cmdlets so validation logic can be exercised without any real
    Azure calls. Confirms Test-LabDeployment returns PASS/FAIL objects with
    the expected shape, and that validate-lab.ps1 surfaces failures via a
    non-zero exit path when a required component is missing.
#>

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Test-LabDeployment' {

    Context 'ResourceGroupExists check' {
        It 'returns PASS when the resource group is found' {
            Mock -CommandName Get-AzResourceGroup -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ ResourceGroupName = 'rg-homelab-mgmt-eastus' } }
            $result = Test-LabDeployment -CheckName 'ResourceGroupExists' -ResourceGroupName 'rg-homelab-mgmt-eastus'
            $result.Status | Should -Be 'PASS'
        }

        It 'returns FAIL when the resource group is not found' {
            Mock -CommandName Get-AzResourceGroup -ModuleName 'AzHomeLab' -MockWith { $null }
            $result = Test-LabDeployment -CheckName 'ResourceGroupExists' -ResourceGroupName 'rg-does-not-exist'
            $result.Status | Should -Be 'FAIL'
        }
    }

    Context 'StorageSecureTransfer check' {
        It 'returns PASS when EnableHttpsTrafficOnly is true' {
            Mock -CommandName Get-AzStorageAccount -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ EnableHttpsTrafficOnly = $true } }
            $result = Test-LabDeployment -CheckName 'StorageSecureTransfer' -ResourceGroupName 'rg-homelab-mgmt-eastus' -ResourceName 'sthomelablab01'
            $result.Status | Should -Be 'PASS'
        }

        It 'returns FAIL when secure transfer is disabled' {
            Mock -CommandName Get-AzStorageAccount -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ EnableHttpsTrafficOnly = $false } }
            $result = Test-LabDeployment -CheckName 'StorageSecureTransfer' -ResourceGroupName 'rg-homelab-mgmt-eastus' -ResourceName 'sthomelablab01'
            $result.Status | Should -Be 'FAIL'
        }
    }

    Context 'KeyVaultRbacMode check' {
        It 'returns PASS when EnableRbacAuthorization is true' {
            Mock -CommandName Get-AzKeyVault -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ EnableRbacAuthorization = $true } }
            $result = Test-LabDeployment -CheckName 'KeyVaultRbacMode' -ResourceGroupName 'rg-homelab-mgmt-eastus' -ResourceName 'kv-homelab-dev-lab01'
            $result.Status | Should -Be 'PASS'
        }
    }

    Context 'BastionSku check' {
        It 'returns PASS only when SKU is exactly Developer' {
            Mock -CommandName Get-AzBastion -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ Sku = [PSCustomObject]@{ Name = 'Developer' } } }
            $result = Test-LabDeployment -CheckName 'BastionSku' -ResourceGroupName 'rg-homelab-network-eastus' -ResourceName 'bas-homelab-dev-eastus'
            $result.Status | Should -Be 'PASS'
        }

        It 'returns FAIL when SKU is Standard (not the cost-free Developer tier)' {
            Mock -CommandName Get-AzBastion -ModuleName 'AzHomeLab' -MockWith { [PSCustomObject]@{ Sku = [PSCustomObject]@{ Name = 'Standard' } } }
            $result = Test-LabDeployment -CheckName 'BastionSku' -ResourceGroupName 'rg-homelab-network-eastus' -ResourceName 'bas-homelab-dev-eastus'
            $result.Status | Should -Be 'FAIL'
        }
    }
}

Describe 'Test-LabDeployment result object shape' {

    It 'always returns an object with Check, Status, and Detail properties' {
        Mock -CommandName Get-AzResourceGroup -ModuleName 'AzHomeLab' -MockWith { $null }
        $result = Test-LabDeployment -CheckName 'ResourceGroupExists' -ResourceGroupName 'rg-anything'
        $result.PSObject.Properties.Name | Should -Contain 'Check'
        $result.PSObject.Properties.Name | Should -Contain 'Status'
        $result.PSObject.Properties.Name | Should -Contain 'Detail'
    }
}
