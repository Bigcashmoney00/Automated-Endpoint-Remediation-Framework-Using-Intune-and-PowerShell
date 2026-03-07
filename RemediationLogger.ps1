<#
.SYNOPSIS
    Shared logging module for Intune Proactive Remediation scripts.

.DESCRIPTION
    Provides consistent logging to file and stdout for detection/remediation scripts.
    Intune captures stdout; file logs persist for local monitoring.
#>

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-RemediationLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',
        [string]$ScriptName = $MyInvocation.ScriptName
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] [$ScriptName] $Message"

    # Ensure log directory exists
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue

    # Write to stdout (captured by Intune)
    Write-Output $entry
}

function Get-RemediationLogPath {
    return $LogPath
}

function Get-RemediationLogFile {
    return $LogFile
}
