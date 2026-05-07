<#
Repair-LocalHybridRegistration.ps1

Release Notes:
1) Device-side remediation for broken Windows LAPS hybrid Entra registration
2) Two-phase flow with mandatory restart between phases
3) Run -Action Leave first, restart, then -Action Join, restart again
4) Wait 15 to 24 hours for the background Automatic-Device-Join task to complete

Usage examples:

Phase 1 (clear local registration):
.\Repair-LocalHybridRegistration.ps1 -Action Leave
# (restart the device, sign in, then continue)

Phase 2 (force fresh join):
.\Repair-LocalHybridRegistration.ps1 -Action Join
# (restart the device, then wait 15 to 24 hours)

Inspect current registration state:
.\Repair-LocalHybridRegistration.ps1 -Action Status
#>

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("Leave","Join","Status")]
  [string]$Action
)

# ----------------------------
# Helpers
# ----------------------------

function Test-IsAdmin {
  $current   = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ----------------------------
# Main
# ----------------------------

if ($Action -ne 'Status' -and -not (Test-IsAdmin)) {
  Write-Host "ERROR: This action requires local administrator rights." -ForegroundColor Red
  Write-Host "Re-run from an elevated PowerShell session."
  exit 1
}

switch ($Action) {

  "Leave" {
    Write-Host "============================================================="
    Write-Host "Phase 1 of 2: clearing local hybrid Entra registration state"
    Write-Host "============================================================="
    Write-Host ""
    Write-Host "Running: dsregcmd /leave"
    & dsregcmd /leave
    Write-Host ""
    Write-Host "Phase 1 complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:"
    Write-Host "  1. Restart this PC now."
    Write-Host "  2. After restart, sign in normally with your domain credentials."
    Write-Host "  3. Re-run this script with: -Action Join"
    Write-Host ""
  }

  "Join" {
    Write-Host "============================================================="
    Write-Host "Phase 2 of 2: forcing fresh hybrid Entra registration"
    Write-Host "============================================================="
    Write-Host ""
    Write-Host "Running: dsregcmd /join"
    & dsregcmd /join
    Write-Host ""
    Write-Host "Phase 2 complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "EXPECTED BEHAVIOUR:"
    Write-Host "  dsregcmd /status will show AzureAdJoined: NO immediately after this."
    Write-Host "  This is normal. The Automatic-Device-Join scheduled task retries"
    Write-Host "  in the background and registration completes within 15 to 24 hours."
    Write-Host "  Do NOT re-run this procedure during the wait window."
    Write-Host ""
    Write-Host "NEXT STEPS:"
    Write-Host "  1. Restart this PC now."
    Write-Host "  2. Wait 15 to 24 hours."
    Write-Host "  3. From the admin workstation, run Confirm-LAPSEscrowRecovery.ps1"
    Write-Host ""
  }

  "Status" {
    Write-Host "Current local hybrid Entra registration state:"
    Write-Host "============================================================="
    & dsregcmd /status
  }
}
