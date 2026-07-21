<#
.SYNOPSIS
    Tears down the AzHomeLab environment in a safe dependency order.

.DESCRIPTION
    Removes AzHomeLab resources in the order required to avoid dependency
    conflicts: VM -> NIC/disks -> Bastion -> VNet -> Key Vault (with an
    optional purge) -> Storage -> Log Analytics -> Policy assignment ->
    Resource groups. Resource locks are detected and removed FIRST, because
    a CanNotDelete lock on rg-homelab-mgmt-eastus (created by
    New-LabResourceLock during the Security phase) would otherwise block
    resource group deletion. Every removal step is idempotent: if a resource
    is already absent, the script logs that fact and continues rather than
    throwing. Supports -WhatIf and a -Force switch to bypass confirmation
    prompts for unattended runs.

.PARAMETER ConfigPath
    Path to the lab configuration .psd1 file. Defaults to '../config/lab.config.psd1'
    relative to this script's directory.

.PARAMETER Force
    Skip the interactive confirmation prompt before deleting resources.

.PARAMETER PurgeKeyVault
    After removing the Key Vault, also purge it from soft-delete state so
    the name can be reused immediately. Off by default because purge is
    irreversible.

.EXAMPLE
    ./cleanup-lab.ps1 -WhatIf

.EXAMPLE
    ./cleanup-lab.ps1 -Force -PurgeKeyVault
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1'),

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$PurgeKeyVault
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}
catch {
    throw "cleanup-lab.ps1: failed to import the AzHomeLab module from '$modulePath'. Error: $($_.Exception.Message)"
}

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context -or -not $context.Subscription) {
    throw "cleanup-lab.ps1: no active Az PowerShell context was found. Run 'Connect-AzAccount' and re-run this script."
}

$Config = Get-LabConfig -Path $ConfigPath

$logDirectory = Join-Path -Path $PSScriptRoot -ChildPath $Config.Deploy.LogDirectory
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path -Path $logDirectory -ChildPath "cleanup-lab-$timestamp.log"

if (-not $Force) {
    $confirmation = Read-Host "This will delete AzHomeLab resource groups ($($Config.ResourceGroups.Mgmt), $($Config.ResourceGroups.Network), $($Config.ResourceGroups.Compute)) and their contents. Type 'yes' to continue"
    if ($confirmation -ne 'yes') {
        Write-LabLog -Message 'Cleanup aborted by user (confirmation not given).' -LogPath $logPath
        return
    }
}

Write-LabLog -Message '=== AzHomeLab cleanup started ===' -LogPath $logPath

# ---------------------------------------------------------------------------
# 1. Remove resource locks first so RG deletion is not blocked
# ---------------------------------------------------------------------------
foreach ($rgKey in @('Mgmt', 'Network', 'Compute')) {
    $rgName = $Config.ResourceGroups[$rgKey]
    if (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue) {
        Write-LabLog -Message "Removing resource locks (if any) from '$rgName'." -LogPath $logPath
        Remove-LabResourceLock -ResourceGroupName $rgName -WhatIf:$WhatIfPreference
    }
    else {
        Write-LabLog -Message "Resource group '$rgName' not found; nothing to unlock." -Level Verbose -LogPath $logPath
    }
}

