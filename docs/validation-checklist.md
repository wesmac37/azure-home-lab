# Validation Checklist

Use this checklist after running `scripts/deploy-lab.ps1`, either manually
or by running `scripts/validate-lab.ps1` (recommended — it automates every
row below and returns a non-zero exit code on failure).

## Automated checks (via `validate-lab.ps1`)

| # | Check | What it verifies | Function |
|---|---|---|---|
| 1 | Resource groups exist | `rg-homelab-mgmt-eastus`, `rg-homelab-network-eastus`, `rg-homelab-compute-eastus` are present | `Test-LabDeployment -CheckName ResourceGroupExists` |
| 2 | Required tags present | `Environment`, `Project`, `Owner`, `CostCenter`, `AutoShutdown`, `CreatedBy`, `DeployPhase` all present on the mgmt RG | `Test-LabDeployment -CheckName TagsPresent` |
| 3 | NSG rules present | `nsg-mgmt-homelab-dev-eastus` and `nsg-app-homelab-dev-eastus` each have explicit security rules | `Test-LabDeployment -CheckName NsgRulesPresent` |
| 4 | Bastion SKU is Developer | Confirms the $0/hour SKU is what's actually deployed, not Basic/Standard | `Test-LabDeployment -CheckName BastionSku` |
| 5 | Storage secure transfer enforced | `EnableHttpsTrafficOnly` is `$true` on the storage account | `Test-LabDeployment -CheckName StorageSecureTransfer` |
| 6 | Key Vault RBAC mode | `EnableRbacAuthorization` is `$true` (not legacy access policies) | `Test-LabDeployment -CheckName KeyVaultRbacMode` |
| 7 | Log Analytics workspace exists with cap | Workspace present, `dailyQuotaGb` set as configured | `Test-LabDeployment -CheckName LogAnalyticsDailyCap` |
| 8 | Budget exists (optional) | `budget-homelab-monthly` consumption budget is present | `Test-LabDeployment -CheckName BudgetExists` |

Run it:
```powershell
./scripts/validate-lab.ps1
# Scope to one phase:
./scripts/validate-lab.ps1 -Phase Network
```

## Manual spot-checks (recommended before an interview/demo)

- [ ] `Get-AzResourceGroup | Where-Object Tags.Project -eq 'AzureHomeLab'`
      returns exactly the three expected resource groups.
- [ ] Portal: **Key Vault > Access control (IAM)** shows RBAC authorization
      mode, and **Secrets** shows one secret named `DemoConnectionString`.
- [ ] Portal: **Bastion resource > Overview** shows Tier = *Developer*.
- [ ] Portal: **Network Security Group > Inbound security rules** shows no
      rule allowing RDP (3389) or SSH (22) from `Internet` / `Any`.
- [ ] Portal: **Storage account > Configuration** shows *Secure transfer
      required* = Enabled and *Allow Blob public access* = Disabled.
- [ ] Portal: **Log Analytics workspace > Usage and estimated costs > Data
      Cap** shows the configured `dailyQuotaGb`.
- [ ] Portal: **Resource group (mgmt) > Locks** shows one `CanNotDelete`
      lock.
- [ ] Portal: **Cost Management + Billing > Budgets** shows
      `budget-homelab-monthly` if the Security phase's budget step succeeded.
- [ ] If compute was deployed: **VM > Overview > Auto-shutdown** shows a
      configured nightly time and the correct time zone, and **Networking**
      shows no public IP attached.

## After `cleanup-lab.ps1`

- [ ] `Get-AzResourceGroup -Name 'rg-homelab-mgmt-eastus'` (and the other two)
      returns nothing (or a `ResourceGroupNotFound` error, which is expected).
- [ ] `Get-AzResourceLock -ResourceGroupName 'rg-homelab-mgmt-eastus'`
      returns nothing (locks were removed before deletion).
- [ ] Cost Management + Billing shows no new charges accruing for AzHomeLab
      resources going forward.
