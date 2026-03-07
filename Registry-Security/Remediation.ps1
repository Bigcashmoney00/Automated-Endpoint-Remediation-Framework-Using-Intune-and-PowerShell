<#
.SYNOPSIS
    Remediation script for registry security settings.
.DESCRIPTION
    Creates/restores required security registry keys.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$LogPath = "$env:ProgramData\Remediation\Logs"
$LogFile = Join-Path $LogPath "Remediation-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log { param($Msg) $e = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"; Add-Content -Path $LogFile -Value $e -ErrorAction SilentlyContinue; Write-Output $e }

if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

$Settings = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "EnableLUA"; Type = "DWord"; Value = 1 },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "ConsentPromptBehaviorAdmin"; Type = "DWord"; Value = 5 },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"; Name = "LimitBlankPasswordUse"; Type = "DWord"; Value = 1 }
)

try {
    foreach ($s in $Settings) {
        if (-not (Test-Path $s.Path)) {
            New-Item -Path $s.Path -ItemType Directory -Force | Out-Null
        }
        Set-ItemProperty -Path $s.Path -Name $s.Name -Value $s.Value -Type $s.Type -Force
        Write-Log "Set $($s.Path)\$($s.Name) = $($s.Value)"
    }
    Write-Log "SUCCESS: Registry security settings restored"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
