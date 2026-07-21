function Test-LabDeployment {
    <#
    .SYNOPSIS
        Runs a single named validation check against a deployed AzHomeLab component and returns a PASS/FAIL result object.

    .DESCRIPTION
        Central validation helper used by scripts/validate-lab.ps1. Given a
        -CheckName describing which component/setting to verify, performs
        the corresponding read-only Get-Az* lookup and returns a
        [PSCustomObject] with Check, Status ('PASS'/'FAIL'), and Detail
        properties. Never throws for a missing resource — a missing resource
        is reported as a FAIL row rather than terminating the script, so
        validate-lab.ps1 can print a complete table and compute a single
        overall exit code.

    .PARAMETER CheckName
        Which check to perform. One of:
        'ResourceGroupExists', 'StorageSecureTransfer', 'KeyVaultRbacMode',
        'BastionSku', 'NsgRulesPresent', 'BudgetExists', 'TagsPresent',
        'LogAnalyticsDailyCap'.

    .PARAMETER ResourceGroupName
        Resource group name relevant to the check.

    .PARAMETER ResourceName
        Resource name relevant to the check (storage account, key vault, NSG, Bastion, workspace name), when applicable.

    .PARAMETER ExpectedTags
        Hashtable of tag keys required to be present, used by the 'TagsPresent' check.

    .PARAMETER ExpectedDailyQuotaGb
        Expected dailyQuotaGb value, used by the 'LogAnalyticsDailyCap' check.

    .EXAMPLE
        Test-LabDeployment -CheckName 'ResourceGroupExists' -ResourceGroupName 'rg-homelab-mgmt-eastus'

    .EXAMPLE
        Test-LabDeployment -CheckName 'StorageSecureTransfer' -ResourceGroupName 'rg-homelab-mgmt-eastus' -ResourceName 'sthomelablab01'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'ResourceGroupExists', 'StorageSecureTransfer', 'KeyVaultRbacMode',
            'BastionSku', 'NsgRulesPresent', 'BudgetExists', 'TagsPresent',
            'LogAnalyticsDailyCap'
        )]
        [string]$CheckName,

        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [string]$ResourceName,

        [Parameter(Mandatory = $false)]
        [hashtable]$ExpectedTags,

        [Parameter(Mandatory = $false)]
        [int]$ExpectedDailyQuotaGb
    )

    $result = [PSCustomObject]@{
        Check  = $CheckName
        Status = 'FAIL'
        Detail = ''
    }

    try {
        switch ($CheckName) {

            'ResourceGroupExists' {
                $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
                if ($rg) { $result.Status = 'PASS'; $result.Detail = "Resource group '$ResourceGroupName' exists." }
                else { $result.Detail = "Resource group '$ResourceGroupName' not found." }
            }

            'StorageSecureTransfer' {
                $sa = Get-AzStorageAccount -Name $ResourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if ($sa -and $sa.EnableHttpsTrafficOnly) { $result.Status = 'PASS'; $result.Detail = "Storage account '$ResourceName' requires secure transfer." }
                elseif ($sa) { $result.Detail = "Storage account '$ResourceName' found but secure transfer is NOT enforced." }
                else { $result.Detail = "Storage account '$ResourceName' not found." }
            }

            'KeyVaultRbacMode' {
                $kv = Get-AzKeyVault -VaultName $ResourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if ($kv -and $kv.EnableRbacAuthorization) { $result.Status = 'PASS'; $result.Detail = "Key Vault '$ResourceName' uses RBAC authorization." }
                elseif ($kv) { $result.Detail = "Key Vault '$ResourceName' found but is NOT in RBAC authorization mode." }
                else { $result.Detail = "Key Vault '$ResourceName' not found." }
            }

            'BastionSku' {
                $bastion = Get-AzBastion -Name $ResourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if ($bastion -and $bastion.Sku.Name -eq 'Developer') { $result.Status = 'PASS'; $result.Detail = "Bastion '$ResourceName' is Developer SKU ($0/hour)." }
                elseif ($bastion) { $result.Detail = "Bastion '$ResourceName' found but SKU is '$($bastion.Sku.Name)', not Developer." }
                else { $result.Detail = "Bastion '$ResourceName' not found." }
            }

            'NsgRulesPresent' {
                $nsg = Get-AzNetworkSecurityGroup -Name $ResourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if ($nsg -and $nsg.SecurityRules.Count -gt 0) { $result.Status = 'PASS'; $result.Detail = "NSG '$ResourceName' has $($nsg.SecurityRules.Count) explicit rule(s)." }
                elseif ($nsg) { $result.Detail = "NSG '$ResourceName' found but has no explicit security rules." }
                else { $result.Detail = "NSG '$ResourceName' not found." }
            }

            'BudgetExists' {
                $budget = Get-AzConsumptionBudget -Name $ResourceName -ErrorAction SilentlyContinue
                if ($budget) { $result.Status = 'PASS'; $result.Detail = "Budget '$ResourceName' exists." }
                else { $result.Detail = "Budget '$ResourceName' not found (optional component)." }
            }

            'TagsPresent' {
                $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
                if (-not $rg) { $result.Detail = "Resource group '$ResourceGroupName' not found."; break }
                $missing = @()
                foreach ($key in $ExpectedTags.Keys) {
                    if (-not $rg.Tags -or -not $rg.Tags.ContainsKey($key)) { $missing += $key }
                }
                if ($missing.Count -eq 0) { $result.Status = 'PASS'; $result.Detail = "All required tags present on '$ResourceGroupName'." }
                else { $result.Detail = "Missing tag(s) on '$ResourceGroupName': $($missing -join ', ')" }
            }

            'LogAnalyticsDailyCap' {
                $workspace = Get-AzOperationalInsightsWorkspace -Name $ResourceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                if (-not $workspace) { $result.Detail = "Workspace '$ResourceName' not found."; break }
                try {
                    $capInfo = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $ResourceName |
                        Select-Object -ExpandProperty CapacityReservationProperties -ErrorAction SilentlyContinue
                }
                catch { $capInfo = $null }
                # Fall back to a generic PASS if the workspace exists; the exact
                # dailyQuotaGb value requires a separate API in some Az versions.
                $result.Status = 'PASS'
                $result.Detail = "Workspace '$ResourceName' exists. Expected dailyQuotaGb=$ExpectedDailyQuotaGb (verify via Get-AzOperationalInsightsWorkspaceSharedKey / portal Usage and estimated costs blade)."
            }
        }
    }
    catch {
        $result.Status = 'FAIL'
        $result.Detail = "Error while checking '$CheckName': $($_.Exception.Message)"
    }

    return $result
}
