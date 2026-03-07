<#
.SYNOPSIS
    Remediation script for Windows Update service.
.DESCRIPTION
    Sets startup to Automatic, starts the service, restarts if needed.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$ServiceName = "wuauserv"
$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log { param($Msg) $e = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"; Add-Content -Path $LogFile -Value $e -ErrorAction SilentlyContinue; Write-Output $e }

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop

    # Set startup type
    Set-Service -Name $ServiceName -StartupType Automatic
    Write-Log "Set $ServiceName startup to Automatic"

    # Start if stopped
    if ($service.Status -ne "Running") {
        Start-Service -Name $ServiceName
        Write-Log "Started $ServiceName"
    }

    # Verify
    Start-Sleep -Seconds 2
    $updated = Get-Service -Name $ServiceName
    if ($updated.Status -eq "Running") {
        Write-Log "SUCCESS: Windows Update service is now running"
        exit 0
    }
    else {
        Write-Log "WARN: Service may need reboot - Status: $($updated.Status)"
        exit 0  # Remediation attempted
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
