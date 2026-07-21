function New-LabTag {
    <#
    .SYNOPSIS
        Builds the standard AzHomeLab tag hashtable, merging in any overrides.

    .DESCRIPTION
        Returns a hashtable containing the seven required AzHomeLab tags
        (Environment, Project, Owner, CostCenter, AutoShutdown, CreatedBy,
        DeployPhase). Accepts a base tag hashtable (typically loaded from
        config/lab.config.psd1) and an optional -Override hashtable whose
        keys take precedence, allowing callers to set a per-resource
        DeployPhase or AutoShutdown value without mutating the shared config.

    .PARAMETER BaseTags
        The baseline tag hashtable, usually $Config.Tags from lab.config.psd1.

    .PARAMETER Override
        Optional hashtable of tag keys/values that override BaseTags.

    .EXAMPLE
        New-LabTag -BaseTags $Config.Tags -Override @{ DeployPhase = 'Network' }

    .EXAMPLE
        New-LabTag -BaseTags $Config.Tags -Override @{ AutoShutdown = 'true'; DeployPhase = 'Compute' }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$BaseTags,

        [Parameter(Mandatory = $false)]
        [hashtable]$Override = @{}
    )

    $requiredKeys = @('Environment', 'Project', 'Owner', 'CostCenter', 'AutoShutdown', 'CreatedBy', 'DeployPhase')

    $merged = @{}
    foreach ($key in $BaseTags.Keys) {
        $merged[$key] = $BaseTags[$key]
    }
    foreach ($key in $Override.Keys) {
        $merged[$key] = $Override[$key]
    }

    $missing = $requiredKeys | Where-Object { -not $merged.ContainsKey($_) }
    if ($missing) {
        throw "New-LabTag: merged tag set is missing required key(s): $($missing -join ', ')"
    }

    return $merged
}
