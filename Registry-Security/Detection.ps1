<#
.SYNOPSIS
    Detection script for critical registry security settings.
.DESCRIPTION
    Verifies required security-related registry keys exist with correct values.
    Exit 0 = Compliant, Exit 1 = Non-compliant
#>

$ErrorActionPreference = "SilentlyContinue"

# Define required registry settings: Path, Name, Type, ExpectedValue
$RequiredSettings = @(
    @{
        Path         = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Name         = "EnableLUA"
        Type         = "DWord"
        ExpectedValue = 1  # UAC enabled
    },
    @{
        Path         = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Name         = "ConsentPromptBehaviorAdmin"
        Type         = "DWord"
        ExpectedValue = 5  # Prompt for non-Windows binaries
    },
    @{
        Path         = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Name         = "LimitBlankPasswordUse"
        Type         = "DWord"
        ExpectedValue = 1  # Disable blank passwords
    }
)

$NonCompliant = @()

foreach ($setting in $RequiredSettings) {
    $current = Get-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
    if (-not $current -or $current.($setting.Name) -ne $setting.ExpectedValue) {
        $NonCompliant += "$($setting.Path)\$($setting.Name)"
    }
}

if ($NonCompliant.Count -gt 0) {
    Write-Output "Non-compliant: Missing or incorrect registry: $($NonCompliant -join '; ')"
    exit 1
}

Write-Output "Compliant: All registry security settings are correct"
exit 0
