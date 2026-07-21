function Remove-LabResourceLock {
    <#
    .SYNOPSIS
        Detects and removes all resource locks on a resource group.

    .DESCRIPTION
        Used by cleanup-lab.ps1 to guarantee resource group deletion is not
        blocked by governance locks created earlier (e.g. by
        New-LabResourceLock). Enumerates all locks at the resource group
        scope and removes each one. Idempotent: if no locks are present, it
        returns silently rather than throwing.

    .PARAMETER ResourceGroupName
        Resource group to remove locks from.

    .EXAMPLE
        Remove-LabResourceLock -ResourceGroupName 'rg-homelab-mgmt-eastus'

    .EXAMPLE
        Remove-LabResourceLock -ResourceGroupName 'rg-homelab-mgmt-eastus' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName
    )

    try {
        $locks = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if (-not $locks) {
            Write-Verbose "Remove-LabResourceLock: no locks found on '$ResourceGroupName'."
            return
        }

        foreach ($lock in $locks) {
            if ($PSCmdlet.ShouldProcess($lock.Name, "Remove lock from '$ResourceGroupName'")) {
                Write-Verbose "Remove-LabResourceLock: removing lock '$($lock.Name)' from '$ResourceGroupName'."
                Remove-AzResourceLock -LockId $lock.LockId -Force -ErrorAction Stop | Out-Null
            }
        }
    }
    catch {
        Write-Error "Remove-LabResourceLock: failed to remove locks from '$ResourceGroupName'. Error: $($_.Exception.Message)"
    }
}
