function Get-LabResourceName {
    <#
    .SYNOPSIS
        Builds a resource name that follows the AzHomeLab naming convention.

    .DESCRIPTION
        Implements the standard naming pattern <workload>-<env>-<region>-<resType>
        used throughout the AzHomeLab module (e.g. rg-homelab-dev-eastus).
        Storage accounts and Key Vaults use a compressed, dash-free pattern
        because of Azure's stricter naming rules for those resource types, so
        this function exposes a -Style switch to select the correct shape.

    .PARAMETER Workload
        The workload name segment, e.g. 'homelab'.

    .PARAMETER Environment
        The environment segment, e.g. 'dev'.

    .PARAMETER Region
        The Azure region segment, e.g. 'eastus'.

    .PARAMETER ResourceType
        The resource type token to append/prepend, e.g. 'rg', 'vnet', 'nsg-app', 'vm-jump01'.

    .PARAMETER Style
        Naming shape to produce:
          - 'Standard'  -> <resType>-<workload>-<env>-<region>            (default)
          - 'Compressed'-> <resType><workload><env><suffix>  (storage accounts: no dashes, lowercase)
          - 'KeyVault'  -> kv-<workload>-<env>-<suffix>

    .PARAMETER UniqueSuffix
        Required when -Style is 'Compressed' or 'KeyVault'; a short unique string.

    .EXAMPLE
        Get-LabResourceName -ResourceType 'rg' -Workload 'homelab' -Environment 'dev' -Region 'eastus'
        # rg-homelab-dev-eastus

    .EXAMPLE
        Get-LabResourceName -Style Compressed -ResourceType 'st' -Workload 'homelab' -Environment 'dev' -UniqueSuffix 'lab01'
        # sthomelabdevlab01
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Workload,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Environment,

        [Parameter(Mandatory = $false)]
        [string]$Region = 'eastus',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceType,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard', 'Compressed', 'KeyVault')]
        [string]$Style = 'Standard',

        [Parameter(Mandatory = $false)]
        [string]$UniqueSuffix
    )

    switch ($Style) {
        'Standard' {
            return ('{0}-{1}-{2}-{3}' -f $ResourceType, $Workload, $Environment, $Region).ToLowerInvariant()
        }
        'Compressed' {
            if (-not $UniqueSuffix) {
                throw "Get-LabResourceName: -UniqueSuffix is required when -Style is 'Compressed'."
            }
            $name = ('{0}{1}{2}{3}' -f $ResourceType, $Workload, $Environment, $UniqueSuffix).ToLowerInvariant()
            return ($name -replace '[^a-z0-9]', '')
        }
        'KeyVault' {
            if (-not $UniqueSuffix) {
                throw "Get-LabResourceName: -UniqueSuffix is required when -Style is 'KeyVault'."
            }
            return ('kv-{0}-{1}-{2}' -f $Workload, $Environment, $UniqueSuffix).ToLowerInvariant()
        }
    }
}
