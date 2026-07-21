# Interview Talking Points

A reference sheet of the strongest points to raise when discussing this
project in an interview, mapped to the skills they demonstrate.

## "Walk me through a project you're proud of"

- Built a fully modular Azure home lab (`AzHomeLab` PowerShell module) that
  deploys entirely within Azure Free Account limits — $0-a-few-cents per
  month at rest, by design, not by accident.
- Structured as a **landing-zone-style** repo: separate resource groups by
  lifecycle (management/network/compute), naming and tagging conventions
  enforced in code and by policy, and phased deployment scripts that mirror
  how you'd actually roll infrastructure out in stages in a real
  organization.
- Backed by real engineering hygiene: Pester v5 unit tests, PSScriptAnalyzer
  linting, and a GitHub Actions CI pipeline that runs both on every push/PR.

## "How do you think about cloud cost management?"

- Chose Azure Bastion **Developer SKU** specifically because it's $0/hour
  versus $130-200+/month for Basic/Standard — and documented + coded a
  fallback (IP-restricted NSG rule) for regions where Developer SKU isn't
  available yet.
- Set an explicit `dailyQuotaGb` cap on the Log Analytics workspace
  regardless of pricing tier, so ingestion cost has a ceiling I chose.
- Made the only VM in the lab **opt-in** (`-SkipCompute` defaults to
  skipping it) and gave it a real, working **auto-shutdown schedule** via
  `Invoke-AzRestMethod` against `Microsoft.DevTestLab/schedules` — not just
  a tag that says `AutoShutdown=true`, an actual enforced nightly power-off.
- Shipped a **working** $5/month consumption budget with 80%/100% email
  alert thresholds, because budgets are free to create and there's no
  reason not to have one.
- Classified every component explicitly (Free / 12-months-free / Uses $200
  credit / Low-cost pay-as-you-go / Optional-may-cost-money) in
  [cost-awareness.md](./cost-awareness.md) with citations back to Microsoft
  documentation, rather than assuming.

## "How do you approach infrastructure automation / IaC?"

- Every resource-creating function follows an **idempotent Get-then-New
  pattern**: check with `Get-Az*` first, skip or return the existing object,
  only call `New-Az*` if it's actually missing. Re-running any phase is
  always safe.
- Every function that creates or deletes something supports
  `-WhatIf`/`-Confirm` via `[CmdletBinding(SupportsShouldProcess)]`, so
  you can preview a change before committing to it — the same discipline
  you'd want before touching production.
- No hard-coded subscription IDs — scripts read
  `(Get-AzContext).Subscription.Id` or accept a parameter, with a clearly
  marked example placeholder value if none is supplied.
- All customizable values (names, region, tags, budget amount, VM size,
  `SkipCompute` default) live in one data file
  (`config/lab.config.psd1`), imported via `Import-PowerShellDataFile` —
  config is separated from logic.

## "How do you handle security/governance in the cloud?"

- RDP/SSH are **never** exposed to the internet — access is exclusively via
  Azure Bastion Developer SKU, or, as a documented fallback, an NSG rule
  scoped to a single `/32` IP that's removed on cleanup.
- Key Vault runs in **RBAC authorization mode**, not legacy access policies,
  which is the current Microsoft-recommended pattern and integrates
  cleanly with Entra ID role assignments.
- Storage account access uses **RBAC (Storage Blob Data Contributor)**
  instead of SAS tokens — no long-lived shared-key credentials to leak or
  rotate.
- Demonstrated Azure Policy (`Require a tag on resources`), resource locks
  (`CanNotDelete`), and RBAC role assignment examples, all scoped correctly
  and all runnable, not just described.
- Documented (not live-wired, since it needs the reader's own tenant) the
  OIDC federated-credential pattern for letting GitHub Actions deploy to
  Azure without long-lived secrets — the enterprise-correct approach.

## "Why should we trust you with production infrastructure if this is just a lab?"

- The engineering discipline is the point, not the scale: comment-based
  help on every function, parameter validation attributes, try/catch with
  actionable error messages, `Write-Verbose` step tracing, and a test suite
  that mocks every `Az*` call so CI never touches a real subscription.
- The same phased-deploy / validate / cleanup lifecycle scales conceptually
  to much larger environments — I just capped every component's blast
  radius and cost on purpose here.
- Background in VMware/Windows/Linux/Citrix infrastructure plus AZ-104
  (with AZ-305 in progress) means the cloud-native tooling is additive to,
  not a replacement for, twenty-plus years of understanding how
  infrastructure actually behaves under load, failure, and change.
