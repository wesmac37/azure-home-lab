<#
.SYNOPSIS
    Validates a deployed AzHomeLab environment and prints a PASS/FAIL report.

.DESCRIPTION
    Re-checks every deployed AzHomeLab component's existence and key
    settings — required tags, NSG rules, storage secure-transfer
    enforcement, Key Vault RBAC authorization mode, Bastion Developer SKU,
    and budget existence — using the Test-LabDeployment function from the
    AzHomeLab module. Prints a formatted PASS/FAIL table and exits with a
    non-zero exit code if any check fails, making it suitable for CI-style
    usage (e.g. a post-deploy gate in a pipeline).

.PARAMETER ConfigPath
    Path to the lab configuration .psd1 file. Defaults to '../config/lab.config.psd1'
    relative to this script's directory.

.PARAMETER Phase
    Scope validation to a subset of components, matching the same phase
    names used by deploy-lab.ps1. One of 'All','Foundation','Network','Security','Storage','Monitoring','Compute'.
    Defaults to 'All'.

.EXAMPLE
    ./validate-lab.ps1

.EXAMPLE
    ./validate-lab.ps1 -Phase Network -Verbose
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.config.psd1'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Foundation', 'Network', 'Security', 'Storage', 'Monitoring', 'Compute')]
    [string]$Phase = 'All'
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../modules/AzHomeLab/AzHomeLab.psd1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}
catch {
    throw "validate-lab.ps1: failed to import the AzHomeLab module from '$modulePath'. Error: $($_.Exception.Message)"
}

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context -or -not $context.Subscription) {
    throw "validate-lab.ps1: no active Az PowerShell context was found. Run 'Connect-AzAccount' and re-run this script."
}

$Config = Get-LabConfig -Path $ConfigPath
$runAll = ($Phase -eq 'All')

$checks = New-Object System.Collections.Generic.List[PSCustomObject]

if ($runAll -or $Phase -eq 'Foundation') {
    foreach ($rgKey in @('Mgmt', 'Network', 'Compute')) {
        $rgName = $Config.ResourceGroups[$rgKey]
        $checks.Add((Test-LabDeployment -CheckName 'ResourceGroupExists' -ResourceGroupName $rgName))
    }
    $checks.Add((Test-LabDeployment -CheckName 'TagsPresent' -ResourceGroupName $Config.ResourceGroups.Mgmt -ExpectedTags $Config.Tags))
}

if ($runAll -or $Phase -eq 'Network') {
    $checks.Add((Test-LabDeployment -CheckName 'NsgRulesPresent' -ResourceGroupName $Config.ResourceGroups.Network -ResourceName $Config.Network.NsgMgmtName))
    $checks.Add((Test-LabDeployment -CheckName 'NsgRulesPresent' -ResourceGroupName $Config.ResourceGroups.Network -ResourceName $Config.Network.NsgAppName))
    $checks.Add((Test-LabDeployment -CheckName 'BastionSku' -ResourceGroupName $Config.ResourceGroups.Network -ResourceName $Config.Network.BastionName))
}

if ($runAll -or $Phase -eq 'Security') {
    $checks.Add((Test-LabDeployment -CheckName 'BudgetExists' -ResourceName $Config.Budget.Name))
}

if ($runAll -or $Phase -eq 'Storage') {
    $storageAccountName = Get-LabResourceName -Style Compressed -ResourceType $Config.Storage.AccountNamePrefix `
        -Workload '' -Environment '' -UniqueSuffix $Config.UniqueSuffix
    $keyVaultName = Get-LabResourceName -Style KeyVault -ResourceType 'kv' -Workload $Config.Workload `
        -Environment $Config.Environment -UniqueSuffix $Config.UniqueSuffix

    $checks.Add((Test-LabDeployment -CheckName 'StorageSecureTransfer' -ResourceGroupName $Config.ResourceGroups.Mgmt -ResourceName $storageAccountName))
    $checks.Add((Test-LabDeployment -CheckName 'KeyVaultRbacMode' -ResourceGroupName $Config.ResourceGroups.Mgmt -ResourceName $keyVaultName))
}

if ($runAll -or $Phase -eq 'Monitoring') {
    $checks.Add((Test-LabDeployment -CheckName 'LogAnalyticsDailyCap' -ResourceGroupName $Config.ResourceGroups.Mgmt `
        -ResourceName $Config.Monitoring.WorkspaceName -ExpectedDailyQuotaGb $Config.Monitoring.DailyQuotaGb))
}

Write-Host ''
Write-Host '=== AzHomeLab validation report ===' -ForegroundColor Cyan
$checks | Format-Table -AutoSize -Property Check, Status, Detail | Out-String | Write-Host

$failedChecks = $checks | Where-Object { $_.Status -eq 'FAIL' }
$passCount = ($checks | Where-Object { $_.Status -eq 'PASS' }).Count
$totalCount = $checks.Count

Write-Host "Result: $passCount / $totalCount checks passed." -ForegroundColor $(if ($failedChecks) { 'Red' } else { 'Green' })

if ($failedChecks) {
    Write-Warning "$($failedChecks.Count) check(s) failed. See table above for details."
    exit 1
}
else {
    exit 0
}
