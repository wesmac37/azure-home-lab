# Architecture

## Overview

AzHomeLab is a modular, cost-aware Azure home lab designed to run entirely
within the constraints of an [Azure Free Account](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account).
It deliberately mirrors enterprise landing-zone patterns — lifecycle-based
resource group separation, hub-and-spoke-inspired networking, governance
guardrails (policy, RBAC, locks, budgets), and CI-validated infrastructure
code — at a scale and cost appropriate for a personal lab.

```mermaid
graph TB
    subgraph SUB["Azure Subscription - Free Account"]
        subgraph RGMGMT["rg-homelab-mgmt-eastus"]
            KV["Key Vault<br/>kv-homelab-dev-&lt;suffix&gt;<br/>RBAC mode"]
            ST["Storage Account<br/>st homelab&lt;suffix&gt;<br/>scripts / logs / state"]
            LAW["Log Analytics<br/>law-homelab-dev-eastus<br/>dailyQuotaGb=1"]
            POLICY["Policy Assignment<br/>Require a tag on resources"]
            LOCK["Resource Lock<br/>CanNotDelete"]
            BUDGET["Consumption Budget<br/>$5/month, 80%/100% alerts"]
        end

        subgraph RGNET["rg-homelab-network-eastus"]
            VNET["VNet vnet-homelab-dev-eastus<br/>10.20.0.0/16"]
            SNETMGMT["snet-mgmt<br/>10.20.0.0/24"]
            SNETBASTION["AzureBastionSubnet<br/>10.20.1.0/26"]
            SNETAPP["snet-app<br/>10.20.2.0/24"]
            NSGMGMT["NSG nsg-mgmt-homelab-dev-eastus"]
            NSGAPP["NSG nsg-app-homelab-dev-eastus"]
            BASTION["Azure Bastion<br/>Developer SKU - $0/hour"]

            VNET --> SNETMGMT
            VNET --> SNETBASTION
            VNET --> SNETAPP
            SNETMGMT -.protected by.-> NSGMGMT
            SNETAPP -.protected by.-> NSGAPP
            SNETBASTION --> BASTION
        end

        subgraph RGCOMPUTE["rg-homelab-compute-eastus (optional, -SkipCompute)"]
            VM["VM vm-jump01-dev-eastus<br/>Standard_B1s, no public IP<br/>AutoShutdown=true (nightly)"]
        end

        USER["Administrator<br/>Cloud Shell / Az PowerShell"]

        USER -->|Connect-AzAccount| SUB
        BASTION -->|RDP/SSH session, no public IP exposure| VM
        VM -.->|attached to| SNETAPP
        VM -.->|Storage Blob Data Contributor RBAC| ST
        VM -.->|reads secret| KV
    end
```

The source of this diagram lives at [`diagrams/architecture.mmd`](../diagrams/architecture.mmd).

## Resource group strategy: why split by lifecycle

AzHomeLab uses three resource groups instead of one:

- **`rg-homelab-mgmt-eastus`** — Key Vault, storage account, Log Analytics
  workspace, policy assignment, resource lock, budget.
- **`rg-homelab-network-eastus`** — VNet, subnets, NSGs, Bastion Developer.
- **`rg-homelab-compute-eastus`** — the one optional test VM.

This mirrors how enterprise **landing zones** are organized: platform
resources (identity, connectivity, management) live in resource groups with
a different lifecycle than workload resources. A few concrete benefits this
repo demonstrates:

1. **Independent teardown.** You can delete `rg-homelab-compute-eastus`
   (the VM) without touching networking or governance resources — exactly
   how you'd tear down a short-lived workload without disturbing the
   platform underneath it.
2. **Different blast radius per group.** The management resource group
   holds a `CanNotDelete` lock in this repo, because accidentally deleting
   Key Vault/Log Analytics is far more painful than accidentally deleting a
   disposable test VM.
