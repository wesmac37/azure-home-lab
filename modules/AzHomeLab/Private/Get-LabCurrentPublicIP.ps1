function Get-LabCurrentPublicIP {
    <#
    .SYNOPSIS
        Retrieves the caller's current public IPv4 address.

    .DESCRIPTION
        Internal helper used by the Bastion-unavailable fallback path
        (IP-restricted NSG rule) so that RDP/SSH access can be locked to the
        user's current public IP address rather than opened to the internet.
        Calls the free https://api.ipify.org service. Designed to be safe to
        call from Azure Cloud Shell.

    .EXAMPLE
        $myIp = Get-LabCurrentPublicIP
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -Method Get -TimeoutSec 10
        if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            throw "Unexpected response from ipify: '$ip'"
        }
        return $ip.Trim()
    }
    catch {
        throw "Get-LabCurrentPublicIP: unable to determine current public IP address. Error: $($_.Exception.Message)"
    }
}
