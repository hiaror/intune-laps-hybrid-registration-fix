<#
Test-HybridLAPSRegistration.ps1

Release Notes:
1) Diagnoses Windows LAPS hybrid Entra registration health for one or more devices
2) Surfaces alternativeSecurityIds and registrationDateTime via the Graph beta endpoint
3) Identifies the signature of broken hybrid registration that silently blocks LAPS escrow
4) CSV-driven for batch diagnostics across many devices

Usage examples (SANITIZED):

Diagnose a batch of devices:
.\Test-HybridLAPSRegistration.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -DevicesCsv ".\sample-data\Devices.sample.csv"

Diagnose a single device by name:
.\Test-HybridLAPSRegistration.ps1 `
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
  [string]$ReportPath = (Join-Path $PWD ("HybridLAPSRegistration_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss")))
)

# ----------------------------
# Helpers
# ----------------------------

function Connect-EntraGraph {
  param([Parameter(Mandatory=$true)][string]$TenantId)
  Set-MgGraphOption -DisableLoginByWAM $true | Out-Null
  Connect-MgGraph -TenantId $TenantId -Scopes "Device.Read.All" -NoWelcome
}

function Get-AllEntraDevices {
  $allEntraDevices = New-Object System.Collections.Generic.List[object]
  $uri = "https://graph.microsoft.com/v1.0/devices"
  do {
    $r = Invoke-MgGraphRequest -Method GET -Uri $uri
    foreach ($d in $r.value) { [void]$allEntraDevices.Add($d) }
    $uri = $r.'@odata.nextLink'
  } while ($uri)
  return ,$allEntraDevices
}

function Get-EntraDeviceDetail {
  param([Parameter(Mandatory=$true)][string]$ObjectId)
  $u = "https://graph.microsoft.com/beta/devices/$ObjectId" + `
       "?`$select=displayName,deviceId,trustType," + `
       "registrationDateTime,alternativeSecurityIds," + `
       "approximateLastSignInDateTime,accountEnabled,createdDateTime"
  return Invoke-MgGraphRequest -Method GET -Uri $u
}

function Get-Diagnosis {
  param([Parameter(Mandatory=$true)]$Detail)

  if (-not $Detail['accountEnabled']) { return 'Disabled' }
  $hasReg = [bool]$Detail['registrationDateTime']
  $hasAlt = [bool]$Detail['alternativeSecurityIds']
  if ($hasReg -and $hasAlt) { return 'Healthy' }
  if (-not $hasReg -and -not $hasAlt) { return 'BrokenRegistration' }
  return 'PartialRegistration'
}

# ----------------------------
# Main
# ----------------------------

# Build target list from chosen parameter set
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
Write-Host "Targets: $($targetNames.Count) device(s)"

Connect-EntraGraph -TenantId $TenantId

Write-Host "Pulling all Entra device objects (paginated)..."
$allEntraDevices = Get-AllEntraDevices
Write-Host "  Total Entra device objects: $($allEntraDevices.Count)"
Write-Host ""

$report = New-Object System.Collections.Generic.List[object]

foreach ($name in $targetNames) {
  $matching = @($allEntraDevices | Where-Object { $_['displayName'] -eq $name })

  if ($matching.Count -eq 0) {
    Write-Host "$name : NotFoundInEntra" -ForegroundColor Yellow
    $report.Add([pscustomobject]@{
      DeviceName = $name
      TrustType  = ""
      Registered = ""
      HasAltSec  = ""
      Created    = ""
      LastSignIn = ""
      Enabled    = ""
      Diagnosis  = "NotFoundInEntra"
    }) | Out-Null
    continue
  }

  if ($matching.Count -gt 1) {
    Write-Host "$name : $($matching.Count) Entra objects (likely duplicate)" -ForegroundColor Yellow
  }

  foreach ($m in $matching) {
    $detail = Get-EntraDeviceDetail -ObjectId $m['id']
    $diagnosis = Get-Diagnosis -Detail $detail

    $colour = switch ($diagnosis) {
      'Healthy'             { 'Green'  }
      'BrokenRegistration'  { 'Red'    }
      'PartialRegistration' { 'Yellow' }
      'Disabled'            { 'Yellow' }
      default               { 'White'  }
    }

    Write-Host "$name : $diagnosis (TrustType=$($detail['trustType']))" -ForegroundColor $colour

    $report.Add([pscustomobject]@{
      DeviceName = $detail['displayName']
      TrustType  = $detail['trustType']
      Registered = if ($detail['registrationDateTime']) { 'YES' } else { 'NO-PENDING' }
      HasAltSec  = if ($detail['alternativeSecurityIds']) { 'YES' } else { 'NO' }
      Created    = $detail['createdDateTime']
      LastSignIn = $detail['approximateLastSignInDateTime']
      Enabled    = $detail['accountEnabled']
      Diagnosis  = $diagnosis
    }) | Out-Null
  }
}

$report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

# Summary
Write-Host ""
Write-Host "============================================================="
Write-Host "Diagnosis Summary"
Write-Host "============================================================="
$report | Group-Object Diagnosis | Sort-Object Name | ForEach-Object {
  Write-Host ("{0,-22} : {1}" -f $_.Name, $_.Count)
}
Write-Host "============================================================="
Write-Host "Report saved to: $ReportPath"
