function New-LabBastion {
    <#
    .SYNOPSIS
        Idempotently deploys Azure Bastion using the $0/hour Developer SKU.

    .DESCRIPTION
        Creates (or returns the existing) Azure Bastion host attached to the
        AzureBastionSubnet of the supplied VNet, using the Developer SKU —
        which has no hourly charge and free outbound data transfer, unlike
        Basic/Standard Bastion ($130-$200+/month). Developer SKU is not
        available in every region; if deployment fails because the SKU is
        unsupported in the target region, the error message directs the
        caller to the documented zero-cost NSG fallback instead.
        Reference: https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison
        Reference: https://azure.microsoft.com/en-us/blog/introducing-azure-bastion-developer-secure-and-cost-effective-access-to-your-azure-virtual-machines/

    .PARAMETER Name
        Bastion resource name, e.g. 'bas-homelab-dev-eastus'.

    .PARAMETER ResourceGroupName
        Resource group the Bastion host belongs to.

    .PARAMETER Location
        Azure region. Developer SKU availability varies by region.

    .PARAMETER VirtualNetworkName
        Name of the VNet containing the required 'AzureBastionSubnet'.

    .PARAMETER Tags
        Tag hashtable to apply.

    .EXAMPLE
        New-LabBastion -Name 'bas-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-network-eastus' `
            -Location 'eastus' -VirtualNetworkName 'vnet-homelab-dev-eastus' -Tags $tags
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
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
        [ValidateNotNullOrEmpty()]
        [string]$VirtualNetworkName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags
    )

    try {
        $existing = Get-AzBastion -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Verbose "New-LabBastion: Bastion host '$Name' already exists. Skipping creation."
            return $existing
        }

        $vnet = Get-AzVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        $bastionSubnet = $vnet.Subnets | Where-Object { $_.Name -eq 'AzureBastionSubnet' }
        if (-not $bastionSubnet) {
            throw "New-LabBastion: VNet '$VirtualNetworkName' does not contain the required 'AzureBastionSubnet'. Create it first (must be /26 or larger)."
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create Azure Bastion (Developer SKU) in '$Location'")) {
            Write-Verbose "New-LabBastion: creating Bastion '$Name' with Developer SKU (free, no hourly charge)."

            try {
                return New-AzBastion -Name $Name -ResourceGroupName $ResourceGroupName -VirtualNetwork $vnet `
                    -Sku 'Developer' -ErrorAction Stop
            }
            catch {
                throw "New-LabBastion: failed to create Bastion Developer SKU in region '$Location'. " + `
                    "Developer SKU is not available in every region — see https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison. " + `
                    "Fall back to the zero-cost NSG IP-restriction pattern documented in docs/architecture.md instead. Original error: $($_.Exception.Message)"
            }
        }
    }
    catch {
        throw "New-LabBastion: $($_.Exception.Message)"
    }
}
