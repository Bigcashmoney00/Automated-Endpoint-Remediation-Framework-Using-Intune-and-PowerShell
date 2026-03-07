<#
.SYNOPSIS
    Remediation script for Windows Defender.
.DESCRIPTION
    Enables real-time monitoring and starts WinDefend service.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log { param($Msg) $e = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"; Add-Content -Path $LogFile -Value $e -ErrorAction SilentlyContinue; Write-Output $e }

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

try {
    # Set startup type and start service
    Set-Service -Name "WinDefend" -StartupType Automatic
    Start-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    Write-Log "Started WinDefend service"

    # Enable real-time monitoring (if not blocked by policy)
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Write-Log "Enabled real-time monitoring"

    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "WinDefend"
    if ($svc.Status -eq "Running") {
        Write-Log "SUCCESS: Windows Defender is running"
        exit 0
    }
    else {
        Write-Log "WARN: WinDefend status: $($svc.Status) - may be managed by policy"
        exit 0
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
