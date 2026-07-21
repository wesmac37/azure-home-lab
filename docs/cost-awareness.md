# Cost Awareness

This document classifies every AzHomeLab component by cost category, gives a
realistic monthly estimate at lab scale, and links to the Microsoft source
that backs each claim. Read this before you deploy anything — the whole
point of AzHomeLab is to demonstrate enterprise patterns **without**
surprising you with a bill.

## Free-tier facts this repo relies on

- **Azure Free Account**: $200 USD credit usable within the first 30 days,
  plus a set of "always free" and "12-months-free" service quantities.
  ([Microsoft: Azure Free Account](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account))
- **Burstable VMs (B1s, B2pts v2, B2ats v2)**: 750 hours/month each, free
  for 12 months on eligible free-account subscriptions. Running **one** VM
  ~24/7 stays under 750 hrs in a 31-day month (730 hrs), but running more
  than one concurrently, or running past the 12-month window, incurs cost.
  ([Microsoft: free services](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-free-services))
- **Azure Bastion Developer SKU**: $0/hour, no hourly charge, free outbound
  data transfer, available in many (not all) regions.
  ([Bastion SKU comparison](https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison),
  [Bastion Developer announcement](https://azure.microsoft.com/en-us/blog/introducing-azure-bastion-developer-secure-and-cost-effective-access-to-your-azure-virtual-machines/))
- **Log Analytics Free pricing tier (legacy)**: 500 MB/day ingestion cap,
  7-day retention, evaluation-only. AzHomeLab sets an explicit `dailyQuotaGb`
  cap regardless of the tier chosen, to guarantee no runaway ingestion cost.
  ([Daily cap docs](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap))
- **Key Vault and Storage Account** are **not** part of the always-free or
  12-months-free lists. They are billed pay-as-you-go at very low
  per-operation/GB rates — fractions of a cent for lab-scale use — and are
  covered by the $200/30-day credit if you're still inside that window.

## Component classification table

| Component | Classification | Monthly Estimate | Notes |
|---|---|---|---|
| Resource groups (`rg-homelab-mgmt-eastus`, `rg-homelab-network-eastus`, `rg-homelab-compute-eastus`) | Free | $0.00 | Resource groups themselves have no cost. |
| Virtual network + subnets (`vnet-homelab-dev-eastus`) | Free | $0.00 | VNets, subnets, and NSGs have no direct hourly charge. |
| Network Security Groups (`nsg-mgmt-*`, `nsg-app-*`) | Free | $0.00 | NSG rule evaluation is included at no charge. |
| Azure Bastion (Developer SKU) | Free | $0.00 | $0/hour, no hourly charge, free outbound data transfer per [Bastion SKU comparison](https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison). Not available in every region — see fallback in [architecture.md](./architecture.md). |
| Test VM `vm-jump01-dev-eastus` (Standard_B1s), **skipped by default** | 12-months-free (if enabled) | $0.00 if run ~24/7 within 750 hrs/month for the first 12 months and only one B-series free-eligible VM is running; **Optional-may-cost-money** thereafter or if run concurrently with another eligible VM | 750 free hours/month per eligible size for 12 months ([source](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-free-services)). Nightly auto-shutdown schedule keeps actual usage far under the ceiling regardless. |
| Managed OS disk for test VM | Low-cost pay-as-you-go | ~$1-2/month (Standard_LRS, small size) | Not on the free list; rounds to low dollars for a small disk. |
| Storage account `sthomelab<suffix>` (Standard_LRS) | Low-cost pay-as-you-go | < $0.05/month at lab scale | Not part of always-free/12-months-free; [pay-as-you-go, fractions of a cent per GB/operation](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account) at this scale; covered by the $200/30-day credit if inside that window. |
| Key Vault `kv-homelab-dev-<suffix>` (RBAC mode, 1 demo secret) | Low-cost pay-as-you-go | < $0.03/month at lab scale | Not part of always-free/12-months-free; per-operation billing rounds to cents/month for light lab use. |
| Log Analytics workspace `law-homelab-dev-eastus` (dailyQuotaGb=1) | Uses $200 credit / Low-cost pay-as-you-go | $0.00-$2.50/month | Explicit 1 GB/day cap ([daily cap docs](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap)) bounds worst case; with no VM agent/DCR attached (default), ingestion is near-zero. |
| VM diagnostic extension / Data Collection Rule | Optional-may-cost-money | $0.00 by default (not deployed) | Explicitly left out of the default deploy; documented as an optional stretch item. |
| Azure Policy assignment ("Require a tag on resources") | Free | $0.00 | Policy evaluation has no charge. |
| Resource lock (CanNotDelete) | Free | $0.00 | Locks have no charge. |
| Consumption budget + alert (`budget-homelab-monthly`) | Free | $0.00 | Budgets and their email notifications are free to create. |
| VPN Gateway / ExpressRoute / Internal Load Balancer / App Gateway | Optional-may-cost-money | Not deployed by default; ILB/App Gateway can run ~$140+/month if added | Explicitly out of scope for this repo; called out here only so you don't accidentally add one. |

## How to verify/adjust the Log Analytics daily cap

```powershell
# Check the current cap
Get-AzOperationalInsightsWorkspace -ResourceGroupName 'rg-homelab-mgmt-eastus' -Name 'law-homelab-dev-eastus' |
    Select-Object Name, Sku

# Adjust the cap (example: raise to 2 GB/day)
Update-AzOperationalInsightsWorkspace -ResourceGroupName 'rg-homelab-mgmt-eastus' -Name 'law-homelab-dev-eastus' -DailyQuotaGb 2
```

You can also view/adjust the cap in the portal: **Log Analytics workspace >
Usage and estimated costs > Data Cap**.

## Bottom line

Deploying **Foundation + Network + Security + Storage + Monitoring** (the
default, with `-SkipCompute` in effect) costs **$0.00-$0.10/month** at lab
scale, comfortably inside the always-free tier plus a few cents of
pay-as-you-go storage/Key Vault usage. Adding the optional test VM with
nightly auto-shutdown keeps you inside the 12-months-free 750-hour ceiling
as long as you don't run a second eligible B-series VM at the same time.
