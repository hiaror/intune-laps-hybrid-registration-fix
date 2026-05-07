# Hybrid Entra LAPS Registration Repair

## Overview
This repository contains a PowerShell toolset for diagnosing and remediating Windows LAPS escrow failures caused by **broken hybrid Entra ID device registration**, where a device is Intune-enrolled and policy-applied but cannot escrow its LAPS password because Entra never completed Stage 2 of hybrid join.

The toolset uses Microsoft Graph for diagnostics and `dsregcmd` for device-side remediation. Scripts and procedures are based on a verified end-to-end remediation that was confirmed working in production within approximately 15 hours of the leave-and-rejoin sequence.

## Why This Exists

In hybrid Entra environments, devices can end up in a half-registered state after Entra Connect sync incidents, security group reorganisations, or scoped object recreations. The Entra device object exists, the on-premises AD computer object syncs cleanly, the device shows compliant in Intune, the LAPS policy reports as applied, but the device silently never escrows its password.

The diagnostic signature is:
- `dsregcmd /status` shows `DeviceAuthStatus: FAILED. Device is either disabled or deleted`
- The Entra device object has empty `registrationDateTime` and empty `alternativeSecurityIds`

The `alternativeSecurityIds` field is **not visible in the Entra portal UI**. It is only accessible via the Microsoft Graph beta endpoint. This toolset surfaces it, identifies the broken devices, and walks through the verified two-restart remediation procedure.

## Key Capabilities
- Identifies the diagnostic signature of broken hybrid registration: missing `alternativeSecurityIds`
- CSV-driven device targeting for batch diagnostics
- Per-device readout: TrustType, registrationDateTime, HasAltSec, LastSignIn, Enabled
- Device-side remediation script that wraps the `dsregcmd /leave` and `dsregcmd /join` flow with explicit phase guidance
- Post-remediation verification against Graph escrow records
- All Graph queries are read-only

## Repository Structure
```
.
├── scripts/
│   ├── Test-HybridLAPSRegistration.ps1
│   ├── Repair-LocalHybridRegistration.ps1
│   └── Confirm-LAPSEscrowRecovery.ps1
├── sample-data/
│   └── Devices.sample.csv
└── README.md
```

## Prerequisites
- `Microsoft.Graph` PowerShell SDK installed on the admin workstation
- Windows 11 24H2 (build `10.0.26100` or above) or Windows 11 23H2 (build `10.0.22631` or above) on target devices
- Local administrator rights on the target device for `dsregcmd` commands
- An admin account with these Graph scopes consented:
  - `Device.Read.All` (diagnostic)
  - `DeviceLocalCredential.ReadBasic.All` (post-remediation verification)

## CSV Input Format

### Devices CSV
```csv
DeviceName
CORP-PC-001
CORP-PC-002
CORP-PC-003
```

## Usage Examples

### Diagnose a Batch of Devices
```powershell
./Test-HybridLAPSRegistration.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DevicesCsv ".\sample-data\Devices.sample.csv"
```

### Diagnose a Single Device
```powershell
./Test-HybridLAPSRegistration.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DeviceName "CORP-PC-001"
```

### Run the Device-Side Repair (On the Affected Device)
```powershell
# Phase 1: clear local registration
.\Repair-LocalHybridRegistration.ps1 -Action Leave
# (restart the device, sign in)

# Phase 2: force fresh join
.\Repair-LocalHybridRegistration.ps1 -Action Join
# (restart the device, then wait 15 to 24 hours)
```

### Inspect the Local Registration State
```powershell
.\Repair-LocalHybridRegistration.ps1 -Action Status
```

### Verify Escrow After Remediation
```powershell
./Confirm-LAPSEscrowRecovery.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DevicesCsv ".\sample-data\Devices.sample.csv"
```

## Reporting
`Test-HybridLAPSRegistration.ps1` produces a timestamped CSV with one row per Entra device object found for each target name:
- DeviceName
- TrustType (`ServerAd`, `AzureAd`, or `Workplace`)
- Registered (`YES` or `NO-PENDING`)
- HasAltSec (`YES` or `NO`)
- Created
- LastSignIn
- Enabled
- Diagnosis (`Healthy`, `BrokenRegistration`, `PartialRegistration`, `Disabled`, or `NotFoundInEntra`)

`Confirm-LAPSEscrowRecovery.ps1` prints a per-device `ESCROWED` or `Not yet escrowed` line and writes the same to a timestamped CSV.

## Safety Notes

The diagnostic and verification scripts are read-only against Graph and Intune.

The repair script (`Repair-LocalHybridRegistration.ps1`) runs `dsregcmd /leave` and `dsregcmd /join` on the local device, which clears and re-establishes hybrid registration. This requires two restarts. The user should be signed out before the first restart.

`dsregcmd /status` will show `AzureAdJoined: NO` immediately after the procedure. **This is expected and normal.** Background `Automatic-Device-Join` task retries succeed within 15 to 24 hours. **Do not re-run the repair procedure during this window.** Verify escrow the following morning using `Confirm-LAPSEscrowRecovery.ps1`.

Always remediate during scheduled maintenance windows. Never on a device that is the user's only working machine without a fallback.

## Disclaimer
Provided as-is for reference and learning purposes. Sample data and identifiers are sanitized.
