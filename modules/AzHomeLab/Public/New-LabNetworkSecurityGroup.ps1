function New-LabNetworkSecurityGroup {
    <#
    .SYNOPSIS
        Idempotently creates an NSG with deny-by-default, allow-only-what's-needed rules.

    .DESCRIPTION
        Creates (or returns the existing) Network Security Group and, on
        create, attaches an explicit set of security rules. By design, RDP
        (3389) and SSH (22) are NEVER opened to the internet here — access is
        intended via Azure Bastion Developer SKU. An optional
        -AllowedManagementIp parameter supports the documented zero-cost
        fallback (locking RDP/SSH to the caller's current public IP) for
        regions where Bastion Developer is unavailable. Supports -WhatIf.

    .PARAMETER Name
        NSG name, e.g. 'nsg-mgmt-homelab-dev-eastus'.

    .PARAMETER ResourceGroupName
        Resource group the NSG belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER Tags
        Tag hashtable to apply.

    .PARAMETER AllowedManagementIp
        Optional single IPv4 address (no CIDR) to allow inbound RDP(3389)/SSH(22)
        from, used only as the documented Bastion-unavailable fallback. When
        omitted (default/recommended path), no RDP/SSH inbound rule is created
        at all — access is via Bastion only.

    .EXAMPLE
        New-LabNetworkSecurityGroup -Name 'nsg-mgmt-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-network-eastus' -Location 'eastus' -Tags $tags

    .EXAMPLE
        New-LabNetworkSecurityGroup -Name 'nsg-app-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-network-eastus' -Location 'eastus' -Tags $tags -AllowedManagementIp '203.0.113.10'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup])]
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
        [hashtable]$Tags,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
        [string]$AllowedManagementIp
    )

    try {
        $existing = Get-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Verbose "New-LabNetworkSecurityGroup: NSG '$Name' already exists. Skipping creation."
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create network security group in '$Location'")) {
            Write-Verbose "New-LabNetworkSecurityGroup: creating NSG '$Name'."

            $rules = @()

            # Deny all inbound from Internet by default (explicit, even though
            # Azure's implicit DenyAllInbound already covers this — being explicit
            # documents intent for reviewers/interviewers).
            $rules += New-AzNetworkSecurityRuleConfig -Name 'Deny-Internet-Inbound' -Description 'Explicit deny-by-default for all internet inbound traffic' `
                -Access Deny -Protocol '*' -Direction Inbound -Priority 4096 `
                -SourceAddressPrefix 'Internet' -SourcePortRange '*' `
                -DestinationAddressPrefix '*' -DestinationPortRange '*'

            # Allow inbound from the Bastion subnet only, for RDP/SSH management,
            # so access flows exclusively through Azure Bastion Developer SKU.
            $rules += New-AzNetworkSecurityRuleConfig -Name 'Allow-Bastion-Subnet-RDP-SSH' -Description 'Allow RDP/SSH only from the AzureBastionSubnet range' `
                -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
                -SourceAddressPrefix '10.20.1.0/26' -SourcePortRange '*' `
                -DestinationAddressPrefix '*' -DestinationPortRanges @('3389', '22')

            if ($AllowedManagementIp) {
                # Zero-cost fallback path for regions without Bastion Developer:
                # lock RDP/SSH inbound to the caller's current public IP only.
                Write-Verbose "New-LabNetworkSecurityGroup: adding fallback rule allowing RDP/SSH from $AllowedManagementIp/32 only."
                $rules += New-AzNetworkSecurityRuleConfig -Name 'Allow-CurrentIP-RDP-SSH-Fallback' -Description 'Zero-cost fallback: RDP/SSH allowed only from the deployer current public IP. Remove via cleanup-lab.ps1.' `
                    -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
                    -SourceAddressPrefix "$AllowedManagementIp/32" -SourcePortRange '*' `
                    -DestinationAddressPrefix '*' -DestinationPortRanges @('3389', '22')
            }

            # Allow outbound to Azure Bastion / Azure platform for session traffic.
            $rules += New-AzNetworkSecurityRuleConfig -Name 'Allow-Outbound-AzureCloud' -Description 'Allow outbound to Azure platform services' `
                -Access Allow -Protocol '*' -Direction Outbound -Priority 100 `
                -SourceAddressPrefix '*' -SourcePortRange '*' `
                -DestinationAddressPrefix 'AzureCloud' -DestinationPortRange '*'

            return New-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location `
                -SecurityRules $rules -Tag $Tags -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabNetworkSecurityGroup: failed to create NSG '$Name'. Error: $($_.Exception.Message)"
    }
}
