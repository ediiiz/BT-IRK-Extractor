```powershell
# BT-IRK-Extractor.ps1
# A self-contained script to extract Bluetooth IRK keys from the registry.
# Requires Administrator privileges.

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ( -not $isAdmin ) {
  Write-Host "This script requires Administrator privileges. Please run PowerShell as Administrator." -ForegroundColor Red
  exit
}

# Set up working directory (in TEMP)
$workingDir = "$env:TEMP\BTIRKExtract"
if ( -not (Test-Path -Path $workingDir)) {
  New-Item -Path $workingDir -ItemType Directory -Force | Out-Null
}
Write-Host "Working directory: $workingDir" -ForegroundColor Cyan

# Define file paths
$psExecPath = "$workingDir\PsExec64.exe"
$regExportPath = "$workingDir\BTKeys.reg"
$outputJsonPath = "$workingDir\irk_results.json"
$systemScriptPath = "$workingDir\system_command.ps1"

# Download PsExec if needed
if ( -not (Test-Path -Path $psExecPath) ) {
  Write-Host "Downloading PsExec64.exe..." -ForegroundColor Yellow
  $psExecUrl = "https://download.sysinternals.com/files/PSTools.zip"
  $zipPath = "$workingDir\PSTools.zip"
    
  # Download the PSTools zip file
  Invoke-WebRequest -Uri $psExecUrl -OutFile $zipPath -UseBasicParsing

  # Extract PsExec64.exe from the zip file
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  $entry = $zip.Entries | Where-Object { $_.Name -eq "PsExec64.exe" }
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $psExecPath, $true)
  $zip.Dispose()
    
  # Clean up the zip file
  Remove-Item -Path $zipPath -Force
  Write-Host "PsExec64.exe downloaded successfully to $psExecPath" -ForegroundColor Green
}

# Create a template for the system script that will run as SYSTEM.
# We use a single-quoted here-string to avoid unwanted interpolation.
# (Placeholders {{REG_EXPORT_PATH}} and {{OUTPUT_JSON_PATH}} will be replaced below.)
$systemScriptTemplate = @'
# Extraction script running as SYSTEM
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$regExportPath = "{{REG_EXPORT_PATH}}"
$outputJsonPath = "{{OUTPUT_JSON_PATH}}"
$deviceData = @()

function Get-BTDeviceName {
    param (
        [string]$deviceMac
    )
    # Try standard Bluetooth registry locations
    $possiblePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$deviceMac",
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTH\Parameters\Devices\$deviceMac"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $nameValue = Get-ItemProperty -Path $path -Name "Name" -ErrorAction SilentlyContinue
            if ($nameValue -and $nameValue.Name) {
                return $nameValue.Name
            }
        }
    }
    # Try to get from device manager friendly names
    $deviceClasses = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum" -ErrorAction SilentlyContinue
    foreach ($class in $deviceClasses) {
        $devices = Get-ChildItem $class.PSPath -ErrorAction SilentlyContinue
        foreach ($device in $devices) {
            $properties = Get-ItemProperty $device.PSPath -ErrorAction SilentlyContinue
            if ($properties.FriendlyName -and $properties.HardwareID) {
                $hwId = $properties.HardwareID | Where-Object { $_ -match $deviceMac }
                if ($hwId) {
                    return $properties.FriendlyName
                }
            }
        }
    }
    return "Unknown Device"
}

if (Test-Path -Path $regPath) {
    $adapterKeys = Get-ChildItem -Path $regPath
    if ($adapterKeys.Count -gt 0) {
        foreach ($adapter in $adapterKeys) {
            $deviceKeys = Get-ChildItem -Path $adapter.PSPath
            if ($deviceKeys.Count -gt 0) {
                foreach ($device in $deviceKeys) {
                    $deviceMac = $device.PSChildName
                    $deviceName = Get-BTDeviceName -deviceMac $deviceMac

                    # Export registry key for this device
                    $exportCmd = "reg export `"$($device.PSPath.Replace('Microsoft.PowerShell.Core\Registry::',''))`" `"$regExportPath`" /y"
                    cmd /c $exportCmd | Out-Null

                    # Read exported .reg file and extract the IRK value
                    $content = Get-Content -Path $regExportPath -Raw
                    if ($content -match 'IRK"=hex:([0-9a-f,]+)') {
                        $irkWithCommas = $matches[1]
                        $irk = $irkWithCommas -replace ',', ''
                        $deviceObj = [PSCustomObject]@{
                            DeviceName = $deviceName
                            DeviceMAC  = $deviceMac
                            AdapterMAC = $adapter.PSChildName
                            IRK        = $irk
                        }
                        $deviceData += $deviceObj
                    }
                }
            }
        }
        if ($deviceData.Count -gt 0) {
            $deviceData | ConvertTo-Json | Out-File -FilePath $outputJsonPath -Force
        }
    }
}
'@

