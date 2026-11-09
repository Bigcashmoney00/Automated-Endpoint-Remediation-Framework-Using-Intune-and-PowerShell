<#
.SYNOPSIS
    NinjaOne automation: repair Edge / Copilot 0xc000007b without reimaging.
.DESCRIPTION
    Self-contained script for NinjaOne Automation Library.

    NinjaOne settings:
      Language : PowerShell
      Run as   : System
      Timeout  : 30+ minutes (winget repairs can be slow)

    Exit 0 = healthy up front, or repair completed
    Exit 1 = critical failure (e.g. winget unavailable)

    Optional: use Detection.ps1 as a NinjaOne condition (exit 1 = unhealthy)
    and this script / Remediation.ps1 as the linked automation.
#>

$ErrorActionPreference = "Continue"

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    Write-Output $entry
}

function Test-PeMachineCompatible {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet("AMD64", "x86")][string]$Expected = "AMD64"
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $bytes = New-Object byte[] 64
        $fs = [System.IO.File]::OpenRead($Path)
        try { [void]$fs.Read($bytes, 0, 64) } finally { $fs.Dispose() }
        if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $false }
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        if ($peOffset -le 0 -or $peOffset -gt 4096) { return $false }
        $peHeader = New-Object byte[] 6
        $fs2 = [System.IO.File]::OpenRead($Path)
        try {
            [void]$fs2.Seek($peOffset, 'Begin')
            [void]$fs2.Read($peHeader, 0, 6)
        }
        finally { $fs2.Dispose() }
        if ($peHeader[0] -ne 0x50 -or $peHeader[1] -ne 0x45) { return $false }
        $machine = [BitConverter]::ToUInt16($peHeader, 4)
        if ($Expected -eq "AMD64") { return ($machine -eq 0x8664) }
        return ($machine -eq 0x14C)
    }
    catch { return $false }
}

function Get-HealthIssues {
    $Issues = @()

    $edgeRoots = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application",
        "$env:ProgramFiles\Microsoft\Edge\Application"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $edgeExe = $null
    $msedgeDll = $null
    foreach ($root in $edgeRoots) {
        $candidate = Get-ChildItem -Path $root -Filter "msedge.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) {
            $edgeExe = $candidate.FullName
            $dll = Join-Path $candidate.DirectoryName "msedge.dll"
            if (Test-Path -LiteralPath $dll) { $msedgeDll = $dll }
            break
        }
    }

    if (-not $edgeExe) {
        $Issues += "Microsoft Edge msedge.exe missing"
    }
    elseif (-not (Test-PeMachineCompatible -Path $edgeExe -Expected AMD64)) {
        $Issues += "Microsoft Edge msedge.exe invalid or wrong architecture"
    }

    if ($edgeExe -and -not $msedgeDll) {
        $Issues += "Microsoft Edge msedge.dll missing"
    }
    elseif ($msedgeDll -and -not (Test-PeMachineCompatible -Path $msedgeDll -Expected AMD64)) {
        $Issues += "Microsoft Edge msedge.dll invalid or wrong architecture"
    }

    $webviewOk = $false
    foreach ($wv in @(
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application"
    )) {
        if (-not (Test-Path $wv)) { continue }
        $wvExe = Get-ChildItem -Path $wv -Filter "msedgewebview2.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($wvExe -and (Test-PeMachineCompatible -Path $wvExe.FullName -Expected AMD64)) {
            $webviewOk = $true
            break
        }
    }
    if (-not $webviewOk) { $Issues += "Edge WebView2 Runtime missing or damaged" }

    $vcOk = $false
    foreach ($key in @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64"
    )) {
        $prop = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($prop -and ($prop.Installed -eq 1 -or $prop.Major -ge 14)) { $vcOk = $true; break }
    }
    if (-not $vcOk) {
        $uninstall = Get-ItemProperty @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        ) -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "Visual C\+\+.*(2015|2017|2019|2022).*x64" }
        if ($uninstall) { $vcOk = $true }
    }
    if (-not $vcOk) { $Issues += "Visual C++ 2015-2022 x64 Redistributable missing" }

    $copilotPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)^Microsoft\.(Windows\.)?Copilot$" -or
        ($_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub")
    } | Sort-Object PackageFullName -Unique

    if (-not $copilotPackages) {
        $Issues += "Windows Copilot AppX package not installed"
    }
    else {
        foreach ($pkg in $copilotPackages) {
            if ($pkg.Status -and $pkg.Status.ToString() -ne "Ok") {
                $Issues += "Copilot package status not Ok: $($pkg.PackageFullName)"
            }
            if (-not $pkg.InstallLocation -or -not (Test-Path -LiteralPath $pkg.InstallLocation)) {
                $Issues += "Copilot InstallLocation missing: $($pkg.PackageFullName)"
                continue
            }
            $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
            if (-not (Test-Path -LiteralPath $manifest)) {
                $Issues += "Copilot AppxManifest.xml missing: $($pkg.PackageFullName)"
            }
        }
    }

    $policy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
    if ($policy -and $policy.TurnOffWindowsCopilot -eq 1) {
        $Issues += "Policy TurnOffWindowsCopilot=1 blocks Copilot"
    }

    return $Issues
}

