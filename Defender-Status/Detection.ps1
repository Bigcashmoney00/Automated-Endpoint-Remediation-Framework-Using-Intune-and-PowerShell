<#
.SYNOPSIS
    Detection script for Windows Defender status.
.DESCRIPTION
    Exit 0 = Compliant (Defender enabled, real-time protection on)
    Exit 1 = Non-compliant
#>

$ErrorActionPreference = "SilentlyContinue"

try {
    # Check if Defender is enabled (not disabled by policy)
    $pref = Get-MpPreference -ErrorAction Stop

    if ($pref.DisableRealtimeMonitoring -eq $true) {
        Write-Output "Non-compliant: Windows Defender real-time monitoring is disabled"
        exit 1
    }

    # Check service
    $service = Get-Service -Name "WinDefend" -ErrorAction Stop
    if ($service.Status -ne "Running") {
        Write-Output "Non-compliant: WinDefend service is not running (Status: $($service.Status))"
        exit 1
    }

    Write-Output "Compliant: Windows Defender is enabled and running"
    exit 0
}
catch {
    # Defender module might not be available in some SKUs
    Write-Output "Non-compliant: Unable to verify Defender - $($_.Exception.Message)"
    exit 1
}
