function Write-LabLog {
    <#
    .SYNOPSIS
        Writes a timestamped log line to the console and, optionally, to a log file.

    .DESCRIPTION
        Shared logging helper used by the orchestration scripts (deploy-lab.ps1,
        validate-lab.ps1, cleanup-lab.ps1, Get-LabCostEstimate.ps1) to emit
        consistent, timestamped status output. Honors -Verbose for
        detailed tracing while keeping default output concise. When -LogPath is
        supplied the same line is appended to the file so deploy-lab.ps1 and
        cleanup-lab.ps1 can produce a persistent transcript.

    .PARAMETER Message
        The message text to write.

    .PARAMETER Level
        Severity level of the message. One of Info, Verbose, Warning, Error.
        Defaults to Info.

    .PARAMETER LogPath
        Optional path to a log file. If supplied, the line is appended to the file.

    .EXAMPLE
        Write-LabLog -Message 'Starting Foundation phase' -Level Info -LogPath $logPath

    .EXAMPLE
        Write-LabLog -Message 'Resource already exists, skipping' -Level Verbose
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Verbose', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message

    switch ($Level) {
        'Info'    { Write-Host $line }
        'Verbose' { Write-Verbose $line }
        'Warning' { Write-Warning $line }
        'Error'   { Write-Error $line }
    }

    if ($LogPath) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if ($logDir -and -not (Test-Path -Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $line -Encoding utf8
        }
        catch {
            Write-Warning "Write-LabLog: failed to write to log file '$LogPath': $($_.Exception.Message)"
        }
    }
}
