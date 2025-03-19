# BT-IRK-Extractor.ps1
# A self-contained Bluetooth IRK Extraction Tool

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "This script requires Administrator privileges. Please run PowerShell as Administrator." -ForegroundColor Red
  exit
}

# Set up working directory
$workingDir = "$env:TEMP\BTIRKExtract"
if (-not (Test-Path -Path $workingDir)) {
  New-Item -Path $workingDir -ItemType Directory -Force | Out-Null
}

# Set up file paths
$psExecPath = "$workingDir\PsExec64.exe"
$regExportPath = "$workingDir\BTKeys.reg"
$outputJsonPath = "$workingDir\irk_results.json"
$systemScriptPath = "$workingDir\system_command.ps1"

# Download PsExec if needed
if (-not (Test-Path -Path $psExecPath)) {
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
    
  Write-Host "PsExec64.exe downloaded successfully" -ForegroundColor Green
}

# Create the system script file
$systemScript = @"
# Extraction script that runs as SYSTEM
`$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
`$regExportPath = "$regExportPath"
`$outputJsonPath = "$outputJsonPath"
`$deviceData = @()

# Function to get device name
function Get-BTDeviceName {
    param (
        [string]`$deviceMac
    )
    
    # Try standard Bluetooth registry locations
    `$possiblePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\`$deviceMac",
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTH\Parameters\Devices\`$deviceMac"
    )
    
    foreach (`$path in `$possiblePaths) {
        if (Test-Path `$path) {
            `$nameValue = Get-ItemProperty -Path `$path -Name "Name" -ErrorAction SilentlyContinue
            if (`$nameValue -and `$nameValue.Name) {
                return `$nameValue.Name
            }
        }
    }
    
    # Try to get from user-friendly names in device manager
    `$deviceClasses = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum" -ErrorAction SilentlyContinue
    foreach (`$class in `$deviceClasses) {
        `$devices = Get-ChildItem `$class.PSPath -ErrorAction SilentlyContinue
        foreach (`$device in `$devices) {
            `$properties = Get-ItemProperty `$device.PSPath -ErrorAction SilentlyContinue
            if (`$properties.FriendlyName -and `$properties.HardwareID) {
                `$hwId = `$properties.HardwareID | Where-Object { `$_ -match `$deviceMac }
                if (`$hwId) {
                    return `$properties.FriendlyName
                }
            }
        }
    }
    
    return "Unknown Device"
}

# Check if the registry path exists
if (Test-Path -Path `$regPath) {
    # Get the Bluetooth adapter MAC address subfolder
    `$adapterKeys = Get-ChildItem -Path `$regPath
    
    if (`$adapterKeys.Count -gt 0) {
        foreach (`$adapter in `$adapterKeys) {
            # Get device keys under this adapter
            `$deviceKeys = Get-ChildItem -Path `$adapter.PSPath
            
            if (`$deviceKeys.Count -gt 0) {
                foreach (`$device in `$deviceKeys) {
                    `$deviceMac = `$device.PSChildName
                    `$deviceName = Get-BTDeviceName -deviceMac `$deviceMac
                    
                    # Export this device key to .reg file
                    `$exportCmd = "reg export '`$(`$device.PSPath.Replace('Microsoft.PowerShell.Core\Registry::',''))' '`$regExportPath' /y"
                    cmd /c `$exportCmd | Out-Null
                    
                    # Read the exported REG file
                    `$content = Get-Content -Path `$regExportPath -Raw
                    
                    # Look for the IRK value
                    if (`$content -match 'IRK"=hex:([0-9a-f,]+)') {
                        `$irkWithCommas = `$matches[1]
                        `$irk = `$irkWithCommas -replace ',', ''
                        
                        # Add to device data
                        `$deviceObj = [PSCustomObject]@{
                            DeviceName = `$deviceName
                            DeviceMAC = `$deviceMac
                            AdapterMAC = `$adapter.PSChildName
                            IRK = `$irk
                        }
                        `$deviceData += `$deviceObj
                    }
                }
            }
        }
        
        # Save results to JSON file
        if (`$deviceData.Count -gt 0) {
            `$deviceData | ConvertTo-Json | Out-File -FilePath `$outputJsonPath -Force
        }
    }
}
"@

# Write the script to a file
Set-Content -Path $systemScriptPath -Value $systemScript

# Execute the command as SYSTEM using PsExec
Write-Host "Extracting Bluetooth IRK keys (please wait)..." -ForegroundColor Yellow
$psExecCommand = "$psExecPath -accepteula -i -s powershell.exe -ExecutionPolicy Bypass -File '$systemScriptPath'"
Invoke-Expression $psExecCommand

# Wait a moment for the process to complete
Start-Sleep -Seconds 2

# Read and display the results
if (Test-Path $outputJsonPath) {
  try {
    $irkData = Get-Content -Path $outputJsonPath -Raw | ConvertFrom-Json
        
    if ($irkData.Count -gt 0) {
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
            
      # Save results to user directory if desired
      $saveFiles = Read-Host "Do you want to save these results to the desktop? (y/n)"
      if ($saveFiles.ToLower() -eq 'y') {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $outputPath = "$desktopPath\BluetoothIRK_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $irkData | Export-Csv -Path $outputPath -NoTypeInformation
        Write-Host "Results saved to: $outputPath" -ForegroundColor Green
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
    
  # Clean up
  Remove-Item -Path $outputJsonPath -Force -ErrorAction SilentlyContinue
}
else {
  Write-Host "No Bluetooth devices with IRK keys were found." -ForegroundColor Yellow
}

Write-Host "`nBluetooth IRK extraction complete." -ForegroundColor Green

# Clean up temp files
Remove-Item -Path $regExportPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $systemScriptPath -Force -ErrorAction SilentlyContinue
