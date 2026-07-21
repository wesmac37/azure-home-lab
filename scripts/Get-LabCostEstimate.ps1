<#
.SYNOPSIS
    Prints month-to-date spend for the current subscription and compares it to the AzHomeLab budget.

.DESCRIPTION
    Attempts to retrieve month-to-date consumption usage details via
    Get-AzConsumptionUsageDetail and sums the pretax cost, then compares the
    total to the $Config.Budget.AmountUsd threshold from
    config/lab.config.psd1. Many free-tier / Azure-for-Students-style tenants
    restrict access to the Consumption API, so this script wraps the call in
    try/catch: on failure it prints a clear instructional fallback pointing
    the user to the exact Cost Management + Billing portal navigation steps
    instead of failing silently.

.PARAMETER ConfigPath
    Path to the lab configuration .psd1 file. Defaults to '../config/lab.config.psd1'
    relative to this script's directory.

.EXAMPLE
    ./Get-LabCostEstimate.ps1

.EXAMPLE
    ./Get-LabCostEstimate.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1')
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}
catch {
    throw "Get-LabCostEstimate.ps1: failed to import the AzHomeLab module from '$modulePath'. Error: $($_.Exception.Message)"
}

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context -or -not $context.Subscription) {
    throw "Get-LabCostEstimate.ps1: no active Az PowerShell context was found. Run 'Connect-AzAccount' and re-run this script."
}

$Config = Get-LabConfig -Path $ConfigPath
$budgetAmount = $Config.Budget.AmountUsd

$today = Get-Date
$monthStart = Get-Date -Year $today.Year -Month $today.Month -Day 1 -Hour 0 -Minute 0 -Second 0

Write-Host ''
Write-Host '=== AzHomeLab month-to-date cost estimate ===' -ForegroundColor Cyan
Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
Write-Host "Period: $($monthStart.ToString('yyyy-MM-dd')) to $($today.ToString('yyyy-MM-dd'))"
Write-Host "Budget threshold (from config): `$$budgetAmount USD/month"
Write-Host ''

try {
    $usageDetails = Get-AzConsumptionUsageDetail -StartDate $monthStart -EndDate $today -ErrorAction Stop

    if (-not $usageDetails) {
        Write-Host 'No usage records returned for the current month (this is normal early in the billing cycle or for a brand-new subscription).' -ForegroundColor Yellow
        return
    }

    $totalCost = ($usageDetails | Measure-Object -Property PretaxCost -Sum).Sum
    $totalCost = [math]::Round([double]$totalCost, 2)
    $percentOfBudget = if ($budgetAmount -gt 0) { [math]::Round(($totalCost / $budgetAmount) * 100, 1) } else { 0 }

    Write-Host "Month-to-date spend: `$$totalCost USD" -ForegroundColor $(if ($totalCost -ge $budgetAmount) { 'Red' } elseif ($percentOfBudget -ge 80) { 'Yellow' } else { 'Green' })
    Write-Host "That is $percentOfBudget% of the `$$budgetAmount budget."

    Write-Host ''
    Write-Host 'Top cost contributors:' -ForegroundColor Cyan
    $usageDetails | Group-Object -Property InstanceName | Sort-Object { ($_.Group | Measure-Object -Property PretaxCost -Sum).Sum } -Descending |
        Select-Object -First 10 | ForEach-Object {
            $sum = [math]::Round((($_.Group | Measure-Object -Property PretaxCost -Sum).Sum), 4)
            Write-Host ("  {0,-50} `${1}" -f $_.Name, $sum)
        }
}
catch {
    Write-Warning "Get-LabCostEstimate.ps1: Get-AzConsumptionUsageDetail was not accessible in this tenant/subscription (common on free-tier or restricted tenants). Error: $($_.Exception.Message)"
    Write-Host ''
    Write-Host 'Use the Azure portal instead:' -ForegroundColor Cyan
    Write-Host '  1. Sign in to https://portal.azure.com'
    Write-Host '  2. Search for and open "Cost Management + Billing"'
    Write-Host '  3. Select "Cost Management" > "Cost analysis"'
    Write-Host '  4. Set Scope to your subscription'
    Write-Host '  5. Set the date range to "Month to date"'
    Write-Host "  6. Compare the total shown to your `$$budgetAmount/month budget"
    Write-Host '  7. Optionally open "Budgets" in the same left-hand menu to see alert history for budget-homelab-monthly'
}
