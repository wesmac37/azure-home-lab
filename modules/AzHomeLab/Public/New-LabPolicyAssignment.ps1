function New-LabPolicyAssignment {
    <#
    .SYNOPSIS
        Idempotently assigns the built-in "Require a tag on resources" policy to a resource group scope.

    .DESCRIPTION
        Assigns the built-in Azure Policy definition
        '871b6d14-10aa-478d-b590-94f262ecfa99' ("Require a tag on resources")
        at the supplied resource group scope, using New-AzPolicyAssignment.
        Checks for an existing assignment with the same name first so re-runs
        are safe. Supports -WhatIf/-Confirm since policy assignments affect
        governance behavior across the scope.

    .PARAMETER Name
        Policy assignment name, e.g. 'require-tag-homelab-mgmt'.

    .PARAMETER PolicyDefinitionId
        Full resource ID of the built-in (or custom) policy definition.

    .PARAMETER ScopeResourceGroupName
        Resource group name to scope the assignment to.

    .PARAMETER RequiredTagName
        The tag key the policy will require, e.g. 'Environment'.

    .EXAMPLE
        New-LabPolicyAssignment -Name 'require-tag-homelab-mgmt' `
            -PolicyDefinitionId '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99' `
            -ScopeResourceGroupName 'rg-homelab-mgmt-eastus' -RequiredTagName 'Environment'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyDefinitionId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScopeResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RequiredTagName
    )

    try {
        # Build the resource-group scope deterministically from the current subscription ID and
        # the resource group name, rather than depending on Get-AzResourceGroup returning a live
        # object. Under -WhatIf, a resource group created earlier in the same run (e.g. during the
        # Foundation phase) genuinely does not exist yet, so Get-AzResourceGroup would return $null
        # here - relying on '$rg.ResourceId' would then fail even though the scope path itself is
        # fully predictable from subscription ID + resource group name.
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context -or -not $context.Subscription -or -not $context.Subscription.Id) {
            throw 'No active Az context/subscription was found while building the policy assignment scope.'
        }
        $scope = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$ScopeResourceGroupName"

        $rg = Get-AzResourceGroup -Name $ScopeResourceGroupName -ErrorAction SilentlyContinue
        if (-not $rg) {
            Write-Verbose "New-LabPolicyAssignment: resource group '$ScopeResourceGroupName' was not found (it may be created earlier in this same run under -WhatIf). Proceeding with the computed scope '$scope'."
        }

        $existing = Get-AzPolicyAssignment -Name $Name -Scope $scope -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Verbose "New-LabPolicyAssignment: policy assignment '$Name' already exists at scope '$scope'. Skipping."
            return $existing
        }

        if ($PSCmdlet.ShouldProcess($Name, "Assign 'Require a tag on resources' policy at scope $scope")) {
            Write-Verbose "New-LabPolicyAssignment: creating policy assignment '$Name' requiring tag '$RequiredTagName'."
            $policyDefinition = Get-AzPolicyDefinition -Id $PolicyDefinitionId -ErrorAction Stop

            return New-AzPolicyAssignment -Name $Name -Scope $scope -PolicyDefinition $policyDefinition `
                -PolicyParameterObject @{ tagName = $RequiredTagName } -ErrorAction Stop
        }
    }
    catch {
        throw "New-LabPolicyAssignment: failed to create policy assignment '$Name'. Error: $($_.Exception.Message)"
    }
}
