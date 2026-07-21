# Screenshots

This folder is where portfolio screenshots go. They are not included in the
repo (screenshots are environment-specific and would need to be recaptured
after every deploy), but the expected filenames are documented here so the
folder is ready to receive them and so README.md / demo materials have
stable links to point at.

Capture screenshots after a successful `deploy-lab.ps1` run, in this order,
using these exact filenames:

| Filename | What to capture |
|---|---|
| `01-resource-groups.png` | Azure portal, Resource groups blade, filtered to `rg-homelab-*`, showing all three resource groups and their tags column. |
| `02-network-topology.png` | Azure portal, the `vnet-homelab-dev-eastus` resource, Diagram/Topology view showing all three subnets. |
| `03-bastion-developer-sku.png` | Azure portal, the Bastion resource's Overview blade, with the **Tier: Developer** field visible. |
| `04-nsg-rules.png` | Azure portal, `nsg-mgmt-homelab-dev-eastus` Inbound security rules blade, showing the deny-by-default and Bastion-subnet-only rules. |
| `05-keyvault-rbac.png` | Azure portal, Key Vault Access control (IAM) blade showing "Role-based access control" selected under Access configuration. |
| `06-storage-secure-transfer.png` | Azure portal, storage account Configuration blade showing "Secure transfer required: Enabled" and "Allow Blob public access: Disabled". |
| `07-log-analytics-daily-cap.png` | Azure portal, Log Analytics workspace, Usage and estimated costs > Data Cap blade showing the configured `dailyQuotaGb`. |
| `08-policy-assignment.png` | Azure portal, Policy > Assignments blade showing `require-tag-homelab-mgmt` scoped to `rg-homelab-mgmt-eastus`. |
| `09-resource-lock.png` | Azure portal, `rg-homelab-mgmt-eastus` > Locks blade showing the `CanNotDelete` lock. |
| `10-budget-alert.png` | Azure portal, Cost Management + Billing > Budgets blade showing `budget-homelab-monthly` with its 80%/100% thresholds. |
| `11-vm-auto-shutdown.png` | Azure portal (only if compute was deployed), VM > Auto-shutdown blade showing the configured nightly time and time zone. |
| `12-validate-lab-output.png` | Terminal output of `./scripts/validate-lab.ps1` showing the PASS/FAIL table with all checks passing. |
| `13-github-actions-ci.png` | GitHub Actions run summary showing the PSScriptAnalyzer + Pester workflow passing on a push/PR. |

## Guidance

- Redact your subscription ID and any personal email addresses before
  publishing screenshots publicly.
- PNG format, reasonable resolution (1600px wide or so) is sufficient —
  these are for a portfolio README, not print.
- Update `README.md`'s screenshot section links if you rename or reorder
  any of the above.
