# Troubleshooting

Common issues you may hit while deploying, validating, or cleaning up
AzHomeLab, and how to resolve each one.

## "No active Az PowerShell context was found"

**Symptom:** `deploy-lab.ps1`, `validate-lab.ps1`, or `cleanup-lab.ps1`
throws an error mentioning `Connect-AzAccount`.

**Cause:** The scripts deliberately do **not** call `Connect-AzAccount` on
your behalf (so they behave predictably in Azure Cloud Shell, where a
context typically already exists).

**Fix:**
```powershell
Connect-AzAccount
# If you have multiple subscriptions, select the right one:
Get-AzSubscription
Set-AzContext -SubscriptionId '<your-subscription-id>'
```

## Azure Bastion Developer SKU deployment fails

**Symptom:** `New-LabBastion` throws an error referencing SKU/region
support during the Network phase.

**Cause:** Bastion Developer SKU is not available in every Azure region.

**Fix:** Use the documented zero-cost fallback — an NSG rule scoped to your
current public IP — described in [architecture.md](./architecture.md#bastion-developer-sku--the-cost-trick),
or redeploy with a different `Region` value in `config/lab.config.psd1`
where Developer SKU is supported.

## Storage account or Key Vault name already taken

**Symptom:** `New-LabStorageAccount` or `New-LabKeyVault` fails with a "name
not available" style error from Azure.

**Cause:** Storage account and Key Vault names are globally unique across
all of Azure. The default `UniqueSuffix` (`lab01`) in
`config/lab.config.psd1` may already be claimed by another subscription.

**Fix:** Edit `UniqueSuffix` in `config/lab.config.psd1` to a different
short alphanumeric string (4-6 characters) and re-run the Storage phase.

## Resource group deletion is stuck / "scope locked" error

**Symptom:** `cleanup-lab.ps1` (or a manual `Remove-AzResourceGroup`) fails
with a message about a lock preventing the operation.

**Cause:** `rg-homelab-mgmt-eastus` has a `CanNotDelete` resource lock
applied by the Security phase (`New-LabResourceLock`), by design, to
demonstrate governance protection.

**Fix:** `cleanup-lab.ps1` already calls `Remove-LabResourceLock` first —
if you're seeing this outside of the script, run:
```powershell
Import-Module ./modules/AzHomeLab/AzHomeLab.psd1
Remove-LabResourceLock -ResourceGroupName 'rg-homelab-mgmt-eastus'
```

## Key Vault soft-delete blocks name reuse

**Symptom:** Recreating a Key Vault with the same name fails with a
soft-deleted-vault conflict error.

**Cause:** Key Vault soft-delete is mandatory in current Azure; a deleted
vault's name stays reserved for the retention window (default 7 days in
this repo's config) unless purged.

**Fix:** Purge it explicitly (irreversible):
```powershell
./scripts/cleanup-lab.ps1 -Force -PurgeKeyVault
```
or manually:
```powershell
Remove-AzKeyVault -VaultName 'kv-homelab-dev-lab01' -Location 'eastus' -InRemovedState -Force
```

## `Get-AzConsumptionUsageDetail` throws or returns nothing

**Symptom:** `Get-LabCostEstimate.ps1` prints a warning instead of a cost
number.

**Cause:** Many free-tier/restricted tenants (including Azure for
Students-style tenants) block Consumption API access for the signed-in
principal.

**Fix:** This is expected and handled gracefully — the script prints exact
navigation steps for the Cost Management + Billing portal blade instead.
Follow those steps, or ask a subscription Owner/Billing Reader to check the
API-based path.

## RBAC role assignment fails with "principal not found"

**Symptom:** The Security phase's example `New-AzRoleAssignment` calls fail
referencing an object ID or UPN that doesn't resolve.

**Cause:** `Governance.SecondUserObjectId` and `Governance.SecondUserUpn` in
`config/lab.config.psd1` are **intentional placeholders** — they do not
correspond to a real principal in your tenant.

**Fix:** Replace them with a real object ID/UPN from your own tenant (e.g.
a second test user, or your own account for the demo), or leave the example
code commented out at the call site if you don't need a second user.

## PSScriptAnalyzer fails the CI build

**Symptom:** The GitHub Actions workflow fails on the "Run PSScriptAnalyzer"
step.

**Cause:** An Error-severity finding was introduced (Warning-severity
findings are reported but do not fail the build).

**Fix:** Run the same check locally before pushing:
```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error
```

## Pester tests fail locally but the module imports fine interactively

**Symptom:** `Invoke-Pester -Path ./tests` reports failures that don't
reproduce when you run functions manually.

**Cause:** Usually a stale mock or a previous `Import-Module` session
holding an old version of the module in memory.

**Fix:**
```powershell
Remove-Module AzHomeLab -ErrorAction SilentlyContinue
Import-Module ./modules/AzHomeLab/AzHomeLab.psd1 -Force
Invoke-Pester -Path ./tests -Output Detailed
```
