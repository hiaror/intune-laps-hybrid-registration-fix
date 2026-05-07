<#
Confirm-LAPSEscrowRecovery.ps1

Release Notes:
1) Post-remediation verification that target devices are escrowing LAPS to Entra ID
2) Run from the admin workstation against Microsoft Graph
3) Recommended timing: the morning after Repair-LocalHybridRegistration.ps1 -Action Join + restart
4) Writes a timestamped CSV with per-device escrow status

Usage examples (SANITIZED):

Verify escrow for a batch of devices:
.\Confirm-LAPSEscrowRecovery.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DevicesCsv ".\sample-data\Devices.sample.csv"

Verify a single device:
.\Confirm-LAPSEscrowRecovery.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DeviceName "CORP-PC-001"
#>

[CmdletBinding(DefaultParameterSetName='Csv')]
param(
  [Parameter(Mandatory=$true)]
  [string]$TenantId,

  [Parameter(Mandatory=$true, ParameterSetName='Csv')]
  [string]$DevicesCsv,

  [Parameter(Mandatory=$true, ParameterSetName='Single')]
  [string]$DeviceName,

  [Parameter(Mandatory=$false)]
  [string]$ReportPath = (Join-Path $PWD ("LAPSEscrowRecovery_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss")))
)

# ----------------------------
# Helpers
# ----------------------------

function Connect-LAPSGraph {
  param([Parameter(Mandatory=$true)][string]$TenantId)
  Set-MgGraphOption -DisableLoginByWAM $true | Out-Null
  Connect-MgGraph -TenantId $TenantId -Scopes "DeviceLocalCredential.ReadBasic.All" -NoWelcome
}

# ----------------------------
# Main
# ----------------------------

# Build target list
$targetNames = @()
if ($PSCmdlet.ParameterSetName -eq 'Csv') {
  if (-not (Test-Path $DevicesCsv)) { throw "Devices CSV not found: $DevicesCsv" }
  $targetNames = (Import-Csv $DevicesCsv) |
    ForEach-Object { (($_.DeviceName) + "").Trim() } |
    Where-Object { $_ }
} else {
  $targetNames = @($DeviceName)
}

$targetNames = $targetNames | Select-Object -Unique

Connect-LAPSGraph -TenantId $TenantId

$response = Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials"

$report = New-Object System.Collections.Generic.List[object]

Write-Host "Verifying escrow status for $($targetNames.Count) device(s):"
Write-Host "============================================================="

foreach ($d in $targetNames) {
  $found = $response.value | Where-Object { $_['deviceName'] -eq $d }
  if ($found) {
    Write-Host ("{0} : ESCROWED at {1}" -f $d, $found['lastBackupDateTime']) -ForegroundColor Green
    $report.Add([pscustomobject]@{
      DeviceName = $d
      Status     = "ESCROWED"
      LastBackup = $found['lastBackupDateTime']
    }) | Out-Null
  } else {
    Write-Host ("{0} : Not yet escrowed" -f $d) -ForegroundColor Yellow
    $report.Add([pscustomobject]@{
      DeviceName = $d
      Status     = "NOT_YET_ESCROWED"
      LastBackup = ""
    }) | Out-Null
  }
}

Write-Host "============================================================="
$report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Host "Report saved to: $ReportPath"
