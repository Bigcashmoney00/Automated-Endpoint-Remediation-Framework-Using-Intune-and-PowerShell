<#
.SYNOPSIS
    Remediation script for required applications.
.DESCRIPTION
    Installs missing apps via Winget. Configure $RequiredApps to match Detection.ps1.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log { param($Msg) $e = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"; Add-Content -Path $LogFile -Value $e -ErrorAction SilentlyContinue; Write-Output $e }

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

$RequiredApps = @(
    @{ DisplayName = "Microsoft Edge"; WingetId = "Microsoft.Edge" }
)

$wingetPath = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetPath) {
    Write-Log "ERROR: Winget not found. Cannot install applications."
    exit 1
}

$installed = 0
foreach ($app in $RequiredApps) {
    if (-not $app.WingetId) { continue }

    # Re-check if already installed (avoid redundant install)
    $check = winget list --id $app.WingetId 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Skipped $($app.DisplayName) - already installed"
        continue
    }

    try {
        Write-Log "Installing $($app.DisplayName)..."
        winget install --id $app.WingetId --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            $installed++
            Write-Log "SUCCESS: Installed $($app.DisplayName)"
        }
        else {
            Write-Log "WARN: Install may have failed for $($app.DisplayName)"
        }
    }
    catch {
        Write-Log "ERROR installing $($app.DisplayName): $($_.Exception.Message)"
    }
}

Write-Log "Remediation complete. Installed $installed application(s)."
exit 0
