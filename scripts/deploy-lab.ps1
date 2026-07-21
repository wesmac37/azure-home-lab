<#
.SYNOPSIS
    Deploys the AzHomeLab environment in ordered, resumable phases.

.DESCRIPTION
    Orchestrates the full AzHomeLab deployment by importing the AzHomeLab
    module, verifying an active Az PowerShell context, idempotently
    registering required resource providers, and then executing each
    requested phase (Foundation, Network, Security, Storage, Monitoring,
    Compute) in dependency order. Each phase is wrapped in try/catch so a
    failure in one phase is reported clearly without leaving unrelated
    resources in an ambiguous state. A summary table of every resource
    touched (name, type, status) is printed at the end, and the full run is
    logged to ../logs/deploy-lab-<timestamp>.log.

    Designed to run cleanly in Azure Cloud Shell, where an Az context
    already exists. This script deliberately does NOT call Connect-AzAccount
    on the caller's behalf — if no context is found, it throws an
    instructive error telling the caller exactly what to run.

    Compute is SKIPPED by default (per config Deploy.SkipComputeDefault /
    Compute.SkipComputeByDefault) so a first run stays as cheap as possible;
    pass -SkipCompute:$false to opt in.

.PARAMETER ConfigPath
    Path to the lab configuration .psd1 file. Defaults to '../config/lab.config.psd1'
    relative to this script's directory.

.PARAMETER Phase
    Which deployment phase(s) to run. One of 'All','Foundation','Network','Security','Storage','Monitoring','Compute'.
    Defaults to 'All'.

.PARAMETER SkipCompute
    Switch controlling whether the optional test VM is deployed. Defaults to
    the value of Compute.SkipComputeByDefault in the config file (true),
    overridable on the command line.

.PARAMETER VmAdminPassword
    SecureString admin password for the optional test VM. Required only when
    the Compute phase actually runs (Phase is 'All' or 'Compute' and
    -SkipCompute is $false). Prompted securely if not supplied.

.EXAMPLE
    ./deploy-lab.ps1 -Phase Foundation

.EXAMPLE
    ./deploy-lab.ps1 -Phase All -SkipCompute:$false -Verbose

.EXAMPLE
    ./deploy-lab.ps1 -WhatIf
    Shows what would be deployed without making any changes.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Foundation', 'Network', 'Security', 'Storage', 'Monitoring', 'Compute')]
    [string]$Phase = 'All',

    [Parameter(Mandatory = $false)]
    [switch]$SkipCompute,

    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$VmAdminPassword
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Module import
# ---------------------------------------------------------------------------
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}
catch {
    throw "deploy-lab.ps1: failed to import the AzHomeLab module from '$modulePath'. Error: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Az context check — never silently call Connect-AzAccount
# ---------------------------------------------------------------------------
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context -or -not $context.Subscription) {
    throw "deploy-lab.ps1: no active Az PowerShell context was found. Run 'Connect-AzAccount' (or, in Azure Cloud Shell, an authenticated context should already exist — run 'Get-AzContext' to confirm) and then re-run this script."
}
Write-Host "Using subscription '$($context.Subscription.Name)' ($($context.Subscription.Id))." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
$Config = Get-LabConfig -Path $ConfigPath

if (-not $PSBoundParameters.ContainsKey('SkipCompute')) {
    $SkipCompute = [bool]$Config.Compute.SkipComputeByDefault
}

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
$logDirectory = Join-Path -Path $PSScriptRoot -ChildPath $Config.Deploy.LogDirectory
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path -Path $logDirectory -ChildPath "deploy-lab-$timestamp.log"

Write-LabLog -Message "=== AzHomeLab deployment started (Phase=$Phase, SkipCompute=$SkipCompute) ===" -LogPath $logPath

# ---------------------------------------------------------------------------
# Resource provider registration (idempotent)
# ---------------------------------------------------------------------------
$requiredProviders = @(
    'Microsoft.KeyVault', 'Microsoft.Network', 'Microsoft.Storage',
    'Microsoft.OperationalInsights', 'Microsoft.Compute', 'Microsoft.PolicyInsights'
)
Write-LabLog -Message "Registering resource providers: $($requiredProviders -join ', ')" -LogPath $logPath
Register-LabResourceProvider -ProviderNamespace $requiredProviders -WhatIf:$WhatIfPreference

