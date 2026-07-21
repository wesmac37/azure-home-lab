function New-LabResourceLock {
    <#
    .SYNOPSIS
        Idempotently applies a CanNotDelete resource lock to a resource group.

    .DESCRIPTION
        Demonstrates the resource-lock governance pattern by applying a
        CanNotDelete lock to the supplied resource group scope (default:
        rg-homelab-mgmt-eastus). Because this lock will block
        cleanup-lab.ps1 from deleting the resource group, cleanup-lab.ps1
        detects and removes locks first via Remove-LabResourceLock.

    .PARAMETER Name
        Lock name, e.g. 'lock-homelab-mgmt-CanNotDelete'.

    .PARAMETER ResourceGroupName
        Resource group to lock.

    .PARAMETER LockLevel
        Lock level. Defaults to 'CanNotDelete'.

    .PARAMETER Notes
        Free-text note describing the lock's purpose.

    .EXAMPLE
        New-LabResourceLock -Name 'lock-homelab-mgmt-CanNotDelete' -ResourceGroupName 'rg-homelab-mgmt-eastus'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('CanNotDelete', 'ReadOnly')]
        [string]$LockLevel = 'CanNotDelete',

        [Parameter(Mandatory = $false)]
        [string]$Notes = 'Example governance lock created by AzHomeLab. Must be removed (see cleanup-lab.ps1) before the resource group can be deleted.'
    )

    try {
        $existing = Get-AzResourceLock -LockName $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Verbose "New-LabResourceLock: lock '$Name' already exists on '$ResourceGroupName'. Skipping."
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Apply $LockLevel lock '$Name'")) {
            Write-Verbose "New-LabResourceLock: applying $LockLevel lock '$Name' to '$ResourceGroupName'."
            return New-AzResourceLock -LockName $Name -LockLevel $LockLevel -ResourceGroupName $ResourceGroupName -LockNotes $Notes -Force -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabResourceLock: failed to apply lock '$Name' to '$ResourceGroupName'. Error: $($_.Exception.Message)"
    }
}
