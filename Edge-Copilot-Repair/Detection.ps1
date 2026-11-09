<#
.SYNOPSIS
    Detection for damaged Microsoft Edge / Windows Copilot installs (0xc000007b).
.DESCRIPTION
    Checks Edge binaries, WebView2, Visual C++ redistributables, and the Copilot
    AppX package for missing files, bad AppX status, or broken install locations.
    These failures commonly surface as STATUS_INVALID_IMAGE_FORMAT (0xc000007b)
    when launching Copilot or Edge after a hard reset / partial update.

    Exit 0 = Compliant
    Exit 1 = Non-compliant (run remediation)
#>

$ErrorActionPreference = "SilentlyContinue"

$Issues = @()

function Test-PeMachineCompatible {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet("AMD64", "x86", "Any")]
        [string]$Expected = "AMD64"
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $bytes = New-Object byte[] 64
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            [void]$fs.Read($bytes, 0, 64)
        }
        finally {
            $fs.Dispose()
        }
        if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $false } # MZ
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        if ($peOffset -le 0 -or $peOffset -gt 4096) { return $false }
        $peHeader = New-Object byte[] 6
        $fs2 = [System.IO.File]::OpenRead($Path)
        try {
            [void]$fs2.Seek($peOffset, 'Begin')
            [void]$fs2.Read($peHeader, 0, 6)
        }
        finally {
            $fs2.Dispose()
        }
        if ($peHeader[0] -ne 0x50 -or $peHeader[1] -ne 0x45) { return $false } # PE
        $machine = [BitConverter]::ToUInt16($peHeader, 4)
        # 0x8664 = AMD64, 0x14C = i386
        switch ($Expected) {
            "AMD64" { return ($machine -eq 0x8664) }
            "x86"   { return ($machine -eq 0x14C) }
            default { return $true }
        }
    }
    catch {
        return $false
    }
}

# --- Microsoft Edge ---
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
    $Issues += "Microsoft Edge msedge.exe invalid or wrong architecture (0xc000007b risk)"
}

if ($edgeExe -and -not $msedgeDll) {
    $Issues += "Microsoft Edge msedge.dll missing beside msedge.exe"
}
elseif ($msedgeDll -and -not (Test-PeMachineCompatible -Path $msedgeDll -Expected AMD64)) {
    $Issues += "Microsoft Edge msedge.dll invalid or wrong architecture (0xc000007b risk)"
}

# --- WebView2 Runtime (Copilot / Edge embedded hosts depend on this) ---
$webviewPaths = @(
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application",
    "$env:ProgramFiles\Microsoft\EdgeWebView\Application"
)
$webviewOk = $false
foreach ($wv in $webviewPaths) {
    if (Test-Path $wv) {
        $wvExe = Get-ChildItem -Path $wv -Filter "msedgewebview2.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($wvExe -and (Test-PeMachineCompatible -Path $wvExe.FullName -Expected AMD64)) {
            $webviewOk = $true
            break
        }
    }
}
if (-not $webviewOk) {
    $Issues += "Edge WebView2 Runtime missing or damaged"
}

# --- Visual C++ 2015-2022 x64 redistributable (common 0xc000007b root cause) ---
$vcKeys = @(
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64"
)
$vcOk = $false
foreach ($key in $vcKeys) {
    $prop = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($prop -and ($prop.Installed -eq 1 -or $prop.Major -ge 14)) {
        $vcOk = $true
        break
    }
}
# Fallback: uninstall entry
if (-not $vcOk) {
    $uninstall = Get-ItemProperty @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "Visual C\+\+.*(2015|2017|2019|2022).*x64" }
    if ($uninstall) { $vcOk = $true }
}
if (-not $vcOk) {
    $Issues += "Visual C++ 2015-2022 x64 Redistributable missing"
}

# --- Windows Copilot AppX ---
$copilotPackages = @(
    Get-AppxPackage -Name "Microsoft.Copilot" -ErrorAction SilentlyContinue
    Get-AppxPackage -Name "Microsoft.Windows.Copilot" -ErrorAction SilentlyContinue
    Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub"
    }
) | Sort-Object -Property PackageFullName -Unique

if (-not $copilotPackages -or $copilotPackages.Count -eq 0) {
    # Also check AllUsers when running as SYSTEM
    $copilotPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(?i)^Microsoft\.(Windows\.)?Copilot$" -or
        ($_.Name -match "(?i)Copilot" -and $_.Name -notmatch "(?i)Copilot\.Studio|GitHub")
    } | Sort-Object -Property PackageFullName -Unique
}

if (-not $copilotPackages -or $copilotPackages.Count -eq 0) {
    $Issues += "Windows Copilot AppX package not installed"
}
else {
    foreach ($pkg in $copilotPackages) {
        if ($pkg.Status -and $pkg.Status.ToString() -ne "Ok") {
            $Issues += "Copilot package status not Ok: $($pkg.PackageFullName) [$($pkg.Status)]"
        }
        if (-not $pkg.InstallLocation -or -not (Test-Path -LiteralPath $pkg.InstallLocation)) {
            $Issues += "Copilot InstallLocation missing: $($pkg.PackageFullName)"
            continue
        }
        $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
        if (-not (Test-Path -LiteralPath $manifest)) {
            $Issues += "Copilot AppxManifest.xml missing: $($pkg.PackageFullName)"
        }
        $copilotApp = Get-ChildItem -Path $pkg.InstallLocation -Filter "CopilotApp.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $copilotApp) {
            $copilotApp = Get-ChildItem -Path $pkg.InstallLocation -Filter "copilot*.exe" -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        if ($copilotApp -and -not (Test-PeMachineCompatible -Path $copilotApp.FullName -Expected AMD64)) {
            $Issues += "Copilot executable invalid or wrong architecture: $($copilotApp.FullName)"
        }
    }
}

# Policy that fully disables Copilot (treat as non-compliant for this repair package)
$policy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
if ($policy -and $policy.TurnOffWindowsCopilot -eq 1) {
    $Issues += "Policy TurnOffWindowsCopilot=1 blocks Copilot"
}

if ($Issues.Count -gt 0) {
    Write-Output "Non-compliant: $($Issues -join '; ')"
    exit 1
}

Write-Output "Compliant: Edge, WebView2, VC++ x64, and Copilot AppX look healthy"
exit 0
