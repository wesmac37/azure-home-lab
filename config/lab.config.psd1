@{
    # =====================================================================
    # AzHomeLab master configuration
    # -----------------------------------------------------------------
    # This file centralizes every customizable value used by the
    # AzHomeLab module and the scripts/*.ps1 orchestration scripts.
    # Import with: Import-PowerShellDataFile -Path .\config\lab.config.psd1
    # =====================================================================

    # ---------------------------------------------------------------
    # Identity / naming
    # ---------------------------------------------------------------
    Workload      = 'homelab'
    Environment   = 'dev'
    Region        = 'eastus'

    # Free-form unique suffix used for globally-unique resource names
    # (storage account, key vault). Replace with your own short
    # alphanumeric string (4-6 chars recommended) before first deploy.
    UniqueSuffix  = 'lab01'

    # ---------------------------------------------------------------
    # Subscription
    # ---------------------------------------------------------------
    # Clearly-marked example placeholder. Scripts read the active
    # subscription from (Get-AzContext).Subscription.Id by default;
    # this value is only used if you explicitly pass -SubscriptionId.
    SubscriptionId = '<your-subscription-id>'

    # ---------------------------------------------------------------
    # Resource group names (lifecycle-based landing-zone pattern)
    # ---------------------------------------------------------------
    ResourceGroups = @{
        Mgmt    = 'rg-homelab-mgmt-eastus'
        Network = 'rg-homelab-network-eastus'
        Compute = 'rg-homelab-compute-eastus'
    }

    # ---------------------------------------------------------------
    # Required tags applied to every resource / resource group
    # ---------------------------------------------------------------
    Tags = @{
        Environment = 'Lab'
        Project     = 'AzureHomeLab'
        Owner       = '<your-name-or-email>'
        CostCenter  = 'Personal'
        AutoShutdown = 'false'
        CreatedBy   = 'IaC'
        DeployPhase = 'Foundation'
    }

    # ---------------------------------------------------------------
    # Networking
    # ---------------------------------------------------------------
    Network = @{
        VNetName          = 'vnet-homelab-dev-eastus'
        VNetAddressSpace  = '10.20.0.0/16'
        Subnets           = @{
            Mgmt            = @{ Name = 'snet-mgmt';           AddressPrefix = '10.20.0.0/24' }
            AzureBastionSubnet = @{ Name = 'AzureBastionSubnet'; AddressPrefix = '10.20.1.0/26' }
            App             = @{ Name = 'snet-app';            AddressPrefix = '10.20.2.0/24' }
        }
        NsgMgmtName = 'nsg-mgmt-homelab-dev-eastus'
        NsgAppName  = 'nsg-app-homelab-dev-eastus'
        BastionName = 'bas-homelab-dev-eastus'
        BastionSku  = 'Developer'
    }

    # ---------------------------------------------------------------
    # Storage
    # ---------------------------------------------------------------
    Storage = @{
        AccountNamePrefix = 'sthomelab'
        Sku               = 'Standard_LRS'
        Kind              = 'StorageV2'
        Containers        = @('scripts', 'logs', 'state')
    }

    # ---------------------------------------------------------------
    # Key Vault
    # ---------------------------------------------------------------
    KeyVault = @{
        NamePrefix   = 'kv-homelab-dev'
        DemoSecretName  = 'DemoConnectionString'
        DemoSecretValue = 'Server=tcp:demo.database.windows.net;Database=demo;Authentication=Active Directory Default;'
        EnableRbacAuthorization = $true
        EnablePurgeProtection   = $true
        SoftDeleteRetentionDays = 7
    }

    # ---------------------------------------------------------------
    # Monitoring
    # ---------------------------------------------------------------
    Monitoring = @{
        WorkspaceName = 'law-homelab-dev-eastus'
        Sku           = 'PerGB2018'
        DailyQuotaGb  = 1
        RetentionInDays = 30
    }

    # ---------------------------------------------------------------
    # Compute (optional, skipped by default to keep first run cheapest)
    # ---------------------------------------------------------------
    Compute = @{
        VmName          = 'vm-jump01-dev-eastus'
        VmSize          = 'Standard_B1s'
        OsType          = 'Windows'   # 'Windows' or 'Linux' (Ubuntu 22.04)
        AdminUsername   = 'labadmin'
        SkipComputeByDefault = $true
        AutoShutdownTimeZone = 'Eastern Standard Time'
        AutoShutdownTime     = '2300'
    }

    # ---------------------------------------------------------------
    # Governance
    # ---------------------------------------------------------------
    Governance = @{
        # Built-in policy definition: "Require a tag on resources"
        RequireTagPolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
        PolicyAssignmentName         = 'require-tag-homelab-mgmt'
        RequiredTagName              = 'Environment'

        # Clearly-marked PLACEHOLDER identities the user MUST replace
        # before running the RBAC example scripts. These are examples
        # only and will not resolve to a real principal.
        SecondUserObjectId = '<placeholder-object-id-for-second-user>'
        SecondUserUpn       = '<placeholder-upn@yourtenant.onmicrosoft.com>'

        ResourceLockName = 'lock-homelab-mgmt-CanNotDelete'
    }

    # ---------------------------------------------------------------
    # Budget / cost alerting (optional but free to create)
    # ---------------------------------------------------------------
    Budget = @{
        Name              = 'budget-homelab-monthly'
        AmountUsd         = 5
        ThresholdPercents = @(80, 100)
        ContactEmails     = @('<your-email@example.com>')
        StartDate         = '2026-07-01'
        EndDate           = '2027-07-01'
    }

    # ---------------------------------------------------------------
    # Deploy behavior defaults
    # ---------------------------------------------------------------
    Deploy = @{
        SkipComputeDefault = $true
        LogDirectory        = '../logs'
    }
}
