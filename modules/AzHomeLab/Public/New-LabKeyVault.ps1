function New-LabKeyVault {
    <#
    .SYNOPSIS
        Idempotently creates the AzHomeLab Key Vault with RBAC authorization and a demo secret.

    .DESCRIPTION
        Creates (or returns the existing) Key Vault configured for RBAC
        authorization mode (not legacy access policies), with soft-delete
        enabled (default/mandatory in current Azure Key Vault) and purge
        protection enabled per lab best practice. Writes one demo secret
        (DemoConnectionString) to prove the end-to-end secret-write pattern.
        Key Vault is NOT part of the always-free/12-months-free list; it is
        classified as low-cost pay-as-you-go (fractions of a cent per
        operation at lab scale).

    .PARAMETER Name
        Key Vault name, e.g. 'kv-homelab-dev-lab01'.

    .PARAMETER ResourceGroupName
        Resource group the Key Vault belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER Tags
        Tag hashtable to apply.

    .PARAMETER EnablePurgeProtection
        Whether to enable purge protection. Defaults to $true.

    .PARAMETER SoftDeleteRetentionInDays
        Soft-delete retention window in days. Defaults to 7.

    .PARAMETER DemoSecretName
        Name of the demo secret to write, e.g. 'DemoConnectionString'.

    .PARAMETER DemoSecretValue
        Value of the demo secret to write.

    .EXAMPLE
        New-LabKeyVault -Name 'kv-homelab-dev-lab01' -ResourceGroupName 'rg-homelab-mgmt-eastus' -Location 'eastus' `
            -Tags $tags -DemoSecretName 'DemoConnectionString' -DemoSecretValue 'Server=tcp:demo;'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        '',
        Justification = 'DemoSecretValue is a caller-supplied Mandatory string parameter, not a hardcoded credential. Set-AzKeyVaultSecret requires a SecureString, so converting the caller-provided plain text is the documented Az PowerShell pattern for writing a secret value here.')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(3, 24)]
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
        [bool]$EnablePurgeProtection = $true,

        [Parameter(Mandatory = $false)]
        [ValidateRange(7, 90)]
        [int]$SoftDeleteRetentionInDays = 7,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DemoSecretName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DemoSecretValue
    )

    try {
        $vault = Get-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if (-not $vault) {
            if ($PSCmdlet.ShouldProcess($Name, "Create Key Vault (RBAC mode) in '$Location'")) {
                Write-Verbose "New-LabKeyVault: creating Key Vault '$Name' with RBAC authorization."
                $vault = New-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -Location $Location `
                    -EnableRbacAuthorization $true -EnablePurgeProtection:$EnablePurgeProtection `
                    -SoftDeleteRetentionInDays $SoftDeleteRetentionInDays -Tag $Tags -ErrorAction Stop
            }
        }
        else {
            Write-Verbose "New-LabKeyVault: Key Vault '$Name' already exists. Skipping creation."
        }

        if ($vault) {
            $existingSecret = $null
            try {
                $existingSecret = Get-AzKeyVaultSecret -VaultName $Name -Name $DemoSecretName -ErrorAction SilentlyContinue
            }
            catch {
                # Caller may not yet have Key Vault Secrets User/Officer RBAC role
                # propagated; treat as "not found" and attempt the write below.
                Write-Verbose "New-LabKeyVault: could not read existing secret (may not have RBAC role yet): $($_.Exception.Message)"
            }

            if (-not $existingSecret) {
                if ($PSCmdlet.ShouldProcess($DemoSecretName, "Write demo secret to Key Vault '$Name'")) {
                    Write-Verbose "New-LabKeyVault: writing demo secret '$DemoSecretName'."
                    $secureValue = ConvertTo-SecureString -String $DemoSecretValue -AsPlainText -Force
                    Set-AzKeyVaultSecret -VaultName $Name -Name $DemoSecretName -SecretValue $secureValue -ErrorAction Stop | Out-Null
                }
            }
            else {
                Write-Verbose "New-LabKeyVault: demo secret '$DemoSecretName' already exists. Skipping."
            }
        }

        return $vault
    }
    catch {
        throw "New-LabKeyVault: failed to create or configure Key Vault '$Name'. Error: $($_.Exception.Message)"
    }
}
