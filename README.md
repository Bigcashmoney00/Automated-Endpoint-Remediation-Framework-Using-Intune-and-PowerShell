# Automated Endpoint Remediation Framework (NinjaOne + PowerShell)

Built automated endpoint remediation workflows using PowerShell and **NinjaOne** to detect and resolve configuration drift across managed Windows devices.

> Primary RMM: **NinjaOne**. Intune notes remain in `INUNE-DEPLOYMENT.md` only as an optional alternate.

## Concept

Instead of fixing issues manually, endpoints **detect** problems and **remediate** themselves automatically. NinjaOne runs scripts on-demand, on a schedule, or when a condition fails.

## Architecture (NinjaOne)

```
On-demand / Scheduled script / Condition
    │
    ├── Healthy (exit 0) → done
    │
    └── Unhealthy → remediation script (System)
            │
            └── Logs to NinjaOne activity + C:\ProgramData\Remediation\Logs
```

## Project Structure

```
endpoint-remediation/
├── README.md
├── NINJAONE-DEPLOYMENT.md       # NinjaOne setup (primary)
├── INUNE-DEPLOYMENT.md          # Optional Intune notes
├── RemediationLogger.ps1
├── WindowsUpdate-Service/
├── Registry-Security/
├── Defender-Status/
├── Required-Apps/
└── Edge-Copilot-Repair/         # Edge/Copilot 0xc000007b repair
    ├── Detection.ps1
    ├── Remediation.ps1
    └── NinjaOne-DetectAndRepair.ps1   # paste this into NinjaOne
```

## Remediations Included

| Issue | Detection | Remediation |
|-------|-----------|-------------|
| **Windows Update Service** | Service not running or wrong startup type | Restart service, set to Automatic |
| **Registry Security** | Key missing or value incorrect | Create/restore registry settings |
| **Windows Defender** | Real-time protection disabled | Enable Defender, restart service |
| **Required Applications** | App not installed or corrupted | Reinstall via Winget |
| **Edge / Copilot (0xc000007b)** | Missing/bad Edge, WebView2, VC++ x64, or Copilot AppX | Force-repair via winget + reset/re-register Copilot AppX |

## NinjaOne requirements

- NinjaOne agent on target devices
- Scripts run as **System**
- winget / App Installer for app repairs

## Deployment

1. **Administration → Library → Automation → Add → New Script**
2. Language: **PowerShell**
3. Paste `Edge-Copilot-Repair/NinjaOne-DetectAndRepair.ps1` (or another remediation)
4. Run on-demand, via policy schedule, or from a condition
5. Run as **System**, timeout **30+ minutes** for Edge/Copilot repair

See [NINJAONE-DEPLOYMENT.md](NINJAONE-DEPLOYMENT.md) for step-by-step instructions.

## Local Testing

```powershell
.\Edge-Copilot-Repair\Detection.ps1
# Exit 0 = OK, Exit 1 = needs fix

# Elevated:
.\Edge-Copilot-Repair\Remediation.ps1
# Or the NinjaOne one-shot:
.\Edge-Copilot-Repair\NinjaOne-DetectAndRepair.ps1
```

## Logging & Monitoring

- Local: `C:\ProgramData\Remediation\Logs\`
- NinjaOne: device **Activities** / script results
- Optional: `Remediation Report` to aggregate local logs

## Security

- Prefer **System** context in NinjaOne
- No credentials in scripts
- Pilot on a small device set before org-wide policy
