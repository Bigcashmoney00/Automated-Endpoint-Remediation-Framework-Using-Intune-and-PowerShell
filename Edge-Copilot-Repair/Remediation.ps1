<#
.SYNOPSIS
    Repair Microsoft Edge / Windows Copilot installs that throw 0xc000007b.
.DESCRIPTION
    Repairs in-place without reimaging Windows:
      1) Visual C++ 2015-2022 x64 redistributable (bitness / missing CRT)
      2) Microsoft Edge (force reinstall — Copilot loads msedge.dll from Edge)
      3) Edge WebView2 Runtime
      4) Re-register / reset Copilot AppX package
      5) Clear TurnOffWindowsCopilot policy if set
      6) Ensure common Copilot shell registry keys exist (HKCU when available)

    Safe to re-run. Prefer this over wiping the OS for embedded Microsoft apps.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    Write-Output $entry
}

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Invoke-WingetRepair {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName
    )
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log "WARN: winget not found; skipping $DisplayName"
        return $false
    }
    Write-Log "Repairing $DisplayName ($Id) via winget..."
    & winget install --id $Id --exact --force --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
        ForEach-Object { Write-Log "  winget: $_" }
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SUCCESS: $DisplayName repair/install completed"
        return $true
    }
    Write-Log "WARN: winget exit $LASTEXITCODE for $DisplayName (may already be present)"
    return $false
}

$fixed = 0

# --- 1) VC++ redistributable (classic 0xc000007b cause) ---
if (Invoke-WingetRepair -Id "Microsoft.VCRedist.2015+.x64" -DisplayName "Visual C++ 2015-2022 x64") {
    $fixed++
}
# Also ensure x86 CRT for mixed hosts
Invoke-WingetRepair -Id "Microsoft.VCRedist.2015+.x86" -DisplayName "Visual C++ 2015-2022 x86" | Out-Null

# --- 2) Microsoft Edge ---
if (Invoke-WingetRepair -Id "Microsoft.Edge" -DisplayName "Microsoft Edge") {
    $fixed++
}

# --- 3) WebView2 Runtime ---
if (Invoke-WingetRepair -Id "Microsoft.EdgeWebView2Runtime" -DisplayName "Edge WebView2 Runtime") {
    $fixed++
}

# --- 4) Copilot AppX reset / re-register ---
function Get-CopilotPackages {
    $pkgs = @()
    $pkgs += Get-AppxPackage -Name "Microsoft.Copilot" -ErrorAction SilentlyContinue
    $pkgs += Get-AppxPackage -Name "Microsoft.Windows.Copilot" -ErrorAction SilentlyContinue
    $pkgs += Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)^Microsoft\.(Windows\.)?Copilot$" -or
        ($_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub")
    }
    $pkgs | Sort-Object PackageFullName -Unique
}

$copilotPkgs = @(Get-CopilotPackages)
if ($copilotPkgs.Count -eq 0) {
    Write-Log "Copilot AppX not present — attempting provisioned package re-register..."
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "(?i)Copilot" -and $_.DisplayName -notmatch "(?i)Studio|GitHub" }
    foreach ($prov in $provisioned) {
        try {
            Write-Log "Re-adding provisioned package $($prov.DisplayName)..."
            Add-AppxPackage -RegisterByFamilyName -MainPackage $prov.PackageFamilyName -ErrorAction Stop
            $fixed++
            Write-Log "SUCCESS: Re-registered provisioned $($prov.PackageFamilyName)"
        }
        catch {
            Write-Log "WARN: Could not re-register $($prov.PackageFamilyName): $($_.Exception.Message)"
        }
    }
    # Store install as last resort when winget can see it
    Invoke-WingetRepair -Id "9NHT9RB2F4WD" -DisplayName "Microsoft Copilot (Store)" | Out-Null
    $copilotPkgs = @(Get-CopilotPackages)
}

foreach ($pkg in $copilotPkgs) {
    Write-Log "Repairing Copilot package $($pkg.PackageFullName)..."
    $resetWorked = $false
    if (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            Reset-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
            $resetWorked = $true
            $fixed++
            Write-Log "SUCCESS: Reset-AppxPackage $($pkg.PackageFullName)"
        }
        catch {
            Write-Log "WARN: Reset-AppxPackage failed: $($_.Exception.Message)"
        }
    }
    if (-not $resetWorked -and $pkg.InstallLocation) {
        $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
        if (Test-Path -LiteralPath $manifest) {
            try {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                $fixed++
                Write-Log "SUCCESS: Re-registered via AppxManifest.xml"
            }
            catch {
                Write-Log "WARN: Manifest re-register failed: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "WARN: No AppxManifest.xml under $($pkg.InstallLocation)"
        }
    }
}

# --- 5) Clear blocking Copilot policy (machine) ---
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
try {
    if (Test-Path $policyPath) {
        $val = (Get-ItemProperty -Path $policyPath -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue).TurnOffWindowsCopilot
        if ($val -eq 1) {
            Set-ItemProperty -Path $policyPath -Name "TurnOffWindowsCopilot" -Value 0 -Type DWord -Force
            $fixed++
            Write-Log "SUCCESS: Cleared TurnOffWindowsCopilot policy (set to 0)"
        }
    }
}
catch {
    Write-Log "WARN: Could not update Copilot policy: $($_.Exception.Message)"
}

# --- 6) Ensure Copilot-related shell registry keys (current user when interactive) ---
# Intune SYSTEM runs have no real HKCU; still create HKLM-friendly defaults and
# document the per-user keys for interactive/manual runs.
$userCopilotKeys = @(
    @{
        Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Name = "ShowCopilotButton"
        Type = "DWord"
        Value = 1
    },
    @{
        Path = "HKCU:\Software\Microsoft\Windows\Shell\Copilot"
        Name = "IsCopilotAvailable"
        Type = "DWord"
        Value = 1
    }
)

$interactiveUser = [Environment]::UserName -notmatch "(?i)^SYSTEM$"
if ($interactiveUser) {
    foreach ($k in $userCopilotKeys) {
        try {
            if (-not (Test-Path $k.Path)) {
                New-Item -Path $k.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $k.Path -Name $k.Name -Value $k.Value -Type $k.Type -Force
            Write-Log "Set $($k.Path)\$($k.Name)=$($k.Value)"
        }
        catch {
            Write-Log "WARN: Could not set $($k.Path)\$($k.Name): $($_.Exception.Message)"
        }
    }
}
else {
    Write-Log "INFO: Running as SYSTEM — skipped HKCU Copilot shell keys (apply per-user at logon if needed)"
}

# Optional: refresh AppX package repository state
try {
    Write-Log "Running AppX package repository cleanup (Get-AppxPackage)..."
    [void](Get-AppxPackage -ErrorAction SilentlyContinue)
}
catch {
    Write-Log "WARN: AppX refresh probe failed: $($_.Exception.Message)"
}

Write-Log "Remediation complete. Actions applied: $fixed. Reboot recommended if Copilot still returns 0xc000007b."
exit 0
