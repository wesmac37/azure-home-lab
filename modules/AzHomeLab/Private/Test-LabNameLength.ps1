function Test-LabNameLength {
    <#
    .SYNOPSIS
        Validates that a proposed resource name fits within an Azure resource
        type's documented length constraints.

    .DESCRIPTION
        Internal helper used by naming functions (e.g. New-LabStorageAccount,
        New-LabKeyVault) to fail fast with a clear error before making an Azure
        API call, rather than letting Azure reject the name after the fact.

    .PARAMETER Name
        The proposed resource name.

    .PARAMETER MinLength
        Minimum allowed length. Defaults to 1.

    .PARAMETER MaxLength
        Maximum allowed length.

    .PARAMETER ResourceTypeLabel
        Friendly label used in the thrown error message, e.g. 'Storage Account'.

    .EXAMPLE
        Test-LabNameLength -Name 'sthomelablab01' -MinLength 3 -MaxLength 24 -ResourceTypeLabel 'Storage Account'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [int]$MinLength = 1,

        [Parameter(Mandatory = $true)]
        [int]$MaxLength,

        [Parameter(Mandatory = $false)]
        [string]$ResourceTypeLabel = 'Resource'
    )

    if ($Name.Length -lt $MinLength -or $Name.Length -gt $MaxLength) {
        throw "$ResourceTypeLabel name '$Name' is $($Name.Length) characters long; must be between $MinLength and $MaxLength characters."
    }

    return $true
}
