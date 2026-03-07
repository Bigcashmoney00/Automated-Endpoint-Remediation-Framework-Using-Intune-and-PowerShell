<#
.SYNOPSIS
    Detection script for Windows Update service health.
.DESCRIPTION
    Exit 0 = Compliant (service running, startup Automatic)
    Exit 1 = Non-compliant (needs remediation)
#>

$ErrorActionPreference = "SilentlyContinue"

$ServiceName = "wuauserv"  # Windows Update
$RequiredStartup = "Automatic"

try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop

    if ($service.Status -ne "Running") {
        Write-Output "Non-compliant: Windows Update service is not running (Status: $($service.Status))"
        exit 1
    }

    $startup = (Get-WmiObject Win32_Service -Filter "Name='$ServiceName'").StartMode
    if ($startup -ne $RequiredStartup) {
        Write-Output "Non-compliant: Windows Update startup type is $startup (expected $RequiredStartup)"
        exit 1
    }

    Write-Output "Compliant: Windows Update service is running and set to $RequiredStartup"
    exit 0
}
catch {
    Write-Output "Non-compliant: Unable to verify Windows Update service - $($_.Exception.Message)"
    exit 1
}
