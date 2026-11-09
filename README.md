# Automated-Endpoint-Remediation-Framework-Using-Intune-and-PowerShell
Built automated endpoint remediation workflows using PowerShell and Intune proactive remediations to detect and resolve configuration drift across enterprise Windows devices.

## Concept

Instead of fixing issues manually, endpoints **detect** problems and **remediate** themselves automatically. Intune runs detection scripts on a schedule; when a script reports non-compliance, the remediation script runs to fix it.

## Architecture

```
Detection Script (runs every X hours)
    │
    ├── Exit 0 = Compliant (no action)
    │
    └── Exit 1 = Non-compliant
            │
            ▼
    Remediation Script (runs to fix)
            │
            └── Logs result to Intune / local
```

## Project Structure

```
endpoint-remediation/
├── README.md                    # This file
├── INUNE-DEPLOYMENT.md          # Intune setup guide
├── scripts/
│   └── RemediationLogger.ps1    # Shared logging module
├── remediations/
│   ├── WindowsUpdate-Service/   # Broken Windows Update service
│   ├── Registry-Security/       # Missing registry security settings
│   ├── Defender-Status/         # Disabled Windows Defender
│   ├── Required-Apps/           # Failed/missing application installations
│   └── Edge-Copilot-Repair/     # Edge/Copilot 0xc000007b damaged installs
└── monitoring/
    └── RemediationReport.ps1    # Aggregate logs and report
```

## Remediations Included

| Issue | Detection | Remediation |
|-------|-----------|-------------|
| **Windows Update Service** | Service not running or wrong startup type | Restart service, set to Automatic |
| **Registry Security** | Key missing or value incorrect | Create/restore registry settings |
| **Windows Defender** | Real-time protection disabled | Enable Defender, restart service |
| **Required Applications** | App not installed or corrupted | Reinstall via Winget/Chocolatey |
| **Edge / Copilot (0xc000007b)** | Missing/bad Edge, WebView2, VC++ x64, or Copilot AppX | Force-repair via winget + reset/re-register Copilot AppX + policy/registry |

## Intune Proactive Remediation Requirements

- Microsoft Intune (MEM) license
- Devices enrolled in Intune
- **Endpoint analytics** or **Proactive remediations** (part of Intune add-ons)

## Deployment

1. Go to **Intune** → **Reports** → **Endpoint analytics** → **Proactive remediations**
2. Create a new script package for each remediation
3. Upload Detection.ps1 and Remediation.ps1
4. Assign to device groups
5. Set run schedule (e.g., every 8 hours)

See [INUNE-DEPLOYMENT.md](INUNE-DEPLOYMENT.md) for step-by-step instructions.

## Local Testing

Run detection only (no changes):
```powershell
.\remediations\WindowsUpdate-Service\Detection.ps1
# Exit 0 = OK, Exit 1 = needs fix
```

Run remediation manually:
```powershell
.\remediations\WindowsUpdate-Service\Remediation.ps1
```

## Logging & Monitoring

- Scripts write to `C:\ProgramData\Remediation\Logs\` (configurable)
- Intune captures output in **Device** → **Proactive remediations** → Script results
- Use `monitoring/RemediationReport.ps1` to aggregate local logs

## Security

- Scripts require SYSTEM context (Intune runs as SYSTEM)
- No credentials in scripts; use Managed Identity or Azure Key Vault for secrets
- Audit before production deployment


