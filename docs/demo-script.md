# Demo Script

A literal, spoken-word walkthrough (5-7 minutes) you can read aloud in an
interview or live demo. Stage directions are in *italics*; everything else
is meant to be said close to verbatim.

---

**[0:00-0:45] Opening / framing**

"Let me show you an Azure home lab I built to practice enterprise
governance patterns on a free-tier budget. I've been doing infrastructure
for over twenty years — VMware, Windows, Linux, Citrix — and I passed
AZ-104 and I'm working toward AZ-305 now. I wanted a project that proves I
can do modern, cloud-native infrastructure-as-code the *right* way: modular,
idempotent, safe-by-default, and cost-conscious, not just 'click around in
the portal.' Everything you're about to see runs inside the constraints of
a standard Azure Free Account — $200 of credit for the first 30 days, plus
a set of always-free and 12-months-free service allowances."

**[0:45-1:45] Architecture**

*Share diagrams/architecture.mmd rendered, or open docs/architecture.md.*

"The architecture is a lightweight hub-and-spoke. One VNet,
`vnet-homelab-dev-eastus`, on `10.20.0.0/16`, with three subnets: a
management subnet, the required `AzureBastionSubnet`, and an application
subnet for a test VM. I split resources across three resource groups by
*lifecycle* rather than putting everything in one — management resources
like Key Vault and Log Analytics live in `rg-homelab-mgmt-eastus`,
networking lives in `rg-homelab-network-eastus`, and the optional compute
lives in `rg-homelab-compute-eastus`. That's the same pattern you'd see in
an enterprise landing zone — it lets you tear down a workload without
touching the platform underneath it."

**[1:45-3:00] Phased deploy**

*Open a terminal, show `scripts/deploy-lab.ps1`.*

"Deployment is broken into phases — Foundation, Network, Security, Storage,
Monitoring, and an optional Compute phase — because that maps to how you'd
actually roll this out in stages, and it makes failures easy to isolate. I
run it from Azure Cloud Shell, so there's zero local setup:

```powershell
git clone https://github.com/your-username/azure-home-lab.git
cd azure-home-lab
Import-Module ./modules/AzHomeLab/AzHomeLab.psd1
./scripts/deploy-lab.ps1 -Phase Foundation
./scripts/deploy-lab.ps1 -Phase Network
./scripts/deploy-lab.ps1 -Phase Security
./scripts/deploy-lab.ps1 -Phase Storage
./scripts/deploy-lab.ps1 -Phase Monitoring
```

Notice compute is skipped by default — I made that an explicit design
choice, because the first thing anyone should optimize for in a free-tier
lab is *not accidentally spending money*. Every 'New-' function in the
module checks whether the resource already exists before creating it, so
re-running any phase is completely safe — that's the idempotent Get-then-New
pattern you'd want in any real automation."

**[3:00-4:15] Governance — policy, RBAC, locks**

*Open docs/architecture.md at the Governance section, or run
`Get-AzPolicyAssignment` / `Get-AzResourceLock` live.*

"The Security phase is where I demonstrate governance, which is honestly
the part hiring managers care about most. I assign the built-in 'Require a
tag on resources' policy at the management resource group scope — so
nothing lands there without an `Environment` tag. I apply a `CanNotDelete`
lock to that same resource group, to show I understand accidental-deletion
protection. And I've got working — not just documented — example code for
granting a second user `Reader` access at resource-group scope and `Storage
Blob Data Contributor` at the storage account, using RBAC instead of SAS
tokens or access policies."

**[4:15-5:00] The Bastion Developer cost trick**

"Here's a detail I'm proud of: Azure Bastion normally runs $130 to $200-plus
a month even on the cheapest SKU. But Microsoft shipped a Developer SKU
that's genuinely $0 an hour with free outbound data transfer. I use that as
the default, and if it's not available in a given region, I've documented
and coded a zero-cost fallback — locking the NSG's RDP/SSH rule to my
current public IP, which the cleanup script removes automatically. Either
way, RDP and SSH are never exposed to the raw internet."

**[5:00-5:45] Validate script**

*Run `./scripts/validate-lab.ps1`.*

"Once it's deployed, I don't just trust that it worked — I run
`validate-lab.ps1`, which re-checks every component: are the required tags
present, is secure transfer enforced on the storage account, is the Key
Vault in RBAC mode, is Bastion actually running the Developer SKU, does the
budget exist. It prints a PASS/FAIL table and returns a non-zero exit code
on any failure, so it's CI-friendly — I actually wire the same
PSScriptAnalyzer-plus-Pester pattern into GitHub Actions for the module code
itself."

**[5:45-6:30] Cleanup discipline**

"And when I'm done, `cleanup-lab.ps1` tears everything down in the correct
dependency order — VM, then NIC and disks, then Bastion, then the VNet, then
Key Vault, then storage, then Log Analytics, then the policy assignment,
then the resource groups themselves — removing the resource lock first so
it doesn't get stuck. It's idempotent too: if something's already gone, it
logs that and moves on instead of throwing. That discipline — leaving
nothing running, nothing billing — is the whole point of a free-tier lab."

**[6:30-7:00] Close**

"So that's the tour: modular PowerShell module backing everything, Pester
tests and PSScriptAnalyzer running in CI, real governance patterns, and a
Bastion cost trick that alone saves over a hundred dollars a month compared
to the naive approach. Happy to dig into any part of the code."

---

## Five talking points if asked about cost management

1. **Bastion Developer SKU is the single biggest lever** — it replaces a
   $130-200+/month Basic/Standard Bastion deployment with a genuinely $0/hour
   option, and I coded a zero-cost NSG fallback for regions where it's
   unavailable.
2. **Everything expensive is opt-in, not opt-out** — the test VM is skipped
   by default (`-SkipCompute`), and VM diagnostic/DCR log collection is
   documented as optional stretch rather than default behavior.
3. **The Log Analytics workspace has an explicit `dailyQuotaGb` cap**
   regardless of pricing tier, so ingestion cost has a hard ceiling I chose,
   not one Azure chose for me.
4. **Auto-shutdown isn't just a tag — it's a real schedule** applied via
   `Invoke-AzRestMethod` against `Microsoft.DevTestLab/schedules`, so the
   test VM physically powers off nightly instead of idling and billing
   24/7.
5. **I built in a $5/month budget with 80%/100% email alerts** — free to
   create, and it means I get notified before a mistake turns into a
   surprise instead of finding out at the end of the month.
