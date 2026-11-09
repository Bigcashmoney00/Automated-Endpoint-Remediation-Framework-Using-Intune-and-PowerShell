# NinjaOne Deployment Guide

These remediations are meant to run from **NinjaOne** (Automation Library / policies / on-demand), not Intune.

## Prerequisites

- Devices with the **NinjaOne agent** online
- Script run context: **System** (needed for Edge / AppX / machine policy)
- **App Installer / winget** present on endpoints (required for Edge, WebView2, VC++ repair)
- For Copilot AppX reset: Windows 10/11 with Store / AppX packages enabled

## Add a script to NinjaOne

1. In NinjaOne go to **Administration → Library → Automation**
2. **Add → New Script**
3. Set:
   - **Name**: e.g. `Edge-Copilot 0xc000007b Repair`
   - **Language**: PowerShell
   - **Script**: paste contents of `Edge-Copilot-Repair/NinjaOne-DetectAndRepair.ps1`
4. Save

## Run options

### On-demand (ticket / single device)

1. Open the device in NinjaOne
2. **Run** → choose `Edge-Copilot 0xc000007b Repair`
3. Run as **System**
4. Set timeout to **30+ minutes**
5. Review activity output / exit code

### Scheduled (policy)

1. Edit the **Windows policy** for the org/group
2. Add a **Scheduled script** / automation
3. Select the Edge-Copilot repair script
4. Schedule (e.g. weekly) or tie to a maintenance window
5. Run as **System**

### Condition → remediation (detect then fix)

1. Add `Edge-Copilot-Repair/Detection.ps1` as a script used by a **condition**
   - Exit **1** = unhealthy (condition true)
   - Exit **0** = healthy
2. Attach `NinjaOne-DetectAndRepair.ps1` (or `Remediation.ps1`) as the **automation** when the condition fires

## Script map

| Goal | Script |
|------|--------|
| Single NinjaOne paste (recommended) | `Edge-Copilot-Repair/NinjaOne-DetectAndRepair.ps1` |
| Health check only | `Edge-Copilot-Repair/Detection.ps1` |
| Repair only | `Edge-Copilot-Repair/Remediation.ps1` |
| Other remediations | `WindowsUpdate-Service`, `Registry-Security`, `Defender-Status`, `Required-Apps` |

## Edge / Copilot `0xc000007b` notes

- `0xc000007b` = `STATUS_INVALID_IMAGE_FORMAT` — usually bad/mismatched binaries (VC++ CRT, Edge `msedge.dll`, WebView2), not a reason to reinstall Windows.
- Copilot loads Edge/WebView2 components; repairing those plus resetting the Copilot AppX package fixes most cases.
- Script clears `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot\TurnOffWindowsCopilot` when set to `1`.
- Logs: `C:\ProgramData\Remediation\Logs\Remediation-YYYYMMDD.log`
- If Copilot still fails after a successful run, **reboot once** and re-test.

## Other remediations in this repo

Same pattern: paste `Remediation.ps1` (or Detection + condition) into the Automation Library and run as System via policy or on-demand.

| Remediation | Detection | Remediation |
|-------------|-----------|-------------|
| Windows Update service | `WindowsUpdate-Service/Detection.ps1` | `WindowsUpdate-Service/Remediation.ps1` |
| Registry security | `Registry-Security/Detection.ps1` | `Registry-Security/Remediation.ps1` |
| Defender status | `Defender-Status/Detection.ps1` | `Defender-Status/Remediation.ps1` |
| Required apps | `Required-Apps/Detection.ps1` | `Required-Apps/Remediation.ps1` |
| Edge / Copilot repair | `Edge-Copilot-Repair/Detection.ps1` | `Edge-Copilot-Repair/NinjaOne-DetectAndRepair.ps1` |

## Troubleshooting

| Issue | Action |
|-------|--------|
| Script fails immediately | Confirm run as **System**, not Current User |
| `winget not found` | Install/update **App Installer** on the device, then re-run |
| Exit 0 but Copilot still broken | Reboot; confirm no GPO sets `TurnOffWindowsCopilot=1` again |
| Long runtime | Normal for winget force-repair; keep timeout ≥ 30 minutes |
| Need output | Open device **Activities** / script result in NinjaOne; also check `C:\ProgramData\Remediation\Logs` |