3. **Clearer RBAC boundaries.** In a real landing zone, platform teams often
   have different access than workload teams. Splitting resource groups by
   lifecycle makes it possible to scope `New-AzRoleAssignment` calls
   precisely (see the RBAC examples in this repo's Security phase).
4. **Cost attribution.** Cost Management + Billing can filter/group by
   resource group, so splitting by lifecycle also gives you a natural cost
   boundary between "always-on platform" and "sometimes-on workload."

## Network layout

A single VNet, `vnet-homelab-dev-eastus` (`10.20.0.0/16`), acts as a
lightweight hub, with two functional subnets simulating hub/spoke
separation without the cost of multiple VNets or peering:

- **`snet-mgmt`** (`10.20.0.0/24`) — management/jump resources.
- **`AzureBastionSubnet`** (`10.20.1.0/26`) — the exact, required subnet
  name Azure Bastion mandates; must be `/26` or larger.
- **`snet-app`** (`10.20.2.0/24`) — workload/test VM subnet.

Two NSGs — `nsg-mgmt-homelab-dev-eastus` and `nsg-app-homelab-dev-eastus` —
apply deny-by-default, allow-only-what's-needed rules. **RDP/SSH are never
opened to the internet.** Inbound management traffic is only allowed from
the `AzureBastionSubnet` CIDR, so access flows exclusively through Azure
Bastion.

No VPN Gateway, no ExpressRoute, and no Internal Load Balancer / Application
Gateway are deployed — these are called out in [cost-awareness.md](./cost-awareness.md)
as **"Optional / stretch — may cost money"** (an ILB/App Gateway alone can
run $140+/month) and are intentionally out of scope for a free-tier lab.

## Bastion Developer SKU — the cost trick

Azure Bastion **Developer SKU** costs **$0/hour** with free outbound data
transfer — a dramatic improvement over Basic/Standard Bastion, which run
$130-$200+/month. AzHomeLab deploys Developer SKU by default via
`New-LabBastion`.
([Bastion SKU comparison](https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison),
[Bastion Developer announcement](https://azure.microsoft.com/en-us/blog/introducing-azure-bastion-developer-secure-and-cost-effective-access-to-your-azure-virtual-machines/))

Developer SKU isn't available in every region yet. If deployment fails for
that reason, `New-LabBastion` surfaces an error pointing at the **zero-cost
NSG fallback**: lock the management NSG's RDP/SSH rule to your current
public IP only.

```powershell
# Get your current public IP from Cloud Shell
$myIp = Invoke-RestMethod -Uri 'https://api.ipify.org'

# Recreate the app/mgmt NSG with the fallback rule scoped to that IP
Import-Module ./modules/AzHomeLab/AzHomeLab.psd1
New-LabNetworkSecurityGroup -Name 'nsg-mgmt-homelab-dev-eastus' -ResourceGroupName 'rg-homelab-network-eastus' `
    -Location 'eastus' -Tags $tags -AllowedManagementIp $myIp
```

`cleanup-lab.ps1` removes this fallback rule along with everything else
during teardown, so the exposure window is bounded to your active lab
session.

## Compute

The single optional test VM, `vm-jump01-dev-eastus`, is deployed only when
`-SkipCompute:$false` is passed to `deploy-lab.ps1` (the default keeps
compute OFF so a first run stays cheapest). It runs `Standard_B1s`
(free-eligible for 12 months at 750 hrs/month), has **no public IP**, and
gets an actual nightly auto-shutdown schedule applied via
`Invoke-AzRestMethod` against the `Microsoft.DevTestLab/schedules` resource
type (there is no native `Az` cmdlet for the classic VM auto-shutdown
feature). This guarantees the VM powers off every night and never idles
24/7, keeping it comfortably under the free-tier hour ceiling.

## Storage

`sthomelab<uniqueSuffix>` (Standard_LRS) enforces secure transfer (HTTPS
only), disables public blob access, and uses **RBAC-based access** (Storage
Blob Data Contributor granted to the deploying user's own principal)
instead of SAS tokens — the recommended enterprise pattern for
credential-free, auditable access. Three containers are provisioned:
`scripts`, `logs`, and `state` (the last reserved for a future
Terraform/Packer extension).

## Monitor / Log Analytics

`law-homelab-dev-eastus` is created with an **explicit `dailyQuotaGb` cap**
(default 1 GB/day) regardless of which pricing tier is selected, so
ingestion cost is bounded no matter what. VM diagnostic extensions and Data
Collection Rules are intentionally **not** part of the default deploy —
they're documented as an optional stretch item that may add small cost,
while the bare workspace with a low cap is near-zero cost for light lab
activity. See [cost-awareness.md](./cost-awareness.md) for the full
breakdown and cap-adjustment commands.

## Governance

- **Azure Policy**: the built-in "Require a tag on resources" definition
  (`/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99`)
  is assigned at the `rg-homelab-mgmt-eastus` scope via `New-LabPolicyAssignment`.
- **RBAC**: example `New-AzRoleAssignment` calls grant a second (fictitious)
  user `Reader` at resource-group scope and `Storage Blob Data Contributor`
  at storage-account scope. The object IDs/UPNs used are clearly-marked
  placeholders — see the README's "Things you must edit before running."
- **Resource locks**: a `CanNotDelete` lock is applied to
  `rg-homelab-mgmt-eastus` via `New-LabResourceLock` to demonstrate
  accidental-deletion protection. `cleanup-lab.ps1` detects and removes all
  locks (via `Remove-LabResourceLock`) before attempting resource group
  deletion, so teardown never gets stuck.
- **Budget/alert**: `New-LabBudgetAlert` creates a subscription-scoped
  `$5/month` consumption budget with email notifications at 80% and 100%
  thresholds. Budgets are free to create, so this ships as fully working
  code rather than being left as a stretch item.

## GitHub integration pattern

This repo pairs with **GitHub Actions** (`.github/workflows/powershell-ci.yml`)
to run `PSScriptAnalyzer` and `Pester` on every push and pull request against
`main`. The workflow:

1. Checks out the repo on `ubuntu-latest`.
2. Installs/verifies `PSScriptAnalyzer` and `Pester` via
   `Install-Module -Force -Scope CurrentUser`.
3. Runs `Invoke-ScriptAnalyzer -Recurse -Path . -Severity Warning,Error`,
   failing the build if any **Error**-severity finding is present.
4. Runs `Invoke-Pester -Path ./tests -CI`, producing NUnit XML test results.
5. Uploads the test results as a workflow artifact.

### OIDC federated credentials (documented pattern, not wired up)

The enterprise-correct way to let GitHub Actions **deploy** to Azure is
OIDC federated credentials — no long-lived secrets stored in GitHub. The
pattern (text only, no live secrets in this repo):

1. Register an app in Microsoft Entra ID (`az ad app create` or portal).
2. Add a **federated credential** on that app scoped to your GitHub repo +
   branch (e.g. `repo:your-org/azure-home-lab:ref:refs/heads/main`).
3. Grant the app's service principal an RBAC role (e.g. `Contributor`) on
   the target subscription or resource group.
4. In the workflow, use `azure/login@v2` with `client-id`, `tenant-id`, and
   `subscription-id` inputs (no `client-secret`) — the action exchanges
   GitHub's OIDC token for an Azure access token at runtime.
5. Subsequent steps in the same job can run `Az` PowerShell or `az` CLI
   commands authenticated as that service principal.

**Live deploy-from-CI is intentionally left as an OPTIONAL/stretch
exercise** in this repo, since step 1-3 require the reader's own tenant and
app registration — something a portfolio repo can document but shouldn't
assume.
