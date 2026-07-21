function New-LabResourceGroup {
    <#
    .SYNOPSIS
        Idempotently creates (or returns the existing) AzHomeLab resource group.

    .DESCRIPTION
        Checks for an existing resource group by name with Get-AzResourceGroup
        before calling New-AzResourceGroup, so repeat deployments do not fail
        and the existing object's tags are respected unless -Force is used to
        re-apply the standard tag set. Supports -WhatIf/-Confirm.

    .PARAMETER Name
        Resource group name, e.g. 'rg-homelab-mgmt-eastus'.

    .PARAMETER Location
        Azure region, e.g. 'eastus'.

    .PARAMETER Tags
        Tag hashtable to apply (see New-LabTag).

    .PARAMETER Force
        If the resource group already exists, re-apply the supplied tags.

    .EXAMPLE
        New-LabResourceGroup -Name 'rg-homelab-mgmt-eastus' -Location 'eastus' -Tags $tags

    .EXAMPLE
        New-LabResourceGroup -Name 'rg-homelab-network-eastus' -Location 'eastus' -Tags $tags -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 90)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        $existing = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Verbose "New-LabResourceGroup: resource group '$Name' already exists."
            if ($Force -and $PSCmdlet.ShouldProcess($Name, 'Update tags on existing resource group')) {
                Set-AzResourceGroup -Name $Name -Tag $Tags -ErrorAction Stop | Out-Null
                $existing = Get-AzResourceGroup -Name $Name
            }
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create resource group in '$Location'")) {
            Write-Verbose "New-LabResourceGroup: creating resource group '$Name' in '$Location'."
            return New-AzResourceGroup -Name $Name -Location $Location -Tag $Tags -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabResourceGroup: failed to create or retrieve resource group '$Name'. Error: $($_.Exception.Message)"
    }
}
