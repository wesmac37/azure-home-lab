function New-LabBudgetAlert {
    <#
    .SYNOPSIS
        Idempotently creates a subscription-scoped consumption budget with email alerts.

    .DESCRIPTION
        Creates (or returns the existing) monthly consumption budget scoped
        to the current subscription, with notification thresholds (e.g. 80%
        and 100% of the budget amount) that email the supplied contact
        addresses. Budgets themselves are free to create; this is marked
        optional in documentation but shipped as fully working code since it
        costs nothing to have in place.

    .PARAMETER Name
        Budget name, e.g. 'budget-homelab-monthly'.

    .PARAMETER AmountUsd
        Monthly budget amount in USD, e.g. 5.

    .PARAMETER ThresholdPercents
        Array of percentages (of AmountUsd) at which to trigger a notification, e.g. 80, 100.

    .PARAMETER ContactEmails
        Array of email addresses to notify when a threshold is crossed.

    .PARAMETER StartDate
        Budget start date, format 'yyyy-MM-dd'. Must be the first of a month.

    .PARAMETER EndDate
        Budget end date, format 'yyyy-MM-dd'.

    .EXAMPLE
        New-LabBudgetAlert -Name 'budget-homelab-monthly' -AmountUsd 5 -ThresholdPercents 80,100 `
            -ContactEmails 'you@example.com' -StartDate '2026-07-01' -EndDate '2027-07-01'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 100000)]
        [double]$AmountUsd,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [int[]]$ThresholdPercents,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ContactEmails,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StartDate,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndDate
    )

    try {
        $existing = Get-AzConsumptionBudget -Name $Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Verbose "New-LabBudgetAlert: budget '$Name' already exists. Skipping creation."
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create monthly consumption budget of `$$AmountUsd USD")) {
            Write-Verbose "New-LabBudgetAlert: creating budget '$Name' for `$$AmountUsd/month with thresholds $($ThresholdPercents -join ', ')."

            $notifications = @{}
            foreach ($pct in $ThresholdPercents) {
                $key = "Actual_GreaterThan_$pct"
                $notifications[$key] = @{
                    Enabled        = $true
                    Operator       = 'GreaterThan'
                    Threshold      = $pct
                    ContactEmails  = $ContactEmails
                    ThresholdType  = 'Actual'
                }
            }

            return New-AzConsumptionBudget -Name $Name -Amount $AmountUsd -Category 'Cost' `
                -TimeGrain 'Monthly' -StartDate $StartDate -EndDate $EndDate -Notification $notifications -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabBudgetAlert: failed to create budget '$Name'. Error: $($_.Exception.Message)"
    }
}
