<#
.SYNOPSIS
    BT-IRK-Extractor - Extracts Bluetooth Identity Resolving Keys (IRKs) from Windows registry
.DESCRIPTION
    This script extracts Bluetooth IRK values for paired devices by accessing the Windows registry
    with SYSTEM privileges using PsExec. It helps retrieve encryption keys necessary for spoofing
    Bluetooth Low Energy (BLE) devices.
.NOTES
    Author: Ediiiz
    Version: 1.0
    GitHub: https://github.com/ediiiz/BT-IRK-Extractor
#>

function Show-Banner {
  Write-Host "`n============================================================" -ForegroundColor Cyan
  Write-Host "             Bluetooth IRK Extractor Tool                   " -ForegroundColor Cyan
  Write-Host "============================================================" -ForegroundColor Cyan
  Write-Host "Extracts Identity Resolving Keys (IRKs) for BLE devices" -ForegroundColor Yellow
  Write-Host "https://github.com/ediiiz/BT-IRK-Extractor" -ForegroundColor Yellow
  Write-Host "============================================================`n" -ForegroundColor Cyan
}

function Test-Admin {
  $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PsExec {
  $psExecPath = "$env:TEMP\PsExec.exe"
  $psExecUrl = "https://live.sysinternals.com/PsExec.exe"
  
  Write-Host "Downloading PsExec..." -ForegroundColor Yellow
  try {
    Invoke-WebRequest -Uri $psExecUrl -OutFile $psExecPath -ErrorAction Stop
    Write-Host "PsExec downloaded successfully!" -ForegroundColor Green
    return $psExecPath
  }
  catch {
    Write-Host "Failed to download PsExec: $_" -ForegroundColor Red
    return $null
  }
}

function Get-BluetoothIRKs {
  param (
    [string]$PsExecPath
  )

  Write-Host "Creating temporary registry export script..." -ForegroundColor Yellow
  $tempScriptPath = "$env:TEMP\ExportBTRegistry.ps1"
  $regExportPath = "$env:TEMP\BTKeys.reg"

  $exportScript = @"
`$regPath = 'HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys'
reg export `$regPath "$regExportPath" /y
"@

  Set-Content -Path $tempScriptPath -Value $exportScript

  Write-Host "Launching PsExec to access registry with SYSTEM privileges..." -ForegroundColor Yellow
  try {
    Start-Process -FilePath $PsExecPath -ArgumentList "-i -s -accepteula powershell -ExecutionPolicy Bypass -File `"$tempScriptPath`"" -Wait -NoNewWindow
  }
  catch {
    Write-Host "Error executing PsExec: $_" -ForegroundColor Red
    return
  }

  if (-not (Test-Path $regExportPath)) {
    Write-Host "Registry export failed - file not created." -ForegroundColor Red
    return
  }

  Write-Host "Processing exported registry data..." -ForegroundColor Yellow
  $regContent = Get-Content -Path $regExportPath -Raw

  # Define regex patterns to find Bluetooth adapters and their paired devices
  $adapterPattern = '^\[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys\\([a-fA-F0-9]+)\]'
  $devicePattern = '^\[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys\\[a-fA-F0-9]+\\([a-fA-F0-9]+)\]'
  $irkPattern = '"IRK"=hex:([a-fA-F0-9,]+)'

  $adapters = [regex]::Matches($regContent, $adapterPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline) | 
  ForEach-Object { $_.Groups[1].Value }
  
  Write-Host "`nFound Bluetooth adapter(s):" -ForegroundColor Green
  foreach ($adapter in $adapters) {
    Write-Host " - $adapter" -ForegroundColor Cyan
  }
  
  $results = @()
  
  foreach ($adapter in $adapters) {
    Write-Host "`nPaired devices for adapter ${adapter}:" -ForegroundColor Green
      
    $deviceSectionPattern = "^\[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys\\$adapter\\([a-fA-F0-9]+)\]"
    $devices = [regex]::Matches($regContent, $deviceSectionPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline) | 
    ForEach-Object { $_.Groups[1].Value }
      
    foreach ($device in $devices) {
      $deviceSection = [regex]::Match($regContent, "(?s)\[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys\\$adapter\\$device\].*?(?=\[|$)").Value
      $irkMatch = [regex]::Match($deviceSection, $irkPattern)
          
      if ($irkMatch.Success) {
        $irkHex = $irkMatch.Groups[1].Value -replace ',', ''
        $nameMatch = [regex]::Match($deviceSection, '"Name"="([^"]+)"')
        $name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { "Unknown Device" }
              
        $deviceInfo = [PSCustomObject]@{
          AdapterMAC = $adapter -replace '(.{2})(?=.)', '$1:'
          DeviceMAC  = $device -replace '(.{2})(?=.)', '$1:'
          DeviceName = $name
          IRK        = $irkHex
        }
              
        $results += $deviceInfo
              
        Write-Host "  Device: $device" -ForegroundColor White
        Write-Host "  Name: $name" -ForegroundColor White
        Write-Host "  IRK: $irkHex" -ForegroundColor Magenta
        Write-Host ""
      }
    }
  }
  
  # Display results in a formatted table
  if ($results.Count -gt 0) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "                    IRK Results Summary                     " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
      
    $results | Format-Table -Property DeviceName, DeviceMAC, IRK -AutoSize
      
    # Export results to CSV
    $csvPath = "$env:USERPROFILE\Desktop\BluetoothIRKs.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Results exported to: $csvPath" -ForegroundColor Green
  }
  else {
    Write-Host "No Bluetooth devices with IRK keys were found." -ForegroundColor Yellow
  }
  
  # Cleanup
  Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
  Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
  Remove-Item -Path $regExportPath -Force -ErrorAction SilentlyContinue
  
  return $results
}

# Main execution
Show-Banner

if (-not (Test-Admin)) {
  Write-Host "This script requires administrator privileges. Please run as administrator." -ForegroundColor Red
  exit
}

$psExecPath = Get-PsExec
if ($psExecPath) {
  $results = Get-BluetoothIRKs -PsExecPath $psExecPath
  
  # Additional summary display
  if ($results -and $results.Count -gt 0) {
    Write-Host "`nSummary of extracted IRKs:" -ForegroundColor Green
    Write-Host "Total devices found: $($results.Count)" -ForegroundColor Yellow
      
    # Generate a colorized list of devices
    foreach ($device in $results) {
      Write-Host "• $($device.DeviceName)" -ForegroundColor Cyan -NoNewline
      Write-Host " - MAC: $($device.DeviceMAC)" -ForegroundColor White
    }
  }
}
else {
  Write-Host "Cannot continue without PsExec. Exiting." -ForegroundColor Red
  exit
}

Write-Host "`nBluetooth IRK extraction complete!" -ForegroundColor Green
Write-Host "Use these IRK values for your Bluetooth security testing." -ForegroundColor Yellow
