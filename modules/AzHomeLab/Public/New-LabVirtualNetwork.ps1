function New-LabVirtualNetwork {
    <#
    .SYNOPSIS
        Idempotently creates the AzHomeLab hub VNet with its subnets.

    .DESCRIPTION
        Creates (or returns the existing) virtual network containing three
        subnets: snet-mgmt, AzureBastionSubnet (required literal name for
        Azure Bastion, must be /26 or larger), and snet-app. If the VNet
        already exists, missing subnets are added rather than recreating the
        VNet. Supports -WhatIf/-Confirm because it creates billable-adjacent
        (though free-tier) network infrastructure.

    .PARAMETER Name
        Virtual network name, e.g. 'vnet-homelab-dev-eastus'.

    .PARAMETER ResourceGroupName
        Resource group the VNet belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER AddressPrefix
        VNet address space CIDR, e.g. '10.20.0.0/16'.

    .PARAMETER SubnetDefinition
        Hashtable of subnet definitions, each with Name and AddressPrefix,
        as produced by config/lab.config.psd1 -> Network.Subnets.

    .PARAMETER Tags
        Tag hashtable to apply to the VNet.

    .EXAMPLE
        New-LabVirtualNetwork -Name 'vnet-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-network-eastus' `
            -Location 'eastus' -AddressPrefix '10.20.0.0/16' -SubnetDefinition $Config.Network.Subnets -Tags $tags
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$')]
        [string]$AddressPrefix,

        [Parameter(Mandatory = $true)]
        [hashtable]$SubnetDefinition,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags
    )

    try {
        $existingVnet = Get-AzVirtualNetwork -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if ($existingVnet) {
            Write-Verbose "New-LabVirtualNetwork: VNet '$Name' already exists. Checking subnets."

            $changed = $false
            foreach ($key in $SubnetDefinition.Keys) {
                $subnetDef = $SubnetDefinition[$key]
                $existingSubnet = $existingVnet.Subnets | Where-Object { $_.Name -eq $subnetDef.Name }
                if (-not $existingSubnet) {
                    if ($PSCmdlet.ShouldProcess($subnetDef.Name, "Add subnet to VNet '$Name'")) {
                        Write-Verbose "New-LabVirtualNetwork: adding missing subnet '$($subnetDef.Name)'."
                        Add-AzVirtualNetworkSubnetConfig -Name $subnetDef.Name -AddressPrefix $subnetDef.AddressPrefix -VirtualNetwork $existingVnet | Out-Null
                        $changed = $true
                    }
                }
            }

            if ($changed) {
                $existingVnet = Set-AzVirtualNetwork -VirtualNetwork $existingVnet -ErrorAction Stop
            }

            return $existingVnet
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create virtual network in '$Location' ($AddressPrefix)")) {
            Write-Verbose "New-LabVirtualNetwork: creating VNet '$Name' with $($SubnetDefinition.Count) subnets."

            $subnetConfigs = @()
            foreach ($key in $SubnetDefinition.Keys) {
                $subnetDef = $SubnetDefinition[$key]
                $subnetConfigs += New-AzVirtualNetworkSubnetConfig -Name $subnetDef.Name -AddressPrefix $subnetDef.AddressPrefix
            }

            return New-AzVirtualNetwork -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location `
                -AddressPrefix $AddressPrefix -Subnet $subnetConfigs -Tag $Tags -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabVirtualNetwork: failed to create or update VNet '$Name'. Error: $($_.Exception.Message)"
    }
}
