function Get-LabConfig {
    <#
    .SYNOPSIS
        Loads and validates the AzHomeLab configuration data file.

    .DESCRIPTION
        Wraps Import-PowerShellDataFile to load config/lab.config.psd1 and
        performs a lightweight schema check so that missing/renamed keys
        fail fast with an actionable error instead of a confusing null
        reference deeper in a deployment phase.

    .PARAMETER Path
        Path to the .psd1 configuration file. Defaults to
        '../config/lab.config.psd1' relative to the module.

    .EXAMPLE
        $Config = Get-LabConfig -Path './config/lab.config.psd1'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (-not (Test-Path -Path $_)) {
                throw "Get-LabConfig: configuration file not found at path '$_'."
            }
            $true
        })]
        [string]$Path
    )

    try {
        $config = Import-PowerShellDataFile -Path $Path
    }
    catch {
        throw "Get-LabConfig: failed to parse configuration file '$Path'. Error: $($_.Exception.Message)"
    }

    $requiredTopLevelKeys = @(
        'Workload', 'Environment', 'Region', 'UniqueSuffix', 'SubscriptionId',
        'ResourceGroups', 'Tags', 'Network', 'Storage', 'KeyVault',
        'Monitoring', 'Compute', 'Governance', 'Budget', 'Deploy'
    )

    $missing = $requiredTopLevelKeys | Where-Object { -not $config.ContainsKey($_) }
    if ($missing) {
        throw "Get-LabConfig: configuration file '$Path' is missing required key(s): $($missing -join ', ')"
    }

    return $config
}
