# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-21

### Added

- Initial release of the AzHomeLab PowerShell module (`modules/AzHomeLab/`)
  with 18 public functions covering resource groups, naming/tagging
  helpers, networking (VNet/subnets/NSGs/Bastion), storage, Key Vault, Log
  Analytics, compute, governance (policy/RBAC/locks), budgets, resource
  provider registration, and validation.
- `config/lab.config.psd1` centralizing all customizable naming, tagging,
  networking, storage, Key Vault, monitoring, compute, governance, and
  budget values.
- `scripts/deploy-lab.ps1` — phased deployment orchestrator (Foundation,
  Network, Security, Storage, Monitoring, Compute) with `-WhatIf` support,
  idempotent resource-provider registration, and a deployment log written
  to `logs/`.
- `scripts/validate-lab.ps1` — post-deploy PASS/FAIL validation with
  CI-friendly non-zero exit codes on failure.
- `scripts/cleanup-lab.ps1` — safe, dependency-ordered, idempotent teardown
  with automatic resource-lock removal.
- `scripts/Get-LabCostEstimate.ps1` — month-to-date cost reporting via
  `Get-AzConsumptionUsageDetail` with a portal-navigation fallback when the
  Consumption API is unavailable.
- Pester v5 test suite (`tests/`) covering module naming/tagging helpers,
  configuration loading, deploy-lab `-WhatIf` execution, and validation
  logic — 8+ `It` blocks across three test files, all Az cmdlets mocked.
- GitHub Actions CI workflow (`.github/workflows/powershell-ci.yml`) running
  PSScriptAnalyzer and Pester on every push/PR to `main`, publishing NUnit
  XML test results as an artifact.
- Full documentation set: `docs/architecture.md`, `docs/cost-awareness.md`,
  `docs/troubleshooting.md`, `docs/demo-script.md`,
  `docs/validation-checklist.md`, `docs/interview-talking-points.md`, and
  `docs/screenshots/README.md`.
- Mermaid architecture diagram (`diagrams/architecture.mmd`), embedded
  inline in `README.md` and `docs/architecture.md`.
- MIT `LICENSE`, `.gitignore`, and this `CHANGELOG.md`.
