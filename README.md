# Azure Home Lab

![CI](https://img.shields.io/badge/CI-passing-brightgreen?style=flat-square&logo=github)
![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE?style=flat-square&logo=powershell)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

A modular, cost-aware Azure home lab, deployable entirely within the
constraints of an **Azure Free Account**, built and documented as a
portfolio project for a Senior IT Architect background (20+ years
infrastructure: VMware, Windows, Linux, Citrix; AZ-104 passed; AZ-305 in
progress).

Every resource, script, and function in this repo is real and runnable —
not pseudocode — via **Azure Cloud Shell (PowerShell mode)** and the **Az
PowerShell module**.

## Architecture overview

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

Full write-up, including why resources are split by lifecycle into three
resource groups: [docs/architecture.md](docs/architecture.md). Diagram
source: [diagrams/architecture.mmd](diagrams/architecture.mmd).

## Things you must edit before running

This repo ships with **clearly-marked example placeholders**. Replace these
in `config/lab.config.psd1` before deploying:

| Placeholder | Location | Replace with |
|---|---|---|
| `<your-subscription-id>` | `SubscriptionId` | Your Azure subscription ID (or leave as-is — scripts default to `(Get-AzContext).Subscription.Id`). |
| `<your-name-or-email>` | `Tags.Owner` | Your name or email address. |
| `<your-email@example.com>` | `Budget.ContactEmails` | The email address that should receive budget alerts. |
| `<placeholder-object-id-for-second-user>` | `Governance.SecondUserObjectId` | A real Entra ID object ID, only needed if you run the RBAC "second user" example. |
| `<placeholder-upn@yourtenant.onmicrosoft.com>` | `Governance.SecondUserUpn` | A real user principal name, only needed for the same RBAC example. |
| `lab01` (`UniqueSuffix`) | `UniqueSuffix` | Any short alphanumeric string — storage account and Key Vault names must be globally unique. |
| `Copyright (c) 2026 <Your Name>` | `LICENSE` | Your name. |

## Prerequisites

- An [Azure Free Account](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account) (or any subscription — the lab is cost-aware regardless).
- Azure Cloud Shell (PowerShell mode) — recommended, zero local setup — or a
  local install of PowerShell 7+ with the [Az PowerShell module](https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell).
- [Pester 5](https://pester.dev/) and [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) if you want to run tests/lint locally.
- Git.

## Deployment steps (Azure Cloud Shell)

```powershell
# 1. Clone the repo
git clone https://github.com/your-username/azure-home-lab.git
cd azure-home-lab

# 2. Confirm you have an active context (Cloud Shell already has one)
Get-AzContext

# 3. Import the module
Import-Module ./modules/AzHomeLab/AzHomeLab.psd1 -Force

# 4. Edit config/lab.config.psd1 — see "Things you must edit before running" above

# 5. Deploy phase by phase (each phase is idempotent and safe to re-run)
./scripts/deploy-lab.ps1 -Phase Foundation
./scripts/deploy-lab.ps1 -Phase Network
./scripts/deploy-lab.ps1 -Phase Security
./scripts/deploy-lab.ps1 -Phase Storage
./scripts/deploy-lab.ps1 -Phase Monitoring

# Optional — the one test VM, OFF by default to keep the first run cheapest:
./scripts/deploy-lab.ps1 -Phase Compute -SkipCompute:$false

# Or run everything in order at once:
./scripts/deploy-lab.ps1 -Phase All
```

Preview any phase without making changes:
```powershell
./scripts/deploy-lab.ps1 -Phase Network -WhatIf
```

## Validation steps

```powershell
./scripts/validate-lab.ps1
# Scope to a single phase's components:
./scripts/validate-lab.ps1 -Phase Storage
```

Prints a PASS/FAIL table and exits non-zero if any check fails — see
[docs/validation-checklist.md](docs/validation-checklist.md) for the full
list of automated and manual checks.

## Cleanup steps

```powershell
# Preview what would be removed
./scripts/cleanup-lab.ps1 -WhatIf

# Actually tear down (prompts for confirmation)
./scripts/cleanup-lab.ps1

# Unattended, and purge the Key Vault's soft-delete state too
./scripts/cleanup-lab.ps1 -Force -PurgeKeyVault
```

Removes resource locks first, then deletes everything in a safe dependency
order, and never throws if a resource is already gone.

## Cost notes

Deploying the default set of phases (with `-SkipCompute` in effect) costs
roughly **$0.00-$0.10/month** at lab scale. Full component-by-component
classification, monthly estimates, and Microsoft source citations:
[docs/cost-awareness.md](docs/cost-awareness.md). Check current spend any
time with:
```powershell
./scripts/Get-LabCostEstimate.ps1
```

## Troubleshooting

Common issues (Bastion Developer SKU unavailable in a region, storage/Key
Vault name collisions, stuck resource locks, RBAC placeholder errors, and
more) with fixes: [docs/troubleshooting.md](docs/troubleshooting.md).

## Security notes

- RDP (3389) and SSH (22) are **never** opened to the internet. Access is
  exclusively via Azure Bastion Developer SKU, or the documented zero-cost
  NSG fallback scoped to a single `/32` IP (removed automatically by
  cleanup).
- Key Vault runs in **RBAC authorization mode**, not legacy access policies.
- Storage account access uses **RBAC (Storage Blob Data Contributor)**
  instead of SAS tokens; secure transfer (HTTPS) is required and public blob
  access is disabled.
- No hard-coded subscription IDs or credentials anywhere in the code —
  scripts read `(Get-AzContext).Subscription.Id` or accept parameters.
- A `CanNotDelete` resource lock and a tag-requiring Azure Policy assignment
  demonstrate governance guardrails on the management resource group.

## Screenshots & diagram

See [docs/screenshots/README.md](docs/screenshots/README.md) for the
expected screenshot filenames and what each should capture (resource
groups, Bastion Developer tier, NSG rules, Key Vault RBAC mode, storage
secure transfer, Log Analytics data cap, policy assignment, resource lock,
budget, validate-lab output, and CI run). The architecture diagram source
is at [diagrams/architecture.mmd](diagrams/architecture.mmd).

## Interview talking points

A curated set of points mapping this project to common interview questions
about cost management, IaC practices, and cloud governance:
[docs/interview-talking-points.md](docs/interview-talking-points.md). A
literal spoken demo script is at [docs/demo-script.md](docs/demo-script.md).

## Skills demonstrated

- **Azure infrastructure-as-code** via idempotent Az PowerShell automation
  (not just portal clicks) — resource groups, VNets/subnets/NSGs, Bastion,
  storage, Key Vault, Log Analytics, VMs.
- **Cost engineering**: Bastion Developer SKU selection, explicit Log
  Analytics ingestion caps, opt-in compute with real auto-shutdown
  scheduling, consumption budgets with alerting.
- **Governance**: Azure Policy assignment, RBAC role assignment patterns,
  resource locks, and how they interact with automated cleanup.
- **Software engineering discipline applied to infrastructure**:
  comment-based help, parameter validation, `-WhatIf`/`-Confirm` support,
  try/catch with actionable errors, Pester v5 unit tests with full Az
  mocking, PSScriptAnalyzer linting, and CI via GitHub Actions.
- **Enterprise landing-zone thinking** at lab scale: lifecycle-based
  resource group separation, naming/tagging conventions enforced in code.
- **Documentation as a first-class deliverable**: architecture rationale,
  cost classification with citations, troubleshooting, validation
  checklists, and interview-ready talking points.

## Future enhancements

- Wire up live OIDC-authenticated deploy-from-CI (documented pattern in
  [docs/architecture.md](docs/architecture.md#oidc-federated-credentials-documented-pattern-not-wired-up),
  requires the reader's own tenant app registration).
- Extend the `state` storage container into a real Terraform or Packer
  remote-state backend.
- Add an optional Data Collection Rule + VM diagnostic extension for actual
  log ingestion (currently documented as an intentional stretch item to
  keep default cost near-zero).
- Add a second spoke VNet with peering to more fully simulate a hub-and-spoke
  topology once budget allows.
- Add Microsoft Defender for Cloud Free tier recommendations review as a
  validate-lab check.

## Repository structure

```
azure-home-lab/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── .gitignore
├── docs/
│   ├── architecture.md
│   ├── cost-awareness.md
│   ├── troubleshooting.md
│   ├── demo-script.md
│   ├── validation-checklist.md
│   ├── interview-talking-points.md
│   └── screenshots/README.md
├── diagrams/
│   └── architecture.mmd
├── config/
│   └── lab.config.psd1
├── modules/AzHomeLab/
│   ├── AzHomeLab.psd1
│   ├── AzHomeLab.psm1
│   ├── Public/*.ps1
│   └── Private/*.ps1
├── scripts/
│   ├── deploy-lab.ps1
│   ├── validate-lab.ps1
│   ├── cleanup-lab.ps1
│   └── Get-LabCostEstimate.ps1
├── tests/
│   ├── AzHomeLab.Module.Tests.ps1
│   ├── deploy-lab.Tests.ps1
│   └── validate-lab.Tests.ps1
└── .github/workflows/powershell-ci.yml
```

## License

[MIT](LICENSE) — see the LICENSE file for full text.