# Replace placeholders with the actual paths.
# Note: Use the -replace operator (no formatting needed).
$systemScript = $systemScriptTemplate -replace "\{\{REG_EXPORT_PATH\}\}", $regExportPath `
  -replace "\{\{OUTPUT_JSON_PATH\}\}", $outputJsonPath

# Write the final system script to a file
Set-Content -Path $systemScriptPath -Value $systemScript -Force
Write-Host "System script written to: $systemScriptPath" -ForegroundColor Cyan

# Execute the system script as SYSTEM using PsExec
Write-Host "Extracting Bluetooth IRK keys (please wait)..." -ForegroundColor Yellow
$psExecArgs = "-accepteula -i -s powershell.exe -ExecutionPolicy Bypass -File `"$systemScriptPath`""
Start-Process -FilePath $psExecPath -ArgumentList $psExecArgs -Wait -NoNewWindow

# Allow a short pause for the extraction to complete
Start-Sleep -Seconds 2

# Read and display the results
if (Test-Path $outputJsonPath) {
  try {
    $irkData = Get-Content -Path $outputJsonPath -Raw | ConvertFrom-Json

    if ($irkData -and $irkData.Count -gt 0) {
      # Group by adapter for display
      $adapterGroups = $irkData | Group-Object -Property AdapterMAC

      Write-Host "`nBluetooth IRK Keys:" -ForegroundColor Cyan
      Write-Host "=================" -ForegroundColor Cyan

      foreach ($adapterGroup in $adapterGroups) {
        Write-Host "`nBluetooth Adapter: $($adapterGroup.Name)" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan

        foreach ($device in $adapterGroup.Group) {
          Write-Host "Device: $($device.DeviceName) [$($device.DeviceMAC)]" -ForegroundColor Yellow
          Write-Host "IRK: $($device.IRK)" -ForegroundColor Green
          Write-Host ""
        }
      }

      # (Optional) Save results to Desktop if desired.
      $userInput = Read-Host "Do you want to save these results to the desktop? (y/n)"
      if ($userInput.ToLower() -eq 'y') {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $outputCsv = "$desktopPath\BluetoothIRK_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $irkData | Export-Csv -Path $outputCsv -NoTypeInformation
        Write-Host "Results saved to: $outputCsv" -ForegroundColor Green
      }
    }
    else {
      Write-Host "No Bluetooth devices with IRK keys were found." -ForegroundColor Yellow
    }
  }
  catch {
    Write-Host "Error processing results: $_" -ForegroundColor Red
    Write-Host "No Bluetooth devices with IRK keys were found." -ForegroundColor Yellow
  }
  # Clean up the results JSON
  Remove-Item -Path $outputJsonPath -Force -ErrorAction SilentlyContinue
}
else {
  Write-Host "No Bluetooth devices with IRK keys were found." -ForegroundColor Yellow
}

Write-Host "`nBluetooth IRK extraction complete." -ForegroundColor Green

# Optionally, clean up temporary files (except PsExec64.exe)
Remove-Item -Path $regExportPath, $systemScriptPath -Force -ErrorAction SilentlyContinue
```
