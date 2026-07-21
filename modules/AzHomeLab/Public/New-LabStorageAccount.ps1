function New-LabStorageAccount {
    <#
    .SYNOPSIS
        Idempotently creates the AzHomeLab storage account, containers, and RBAC assignment.

    .DESCRIPTION
        Creates (or returns the existing) Standard_LRS storage account with
        secure transfer required, public blob access disabled, and TLS 1.2
        minimum. Ensures the 'scripts', 'logs', and 'state' blob containers
        exist. Optionally grants the caller (or supplied principal) the
        'Storage Blob Data Contributor' RBAC role at the storage account
        scope, in place of SAS tokens, as the recommended best practice.
        Storage accounts are NOT part of the always-free/12-months-free list;
        they are low-cost pay-as-you-go and round to fractions of a cent per
        month at lab scale.

    .PARAMETER Name
        Storage account name: lowercase, no dashes, <= 24 characters.

    .PARAMETER ResourceGroupName
        Resource group the storage account belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER SkuName
        Storage redundancy SKU. Defaults to 'Standard_LRS'.

    .PARAMETER Containers
        List of blob container names to ensure exist.

    .PARAMETER Tags
        Tag hashtable to apply.

    .PARAMETER GrantRbacToPrincipalId
        Optional object ID of a principal to grant 'Storage Blob Data Contributor'
        at the storage account scope. If omitted, no role assignment is made.

    .EXAMPLE
        New-LabStorageAccount -Name 'sthomelablab01' -ResourceGroupName 'rg-homelab-mgmt-eastus' -Location 'eastus' -Containers 'scripts','logs','state' -Tags $tags
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(3, 24)]
        [ValidatePattern('^[a-z0-9]+$')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Standard_LRS', 'Standard_GRS', 'Standard_ZRS')]
        [string]$SkuName = 'Standard_LRS',

        [Parameter(Mandatory = $true)]
        [string[]]$Containers,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags,

        [Parameter(Mandatory = $false)]
        [string]$GrantRbacToPrincipalId
    )

    try {
        $storageAccount = Get-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if (-not $storageAccount) {
            if ($PSCmdlet.ShouldProcess($Name, "Create storage account in '$Location'")) {
                Write-Verbose "New-LabStorageAccount: creating storage account '$Name'."
                $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $Name -Location $Location `
                    -SkuName $SkuName -Kind StorageV2 -MinimumTlsVersion TLS1_2 `
                    -EnableHttpsTrafficOnly $true -AllowBlobPublicAccess $false -Tag $Tags -ErrorAction Stop
            }
        }
        else {
            Write-Verbose "New-LabStorageAccount: storage account '$Name' already exists. Skipping creation."
        }

        if ($storageAccount) {
            $ctx = $storageAccount.Context
            foreach ($containerName in $Containers) {
                $existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
                if (-not $existingContainer) {
                    if ($PSCmdlet.ShouldProcess($containerName, "Create blob container in storage account '$Name'")) {
                        Write-Verbose "New-LabStorageAccount: creating container '$containerName'."
                        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off -ErrorAction Stop | Out-Null
                    }
                }
                else {
                    Write-Verbose "New-LabStorageAccount: container '$containerName' already exists. Skipping."
                }
            }

            if ($GrantRbacToPrincipalId) {
                $scope = $storageAccount.Id
                $existingAssignment = Get-AzRoleAssignment -ObjectId $GrantRbacToPrincipalId -Scope $scope -RoleDefinitionName 'Storage Blob Data Contributor' -ErrorAction SilentlyContinue
                if (-not $existingAssignment) {
                    if ($PSCmdlet.ShouldProcess($GrantRbacToPrincipalId, "Grant 'Storage Blob Data Contributor' at scope $scope")) {
                        Write-Verbose "New-LabStorageAccount: granting Storage Blob Data Contributor to '$GrantRbacToPrincipalId'."
                        New-AzRoleAssignment -ObjectId $GrantRbacToPrincipalId -RoleDefinitionName 'Storage Blob Data Contributor' -Scope $scope -ErrorAction Stop | Out-Null
                    }
                }
                else {
                    Write-Verbose "New-LabStorageAccount: RBAC role assignment already present for '$GrantRbacToPrincipalId'."
                }
            }
        }

        return $storageAccount
    }
    catch {
        throw "New-LabStorageAccount: failed to create or configure storage account '$Name'. Error: $($_.Exception.Message)"
    }
}
