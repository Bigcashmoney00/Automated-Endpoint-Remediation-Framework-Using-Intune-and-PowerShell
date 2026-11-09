# Intune Proactive Remediation Deployment Guide

## Prerequisites

- **Microsoft Intune** (MEM) subscription
- **Endpoint analytics** or **Proactive remediations** capability
  - Included with: Intune Plan 2, Microsoft 365 E3/E5, or standalone add-on
- Devices enrolled in Intune (MDM-managed)

## Deploying a Remediation Script Package

### Step 1: Navigate to Proactive Remediations

1. Sign in to [Microsoft Intune admin center](https://endpoint.microsoft.com)
2. Go to **Reports** → **Endpoint analytics** → **Proactive remediations**
3. Click **+ Create script package**

### Step 2: Basics

- **Name**: e.g., `Windows Update Service - Remediation`
- **Description**: e.g., `Ensures Windows Update service is running and set to Automatic`

### Step 3: Detection Script

1. Click **Next** to open the Detection script tab
2. Paste the contents of `Detection.ps1` (e.g., `remediations/WindowsUpdate-Service/Detection.ps1`)
3. Ensure script runs in **64-bit** PowerShell (default)
4. Click **Next**

### Step 4: Remediation Script

1. Paste the contents of `Remediation.ps1`
2. Click **Next**

### Step 5: Assignments

1. Select the device groups to target (e.g., All Devices, or a pilot group)
2. Click **Next**

### Step 6: Schedule

- **Run script every**: e.g., 8 hours
- **Run script as**: 64-bit (default)
- Click **Next** → **Create**

## Script Package Mapping

| Remediation         | Detection Script                               | Remediation Script                              |
|---------------------|------------------------------------------------|-------------------------------------------------|
| Windows Update      | `remediations/WindowsUpdate-Service/Detection.ps1`  | `remediations/WindowsUpdate-Service/Remediation.ps1`  |
| Registry Security   | `remediations/Registry-Security/Detection.ps1`     | `remediations/Registry-Security/Remediation.ps1`     |
| Defender Status     | `remediations/Defender-Status/Detection.ps1`       | `remediations/Defender-Status/Remediation.ps1`       |
| Required Apps       | `remediations/Required-Apps/Detection.ps1`         | `remediations/Required-Apps/Remediation.ps1`         |
| Edge / Copilot Repair | `Edge-Copilot-Repair/Detection.ps1`              | `Edge-Copilot-Repair/Remediation.ps1`               |

### Edge / Copilot `0xc000007b` notes

- Error `0xc000007b` (`STATUS_INVALID_IMAGE_FORMAT`) usually means a bad/mismatched binary (often VC++ CRT or Edge `msedge.dll`), not that Windows itself must be reinstalled.
- Copilot is an AppX host that loads Edge/WebView2 components; repairing Edge + WebView2 + VC++ x64, then resetting the Copilot package, fixes most cases without wiping the OS.
- Registry: detection clears `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot\TurnOffWindowsCopilot` when set to `1`. Per-user Copilot shell keys under `HKCU` are applied only when the script runs interactively (not as SYSTEM).
- After remediation, reboot once if Copilot still fails to start.

## How It Works

1. **Detection runs** on schedule (e.g., every 8 hours)
2. **Exit 0** = Compliant → No remediation runs
3. **Exit 1** = Non-compliant → Remediation runs immediately
4. Output is sent to Intune and visible per-device

## Viewing Results

1. Go to **Reports** → **Endpoint analytics** → **Proactive remediations**
2. Select a script package
3. View **Device status** for each device:
   - Detection output
   - Remediation output (if ran)
   - Last run time

## Best Practices

- **Pilot first**: Assign to a small device group before rolling out
- **Schedule**: 8–12 hours is typical; avoid too frequent (load) or too rare (slow fix)
- **Timeout**: Scripts have a 30-minute timeout in Intune
- **No user interaction**: Scripts run in SYSTEM context; no UI allowed
- **Idempotent**: Remediation should be safe to run multiple times

## Troubleshooting

| Issue | Action |
|-------|--------|
| Script not running | Check device enrollment, assignment, and sync |
| Detection always non-compliant | Run Detection.ps1 locally; check exit code and output |
| Remediation fails | Run Remediation.ps1 as admin locally; check logs in `C:\ProgramData\Remediation\Logs` |
| Output not visible | Ensure Write-Output is used (not Write-Host) for key messages |