# ---------------------------------------------------------------------------
# 2. Virtual machine, then its NIC and disks
# ---------------------------------------------------------------------------
try {
    $vm = Get-AzVM -Name $Config.Compute.VmName -ResourceGroupName $Config.ResourceGroups.Compute -ErrorAction SilentlyContinue
    if ($vm) {
        if ($PSCmdlet.ShouldProcess($Config.Compute.VmName, 'Remove virtual machine')) {
            Write-LabLog -Message "Removing VM '$($Config.Compute.VmName)'." -LogPath $logPath
            Remove-AzVM -Name $Config.Compute.VmName -ResourceGroupName $Config.ResourceGroups.Compute -Force -ErrorAction Stop | Out-Null
        }

        $nicName = "nic-$($Config.Compute.VmName)"
        $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $Config.ResourceGroups.Compute -ErrorAction SilentlyContinue
        if ($nic -and $PSCmdlet.ShouldProcess($nicName, 'Remove network interface')) {
            Write-LabLog -Message "Removing NIC '$nicName'." -LogPath $logPath
            Remove-AzNetworkInterface -Name $nicName -ResourceGroupName $Config.ResourceGroups.Compute -Force -ErrorAction Stop
        }

        $disks = Get-AzDisk -ResourceGroupName $Config.ResourceGroups.Compute -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$($Config.Compute.VmName)*" }
        foreach ($disk in $disks) {
            if ($PSCmdlet.ShouldProcess($disk.Name, 'Remove managed disk')) {
                Write-LabLog -Message "Removing disk '$($disk.Name)'." -LogPath $logPath
                Remove-AzDisk -ResourceGroupName $Config.ResourceGroups.Compute -DiskName $disk.Name -Force -ErrorAction Stop | Out-Null
            }
        }
    }
    else {
        Write-LabLog -Message "VM '$($Config.Compute.VmName)' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing VM/NIC/disks: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 3. Bastion
# ---------------------------------------------------------------------------
try {
    $bastion = Get-AzBastion -Name $Config.Network.BastionName -ResourceGroupName $Config.ResourceGroups.Network -ErrorAction SilentlyContinue
    if ($bastion) {
        if ($PSCmdlet.ShouldProcess($Config.Network.BastionName, 'Remove Bastion host')) {
            Write-LabLog -Message "Removing Bastion '$($Config.Network.BastionName)'." -LogPath $logPath
            Remove-AzBastion -Name $Config.Network.BastionName -ResourceGroupName $Config.ResourceGroups.Network -Force -ErrorAction Stop
        }
    }
    else {
        Write-LabLog -Message "Bastion '$($Config.Network.BastionName)' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing Bastion: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 4. Virtual network
# ---------------------------------------------------------------------------
try {
    $vnet = Get-AzVirtualNetwork -Name $Config.Network.VNetName -ResourceGroupName $Config.ResourceGroups.Network -ErrorAction SilentlyContinue
    if ($vnet) {
        if ($PSCmdlet.ShouldProcess($Config.Network.VNetName, 'Remove virtual network')) {
            Write-LabLog -Message "Removing VNet '$($Config.Network.VNetName)'." -LogPath $logPath
            Remove-AzVirtualNetwork -Name $Config.Network.VNetName -ResourceGroupName $Config.ResourceGroups.Network -Force -ErrorAction Stop
        }
    }
    else {
        Write-LabLog -Message "VNet '$($Config.Network.VNetName)' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing VNet: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 5. Key Vault (remove, then optionally purge)
# ---------------------------------------------------------------------------
try {
    $keyVaultName = Get-LabResourceName -Style KeyVault -ResourceType 'kv' -Workload $Config.Workload `
        -Environment $Config.Environment -UniqueSuffix $Config.UniqueSuffix

    $vault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $Config.ResourceGroups.Mgmt -ErrorAction SilentlyContinue
    if ($vault) {
        if ($PSCmdlet.ShouldProcess($keyVaultName, 'Remove Key Vault')) {
            Write-LabLog -Message "Removing Key Vault '$keyVaultName'." -LogPath $logPath
            Remove-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $Config.ResourceGroups.Mgmt -Force -ErrorAction Stop

            if ($PurgeKeyVault -and $PSCmdlet.ShouldProcess($keyVaultName, 'Purge soft-deleted Key Vault')) {
                Write-LabLog -Message "Purging soft-deleted Key Vault '$keyVaultName'." -LogPath $logPath
                Remove-AzKeyVault -VaultName $keyVaultName -Location $Config.Region -InRemovedState -Force -ErrorAction Stop
            }
        }
    }
    else {
        Write-LabLog -Message "Key Vault '$keyVaultName' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing Key Vault: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 6. Storage account
# ---------------------------------------------------------------------------
try {
    $storageAccountName = Get-LabResourceName -Style Compressed -ResourceType $Config.Storage.AccountNamePrefix `
        -Workload '' -Environment '' -UniqueSuffix $Config.UniqueSuffix

    $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $Config.ResourceGroups.Mgmt -ErrorAction SilentlyContinue
    if ($storageAccount) {
        if ($PSCmdlet.ShouldProcess($storageAccountName, 'Remove storage account')) {
            Write-LabLog -Message "Removing storage account '$storageAccountName'." -LogPath $logPath
            Remove-AzStorageAccount -Name $storageAccountName -ResourceGroupName $Config.ResourceGroups.Mgmt -Force -ErrorAction Stop
        }
    }
    else {
        Write-LabLog -Message "Storage account '$storageAccountName' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing storage account: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 7. Log Analytics workspace
# ---------------------------------------------------------------------------
try {
    $workspace = Get-AzOperationalInsightsWorkspace -Name $Config.Monitoring.WorkspaceName -ResourceGroupName $Config.ResourceGroups.Mgmt -ErrorAction SilentlyContinue
    if ($workspace) {
        if ($PSCmdlet.ShouldProcess($Config.Monitoring.WorkspaceName, 'Remove Log Analytics workspace')) {
            Write-LabLog -Message "Removing Log Analytics workspace '$($Config.Monitoring.WorkspaceName)'." -LogPath $logPath
            Remove-AzOperationalInsightsWorkspace -Name $Config.Monitoring.WorkspaceName -ResourceGroupName $Config.ResourceGroups.Mgmt -Force -ErrorAction Stop
        }
    }
    else {
        Write-LabLog -Message "Log Analytics workspace '$($Config.Monitoring.WorkspaceName)' not found; already absent." -Level Verbose -LogPath $logPath
    }
}
catch {
    Write-LabLog -Message "Error removing Log Analytics workspace: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 8. Policy assignment
# ---------------------------------------------------------------------------
try {
    $rg = Get-AzResourceGroup -Name $Config.ResourceGroups.Mgmt -ErrorAction SilentlyContinue
    if ($rg) {
        $assignment = Get-AzPolicyAssignment -Name $Config.Governance.PolicyAssignmentName -Scope $rg.ResourceId -ErrorAction SilentlyContinue
        if ($assignment) {
            if ($PSCmdlet.ShouldProcess($Config.Governance.PolicyAssignmentName, 'Remove policy assignment')) {
                Write-LabLog -Message "Removing policy assignment '$($Config.Governance.PolicyAssignmentName)'." -LogPath $logPath
                Remove-AzPolicyAssignment -Name $Config.Governance.PolicyAssignmentName -Scope $rg.ResourceId -ErrorAction Stop
            }
        }
        else {
            Write-LabLog -Message "Policy assignment '$($Config.Governance.PolicyAssignmentName)' not found; already absent." -Level Verbose -LogPath $logPath
        }
    }
}
catch {
    Write-LabLog -Message "Error removing policy assignment: $($_.Exception.Message)" -Level Warning -LogPath $logPath
}

# ---------------------------------------------------------------------------
# 9. Resource groups (last)
# ---------------------------------------------------------------------------
foreach ($rgKey in @('Compute', 'Network', 'Mgmt')) {
    $rgName = $Config.ResourceGroups[$rgKey]
    try {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
        if ($rg) {
            if ($PSCmdlet.ShouldProcess($rgName, 'Remove resource group')) {
                Write-LabLog -Message "Removing resource group '$rgName'." -LogPath $logPath
                Remove-AzResourceGroup -Name $rgName -Force -ErrorAction Stop
            }
        }
        else {
            Write-LabLog -Message "Resource group '$rgName' not found; already absent." -Level Verbose -LogPath $logPath
        }
    }
    catch {
        Write-LabLog -Message "Error removing resource group '$rgName': $($_.Exception.Message)" -Level Warning -LogPath $logPath
    }
}

Write-LabLog -Message "=== AzHomeLab cleanup finished. Full log: $logPath ===" -LogPath $logPath
