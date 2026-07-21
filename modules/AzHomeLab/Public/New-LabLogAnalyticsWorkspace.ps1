function New-LabLogAnalyticsWorkspace {
    <#
    .SYNOPSIS
        Idempotently creates the AzHomeLab Log Analytics workspace with an explicit daily ingestion cap.

    .DESCRIPTION
        Creates (or returns the existing) Log Analytics workspace and sets an
        explicit dailyQuotaGb cap regardless of the pricing tier chosen, to
        guarantee no runaway ingestion cost surprise. VM diagnostic
        extensions / Data Collection Rules are intentionally NOT configured
        here — agent-based log collection is documented as an optional
        stretch item that may add small cost; the bare workspace with a low
        cap is near-zero cost for a lab with light activity.
        Reference: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap

    .PARAMETER Name
        Workspace name, e.g. 'law-homelab-dev-eastus'.

    .PARAMETER ResourceGroupName
        Resource group the workspace belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER SkuName
        Log Analytics pricing tier. Defaults to 'PerGB2018' (dailyQuotaGb still applies).

    .PARAMETER DailyQuotaGb
        Explicit daily ingestion cap in GB. Defaults to 1.

    .PARAMETER RetentionInDays
        Data retention window in days.

    .PARAMETER Tags
        Tag hashtable to apply.

    .EXAMPLE
        New-LabLogAnalyticsWorkspace -Name 'law-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-mgmt-eastus' `
            -Location 'eastus' -DailyQuotaGb 1 -RetentionInDays 30 -Tags $tags
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

        [Parameter(Mandatory = $false)]
        [string]$SkuName = 'PerGB2018',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$DailyQuotaGb = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(7, 730)]
        [int]$RetentionInDays = 30,

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags
    )

    try {
        $workspace = Get-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if (-not $workspace) {
            if ($PSCmdlet.ShouldProcess($Name, "Create Log Analytics workspace in '$Location'")) {
                Write-Verbose "New-LabLogAnalyticsWorkspace: creating workspace '$Name'."
                $workspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $Name -Location $Location `
                    -Sku $SkuName -RetentionInDays $RetentionInDays -Tag $Tags -ErrorAction Stop
            }
        }
        else {
            Write-Verbose "New-LabLogAnalyticsWorkspace: workspace '$Name' already exists. Skipping creation."
        }

        if ($workspace -and $PSCmdlet.ShouldProcess($Name, "Set daily ingestion cap to $DailyQuotaGb GB")) {
            Write-Verbose "New-LabLogAnalyticsWorkspace: setting dailyQuotaGb=$DailyQuotaGb on '$Name'."
            Update-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $Name `
                -DailyQuotaGb $DailyQuotaGb -ErrorAction Stop | Out-Null
        }

        return Get-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    }
    catch {
        throw "New-LabLogAnalyticsWorkspace: failed to create or configure workspace '$Name'. Error: $($_.Exception.Message)"
    }
}
