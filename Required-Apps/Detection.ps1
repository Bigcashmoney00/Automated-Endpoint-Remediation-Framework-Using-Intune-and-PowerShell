<#
.SYNOPSIS
    Detection script for required applications.
.DESCRIPTION
    Verifies required apps are installed. Configure $RequiredApps below.
    Exit 0 = Compliant, Exit 1 = Non-compliant
#>

$ErrorActionPreference = "SilentlyContinue"

# Configure required apps: DisplayName (for detection) and/or WingetId
$RequiredApps = @(
    @{ DisplayName = "Microsoft Edge"; WingetId = "Microsoft.Edge" }
    # Add more: @{ DisplayName = "7-Zip"; WingetId = "7zip.7zip" }
)

$Missing = @()

foreach ($app in $RequiredApps) {
    $found = $false

    # Try WinGet
    if ($app.WingetId) {
        $winget = winget list --id $app.WingetId 2>$null
        if ($LASTEXITCODE -eq 0) { $found = $true }
    }

    # Fallback: check via Uninstall registry
    if (-not $found -and $app.DisplayName) {
        $keys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($key in $keys) {
            $items = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($items | Where-Object { $_.DisplayName -like "*$($app.DisplayName)*" }) {
                $found = $true
                break
            }
        }
    }

    if (-not $found) {
        $Missing += $app.DisplayName
    }
}

if ($Missing.Count -gt 0) {
    Write-Output "Non-compliant: Missing applications: $($Missing -join ', ')"
    exit 1
}

Write-Output "Compliant: All required applications are installed"
exit 0
