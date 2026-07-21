@{
    RootModule        = 'AzHomeLab.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b3f6a8e2-9c1d-4e2a-8f3b-6a1d2e4c5f70'
    Author            = 'Your Name'
    CompanyName       = 'Personal'
    Copyright         = '(c) 2026 Your Name. Licensed under MIT.'
    Description       = 'Idempotent, cost-aware Azure home lab automation functions built for the Azure Free Account: resource groups, networking, Bastion Developer SKU, storage, Key Vault, Log Analytics, compute, governance (policy/RBAC/locks), and budget alerting.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @(
        'Get-LabConfig',
        'Get-LabResourceName',
        'New-LabBastion',
        'New-LabBudgetAlert',
        'New-LabKeyVault',
        'New-LabLogAnalyticsWorkspace',
        'New-LabNetworkSecurityGroup',
        'New-LabPolicyAssignment',
        'New-LabResourceGroup',
        'New-LabResourceLock',
        'New-LabStorageAccount',
        'New-LabTag',
        'New-LabVirtualMachine',
        'New-LabVirtualNetwork',
        'Register-LabResourceProvider',
        'Remove-LabResourceLock',
        'Test-LabDeployment',
        'Write-LabLog'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'HomeLab', 'IaC', 'PowerShell', 'AzPowerShell', 'Portfolio')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/your-username/azure-home-lab'
            ReleaseNotes = 'Initial 1.0.0 release: full modular Azure Free Account home lab automation.'
        }
    }
}
