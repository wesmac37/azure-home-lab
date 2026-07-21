function New-LabVirtualMachine {
    <#
    .SYNOPSIS
        Idempotently creates the optional AzHomeLab test VM with no public IP and a nightly auto-shutdown schedule.

    .DESCRIPTION
        Creates (or returns the existing) test virtual machine sized
        Standard_B1s (free-eligible under the 750 hrs/month/12-months
        allowance). The VM is deployed with NO public IP address — access is
        exclusively via Azure Bastion Developer SKU or the documented
        IP-restricted NSG fallback. Boot diagnostics use managed storage
        (free, no separate storage account required). After the VM is
        created, an auto-shutdown schedule is configured against the
        Microsoft.DevTestLab/schedules resource type via Invoke-AzRestMethod
        (there is no native Az PowerShell cmdlet for the classic VM
        auto-shutdown feature), guaranteeing the VM powers off nightly so it
        never idles 24/7 and never approaches the 750-hour free-tier ceiling.

    .PARAMETER Name
        VM name, e.g. 'vm-jump01-dev-eastus'.

    .PARAMETER ResourceGroupName
        Resource group the VM belongs to.

    .PARAMETER Location
        Azure region.

    .PARAMETER SubnetId
        Resource ID of the subnet (snet-app) the VM's NIC will attach to.

    .PARAMETER VmSize
        VM size. Defaults to 'Standard_B1s'.

    .PARAMETER OsType
        'Windows' (Windows Server 2022) or 'Linux' (Ubuntu 22.04 LTS).

    .PARAMETER AdminUsername
        Local administrator username.

    .PARAMETER AdminPassword
        Local administrator password as a SecureString.

    .PARAMETER AutoShutdownTime
        24-hour HHmm time to auto-shutdown the VM nightly, e.g. '2300'.

    .PARAMETER AutoShutdownTimeZone
        Windows time zone ID used for the auto-shutdown schedule, e.g. 'Eastern Standard Time'.

    .PARAMETER Tags
        Tag hashtable to apply. Should include AutoShutdown=true for this resource.

    .EXAMPLE
        New-LabVirtualMachine -Name 'vm-jump01-dev-eastus' -ResourceGroupName 'rg-homelab-compute-eastus' `
            -Location 'eastus' -SubnetId $subnetId -OsType Windows -AdminUsername 'labadmin' `
            -AdminPassword $securePw -AutoShutdownTime '2300' -AutoShutdownTimeZone 'Eastern Standard Time' -Tags $tags
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubnetId,

        [Parameter(Mandatory = $false)]
        [string]$VmSize = 'Standard_B1s',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'Linux')]
        [string]$OsType,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AdminUsername,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$AdminPassword,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^([01]\d|2[0-3])[0-5]\d$')]
        [string]$AutoShutdownTime = '2300',

        [Parameter(Mandatory = $false)]
        [string]$AutoShutdownTimeZone = 'Eastern Standard Time',

        [Parameter(Mandatory = $true)]
        [hashtable]$Tags
    )

    try {
        $existingVm = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

        if ($existingVm) {
            Write-Verbose "New-LabVirtualMachine: VM '$Name' already exists. Skipping creation."
        }
        elseif ($PSCmdlet.ShouldProcess($Name, "Create $OsType virtual machine ($VmSize) with no public IP")) {
            Write-Verbose "New-LabVirtualMachine: creating NIC for '$Name' with no public IP."

            $nicName = "nic-$Name"
            $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
            if (-not $nic) {
                $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location `
                    -SubnetId $SubnetId -Tag $Tags -ErrorAction Stop
            }

            $cred = New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)

            $vmConfig = New-AzVMConfig -VMName $Name -VMSize $VmSize

            if ($OsType -eq 'Windows') {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $Name -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2022-datacenter-azure-edition' -Version 'latest'
            }
            else {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $Name -Credential $cred
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'Canonical' -Offer '0001-com-ubuntu-server-jammy' -Skus '22_04-lts-gen2' -Version 'latest'
            }

            $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType 'Standard_LRS'
            $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable

            $existingVm = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig -Tag $Tags -ErrorAction Stop
        }

        if ($existingVm -and $PSCmdlet.ShouldProcess($Name, "Configure nightly auto-shutdown at $AutoShutdownTime $AutoShutdownTimeZone")) {
            Write-Verbose "New-LabVirtualMachine: configuring auto-shutdown schedule for '$Name'."

            $subscriptionId = (Get-AzContext).Subscription.Id
            $scheduleResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$Name"
            $vmResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$Name"

            $body = @{
                properties = @{
                    status           = 'Enabled'
                    taskType         = 'ComputeVmShutdownTask'
                    dailyRecurrence  = @{ time = $AutoShutdownTime }
                    timeZoneId       = $AutoShutdownTimeZone
                    targetResourceId = $vmResourceId
                    notificationSettings = @{
                        status = 'Disabled'
                    }
                }
                location = $Location
            } | ConvertTo-Json -Depth 10

            try {
                Invoke-AzRestMethod -Path "$scheduleResourceId`?api-version=2018-09-15" -Method PUT -Payload $body -ErrorAction Stop | Out-Null
                Write-Verbose "New-LabVirtualMachine: auto-shutdown schedule applied to '$Name'."
            }
            catch {
                Write-Error "New-LabVirtualMachine: VM '$Name' was created but the auto-shutdown schedule could not be applied. Configure it manually in the portal (Overview > Auto-shutdown). Error: $($_.Exception.Message)"
            }
        }

        return $existingVm
    }
    catch {
        throw "New-LabVirtualMachine: failed to create or configure VM '$Name'. Error: $($_.Exception.Message)"
    }
}