function Get-WingetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    # NinjaOne System context often has no winget on PATH
    $hit = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Microsoft\.DesktopAppInstaller_.*_x64__8wekyb3d8bbwe' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }

    $localApp = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path $localApp) { return $localApp }
    return $null
}

function Invoke-WingetRepair {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$WingetExe
    )
    Write-Log "Repairing $DisplayName ($Id)..."
    & $WingetExe install --id $Id --exact --force --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
        ForEach-Object { Write-Log "  winget: $_" }
    if ($LASTEXITCODE -eq 0) {
        Write-Log "SUCCESS: $DisplayName"
        return $true
    }
    Write-Log "WARN: winget exit $LASTEXITCODE for $DisplayName"
    return $false
}

Write-Log "NinjaOne Edge/Copilot DetectAndRepair on $env:COMPUTERNAME (user=$([Environment]::UserName))"

$issues = @(Get-HealthIssues)
if ($issues.Count -eq 0) {
    Write-Log "Compliant: Edge, WebView2, VC++ x64, and Copilot look healthy — no repair needed."
    exit 0
}

Write-Log "Non-compliant: $($issues -join '; ')"

$wingetExe = Get-WingetPath
if (-not $wingetExe) {
    Write-Log "ERROR: winget not found under System. Install/update App Installer, then re-run."
    exit 1
}
Write-Log "Using winget: $wingetExe"

$fixed = 0
foreach ($app in @(
    @{ Id = "Microsoft.VCRedist.2015+.x64"; Name = "Visual C++ 2015-2022 x64" },
    @{ Id = "Microsoft.VCRedist.2015+.x86"; Name = "Visual C++ 2015-2022 x86" },
    @{ Id = "Microsoft.Edge"; Name = "Microsoft Edge" },
    @{ Id = "Microsoft.EdgeWebView2Runtime"; Name = "Edge WebView2 Runtime" }
)) {
    if (Invoke-WingetRepair -Id $app.Id -DisplayName $app.Name -WingetExe $wingetExe) { $fixed++ }
}

$copilotPkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "(?i)^Microsoft\.(Windows\.)?Copilot$" -or
    ($_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub")
} | Sort-Object PackageFullName -Unique

if (-not $copilotPkgs) {
    Write-Log "Copilot AppX missing — trying Store package via winget..."
    Invoke-WingetRepair -Id "9NHT9RB2F4WD" -DisplayName "Microsoft Copilot (Store)" -WingetExe $wingetExe | Out-Null
    $copilotPkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub"
    }
}

foreach ($pkg in $copilotPkgs) {
    Write-Log "Repairing Copilot $($pkg.PackageFullName)..."
    $done = $false
    if (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            Reset-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
            $done = $true
            $fixed++
            Write-Log "SUCCESS: Reset-AppxPackage $($pkg.Name)"
        }
        catch {
            Write-Log "WARN: Reset-AppxPackage failed: $($_.Exception.Message)"
        }
    }
    if (-not $done -and $pkg.InstallLocation) {
        $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
        if (Test-Path -LiteralPath $manifest) {
            try {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                $fixed++
                Write-Log "SUCCESS: Re-registered Copilot via AppxManifest.xml"
            }
            catch {
                Write-Log "WARN: Manifest re-register failed: $($_.Exception.Message)"
            }
        }
    }
}

$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
try {
    if (Test-Path $policyPath) {
        $val = (Get-ItemProperty -Path $policyPath -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue).TurnOffWindowsCopilot
        if ($val -eq 1) {
            Set-ItemProperty -Path $policyPath -Name "TurnOffWindowsCopilot" -Value 0 -Type DWord -Force
            $fixed++
            Write-Log "SUCCESS: Cleared TurnOffWindowsCopilot policy"
        }
    }
}
catch {
    Write-Log "WARN: Could not update Copilot policy: $($_.Exception.Message)"
}

Write-Log "Repair finished. Actions applied: $fixed. Reboot once if Copilot still returns 0xc000007b."
exit 0
