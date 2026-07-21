function Register-LabResourceProvider {
    <#
    .SYNOPSIS
        Idempotently registers the Azure resource providers required by AzHomeLab.

    .DESCRIPTION
        Checks the registration state of each supplied resource provider
        namespace with Get-AzResourceProvider and only calls
        Register-AzResourceProvider when it is not already 'Registered',
        avoiding redundant calls on repeat runs. Supports -WhatIf because it
        mutates subscription-level state.

    .PARAMETER ProviderNamespace
        One or more resource provider namespaces, e.g. 'Microsoft.KeyVault'.

    .EXAMPLE
        Register-LabResourceProvider -ProviderNamespace 'Microsoft.KeyVault','Microsoft.Network'

    .EXAMPLE
        'Microsoft.Storage' | Register-LabResourceProvider -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ProviderNamespace
    )

    process {
        foreach ($namespace in $ProviderNamespace) {
            try {
                $provider = Get-AzResourceProvider -ProviderNamespace $namespace -ErrorAction Stop |
                    Select-Object -First 1

                if ($provider -and $provider.RegistrationState -eq 'Registered') {
                    Write-Verbose "Register-LabResourceProvider: '$namespace' already registered. Skipping."
                    continue
                }

                if ($PSCmdlet.ShouldProcess($namespace, 'Register resource provider')) {
                    Write-Verbose "Register-LabResourceProvider: registering '$namespace'."
                    Register-AzResourceProvider -ProviderNamespace $namespace -ErrorAction Stop | Out-Null
                }
            }
            catch {
                Write-Error "Register-LabResourceProvider: failed to register '$namespace'. Error: $($_.Exception.Message)"
            }
        }
    }
}