# ---------------------------------------------------------------------------
# Results tracking
# ---------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[PSCustomObject]

function Add-DeployResult {
    param($ResourceType, $ResourceName, $Status)
    $results.Add([PSCustomObject]@{
        Resource = $ResourceType
        Name     = $ResourceName
        Status   = $Status
    })
}

$runAll        = ($Phase -eq 'All')
$vnetObject    = $null
$mgmtSubnetId  = $null
$appSubnetId   = $null

# ---------------------------------------------------------------------------
# Phase: Foundation (resource groups)
# ---------------------------------------------------------------------------
if ($runAll -or $Phase -eq 'Foundation') {
    Write-LabLog -Message '--- Phase: Foundation ---' -LogPath $logPath
    try {
        foreach ($rgKey in @('Mgmt', 'Network', 'Compute')) {
            $rgName = $Config.ResourceGroups[$rgKey]
            $tags = New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Foundation' }
            $rg = New-LabResourceGroup -Name $rgName -Location $Config.Region -Tags $tags -WhatIf:$WhatIfPreference
            Add-DeployResult -ResourceType 'ResourceGroup' -ResourceName $rgName -Status 'Succeeded'
            Write-LabLog -Message "Resource group ready: $rgName" -LogPath $logPath
        }
    }
    catch {
        Add-DeployResult -ResourceType 'ResourceGroup' -ResourceName 'Foundation phase' -Status "Failed: $($_.Exception.Message)"
        Write-LabLog -Message "Foundation phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# Phase: Network (VNet, subnets, NSGs, Bastion)
# ---------------------------------------------------------------------------
if ($runAll -or $Phase -eq 'Network') {
    Write-LabLog -Message '--- Phase: Network ---' -LogPath $logPath
    try {
        $tags = New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Network' }

        $vnetObject = New-LabVirtualNetwork -Name $Config.Network.VNetName -ResourceGroupName $Config.ResourceGroups.Network `
            -Location $Config.Region -AddressPrefix $Config.Network.VNetAddressSpace -SubnetDefinition $Config.Network.Subnets `
            -Tags $tags -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'VirtualNetwork' -ResourceName $Config.Network.VNetName -Status 'Succeeded'

        $mgmtNsg = New-LabNetworkSecurityGroup -Name $Config.Network.NsgMgmtName -ResourceGroupName $Config.ResourceGroups.Network `
            -Location $Config.Region -Tags $tags -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'NetworkSecurityGroup' -ResourceName $Config.Network.NsgMgmtName -Status 'Succeeded'

        $appNsg = New-LabNetworkSecurityGroup -Name $Config.Network.NsgAppName -ResourceGroupName $Config.ResourceGroups.Network `
            -Location $Config.Region -Tags $tags -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'NetworkSecurityGroup' -ResourceName $Config.Network.NsgAppName -Status 'Succeeded'

        try {
            $bastion = New-LabBastion -Name $Config.Network.BastionName -ResourceGroupName $Config.ResourceGroups.Network `
                -Location $Config.Region -VirtualNetworkName $Config.Network.VNetName -Tags $tags -WhatIf:$WhatIfPreference
            Add-DeployResult -ResourceType 'Bastion' -ResourceName $Config.Network.BastionName -Status 'Succeeded'
        }
        catch {
            Add-DeployResult -ResourceType 'Bastion' -ResourceName $Config.Network.BastionName -Status "Failed (see docs/architecture.md fallback): $($_.Exception.Message)"
            Write-LabLog -Message "Bastion deployment failed, zero-cost NSG fallback documented in docs/architecture.md: $($_.Exception.Message)" -Level Warning -LogPath $logPath
        }
    }
    catch {
        Add-DeployResult -ResourceType 'Network' -ResourceName 'Network phase' -Status "Failed: $($_.Exception.Message)"
        Write-LabLog -Message "Network phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# Phase: Security (governance — policy, RBAC example, resource lock, budget)
# ---------------------------------------------------------------------------
if ($runAll -or $Phase -eq 'Security') {
    Write-LabLog -Message '--- Phase: Security ---' -LogPath $logPath
    try {
        $policyAssignment = New-LabPolicyAssignment -Name $Config.Governance.PolicyAssignmentName `
            -PolicyDefinitionId $Config.Governance.RequireTagPolicyDefinitionId `
            -ScopeResourceGroupName $Config.ResourceGroups.Mgmt -RequiredTagName $Config.Governance.RequiredTagName `
            -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'PolicyAssignment' -ResourceName $Config.Governance.PolicyAssignmentName -Status 'Succeeded'

        $lock = New-LabResourceLock -Name $Config.Governance.ResourceLockName -ResourceGroupName $Config.ResourceGroups.Mgmt -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'ResourceLock' -ResourceName $Config.Governance.ResourceLockName -Status 'Succeeded'

        Write-LabLog -Message "RBAC example: to grant Reader at RG scope, run: New-AzRoleAssignment -ObjectId '$($Config.Governance.SecondUserObjectId)' -RoleDefinitionName 'Reader' -ResourceGroupName '$($Config.ResourceGroups.Mgmt)' (replace placeholder object ID first)." -LogPath $logPath

        try {
            $budget = New-LabBudgetAlert -Name $Config.Budget.Name -AmountUsd $Config.Budget.AmountUsd `
                -ThresholdPercents $Config.Budget.ThresholdPercents -ContactEmails $Config.Budget.ContactEmails `
                -StartDate $Config.Budget.StartDate -EndDate $Config.Budget.EndDate -WhatIf:$WhatIfPreference
            Add-DeployResult -ResourceType 'Budget' -ResourceName $Config.Budget.Name -Status 'Succeeded'
        }
        catch {
            Add-DeployResult -ResourceType 'Budget' -ResourceName $Config.Budget.Name -Status "Failed (optional): $($_.Exception.Message)"
            Write-LabLog -Message "Budget creation failed (optional component): $($_.Exception.Message)" -Level Warning -LogPath $logPath
        }
    }
    catch {
        Add-DeployResult -ResourceType 'Security' -ResourceName 'Security phase' -Status "Failed: $($_.Exception.Message)"
        Write-LabLog -Message "Security phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# Phase: Storage
# ---------------------------------------------------------------------------
if ($runAll -or $Phase -eq 'Storage') {
    Write-LabLog -Message '--- Phase: Storage ---' -LogPath $logPath
    try {
        $tags = New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Storage' }
        $storageAccountName = Get-LabResourceName -Style Compressed -ResourceType $Config.Storage.AccountNamePrefix `
            -Workload '' -Environment '' -UniqueSuffix $Config.UniqueSuffix

        $callerObjectId = $null
        try {
            $callerObjectId = (Get-AzADUser -SignedIn -ErrorAction SilentlyContinue).Id
        }
        catch {
            Write-LabLog -Message 'Could not resolve signed-in caller object ID for RBAC grant (non-fatal, likely a service principal context).' -Level Warning -LogPath $logPath
        }

        $storageAccount = New-LabStorageAccount -Name $storageAccountName -ResourceGroupName $Config.ResourceGroups.Mgmt `
            -Location $Config.Region -SkuName $Config.Storage.Sku -Containers $Config.Storage.Containers `
            -Tags $tags -GrantRbacToPrincipalId $callerObjectId -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'StorageAccount' -ResourceName $storageAccountName -Status 'Succeeded'

        $keyVaultName = Get-LabResourceName -Style KeyVault -ResourceType 'kv' -Workload $Config.Workload `
            -Environment $Config.Environment -UniqueSuffix $Config.UniqueSuffix

        $keyVault = New-LabKeyVault -Name $keyVaultName -ResourceGroupName $Config.ResourceGroups.Mgmt -Location $Config.Region `
            -Tags $tags -EnablePurgeProtection $Config.KeyVault.EnablePurgeProtection -SoftDeleteRetentionInDays $Config.KeyVault.SoftDeleteRetentionDays `
            -DemoSecretName $Config.KeyVault.DemoSecretName -DemoSecretValue $Config.KeyVault.DemoSecretValue -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'KeyVault' -ResourceName $keyVaultName -Status 'Succeeded'
    }
    catch {
        Add-DeployResult -ResourceType 'Storage' -ResourceName 'Storage phase' -Status "Failed: $($_.Exception.Message)"
        Write-LabLog -Message "Storage phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# Phase: Monitoring
# ---------------------------------------------------------------------------
if ($runAll -or $Phase -eq 'Monitoring') {
    Write-LabLog -Message '--- Phase: Monitoring ---' -LogPath $logPath
    try {
        $tags = New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Monitoring' }
        $workspace = New-LabLogAnalyticsWorkspace -Name $Config.Monitoring.WorkspaceName -ResourceGroupName $Config.ResourceGroups.Mgmt `
            -Location $Config.Region -SkuName $Config.Monitoring.Sku -DailyQuotaGb $Config.Monitoring.DailyQuotaGb `
            -RetentionInDays $Config.Monitoring.RetentionInDays -Tags $tags -WhatIf:$WhatIfPreference
        Add-DeployResult -ResourceType 'LogAnalyticsWorkspace' -ResourceName $Config.Monitoring.WorkspaceName -Status 'Succeeded'
    }
    catch {
        Add-DeployResult -ResourceType 'Monitoring' -ResourceName 'Monitoring phase' -Status "Failed: $($_.Exception.Message)"
        Write-LabLog -Message "Monitoring phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# Phase: Compute (optional, skipped by default)
# ---------------------------------------------------------------------------
if (($runAll -or $Phase -eq 'Compute')) {
    if ($SkipCompute) {
        Write-LabLog -Message '--- Phase: Compute SKIPPED (-SkipCompute is set; this is the cost-safe default) ---' -LogPath $logPath
        Add-DeployResult -ResourceType 'VirtualMachine' -ResourceName $Config.Compute.VmName -Status 'Skipped (SkipCompute)'
    }
    else {
        Write-LabLog -Message '--- Phase: Compute ---' -LogPath $logPath
        try {
            if (-not $VmAdminPassword) {
                $VmAdminPassword = Read-Host -Prompt "Enter admin password for VM '$($Config.Compute.VmName)'" -AsSecureString
            }

            $tags = New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Compute'; AutoShutdown = 'true' }

            $vnet = Get-AzVirtualNetwork -Name $Config.Network.VNetName -ResourceGroupName $Config.ResourceGroups.Network -ErrorAction Stop
            $appSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $Config.Network.Subnets.App.Name }
            if (-not $appSubnet) {
                throw "App subnet '$($Config.Network.Subnets.App.Name)' not found on VNet '$($Config.Network.VNetName)'. Run the Network phase first."
            }

            $vm = New-LabVirtualMachine -Name $Config.Compute.VmName -ResourceGroupName $Config.ResourceGroups.Compute `
                -Location $Config.Region -SubnetId $appSubnet.Id -VmSize $Config.Compute.VmSize -OsType $Config.Compute.OsType `
                -AdminUsername $Config.Compute.AdminUsername -AdminPassword $VmAdminPassword `
                -AutoShutdownTime $Config.Compute.AutoShutdownTime -AutoShutdownTimeZone $Config.Compute.AutoShutdownTimeZone `
                -Tags $tags -WhatIf:$WhatIfPreference
            Add-DeployResult -ResourceType 'VirtualMachine' -ResourceName $Config.Compute.VmName -Status 'Succeeded'
        }
        catch {
            Add-DeployResult -ResourceType 'VirtualMachine' -ResourceName $Config.Compute.VmName -Status "Failed: $($_.Exception.Message)"
            Write-LabLog -Message "Compute phase failed: $($_.Exception.Message)" -Level Error -LogPath $logPath
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-LabLog -Message '=== Deployment summary ===' -LogPath $logPath
$results | Format-Table -AutoSize | Out-String | Write-Host
$results | ForEach-Object { Write-LabLog -Message "$($_.Resource) | $($_.Name) | $($_.Status)" -LogPath $logPath }

Write-LabLog -Message "=== AzHomeLab deployment finished. Full log: $logPath ===" -LogPath $logPath

$failures = $results | Where-Object { $_.Status -like 'Failed*' }
if ($failures) {
    Write-Warning "Deployment completed with $($failures.Count) failed step(s). See $logPath for details."
}
