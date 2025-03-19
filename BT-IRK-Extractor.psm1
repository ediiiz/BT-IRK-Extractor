function Get-BluetoothIRK {
  [CmdletBinding()]
  param (
    [Parameter()]
    [switch]$SaveFiles,
        
    [Parameter()]
    [string]$OutputPath = "$env:USERPROFILE\BTIRKExtract"
  )
    
  Begin {
    # Check if script is running with admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
      throw "This function requires administrative privileges. Please run PowerShell as Administrator."
    }
        
    # Create or ensure working directory exists
    if ($SaveFiles -and -not (Test-Path -Path $OutputPath)) {
      New-Item -Path $OutputPath -ItemType Directory | Out-Null
      Write-Verbose "Created output directory: $OutputPath"
    }
        
    $psExecPath = "$OutputPath\PsExec64.exe"
    $regExportPath = "$OutputPath\BTKeys.reg"
    $resultsPath = "$OutputPath\IRK_Summary.csv"
        
    # Download PsExec if needed
    if (-not (Test-Path -Path $psExecPath)) {
      Write-Verbose "Downloading PsExec64.exe..."
            
      $psExecUrl = "https://download.sysinternals.com/files/PSTools.zip"
      $zipPath = "$OutputPath\PSTools.zip"
            
      # Download the PSTools zip file
      Invoke-WebRequest -Uri $psExecUrl -OutFile $zipPath
            
      # Extract PsExec64.exe from the zip file
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
      $entry = $zip.Entries | Where-Object { $_.Name -eq "PsExec64.exe" }
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $psExecPath, $true)
      $zip.Dispose()
            
      # Clean up the zip file
      Remove-Item -Path $zipPath -Force
            
      Write-Verbose "PsExec64.exe has been downloaded to $psExecPath"
    }
  }
    
  Process {
    # Create a temporary script to execute with SYSTEM privileges
    $tempScriptPath = "$OutputPath\ExportBTKeys.ps1"
    $deviceData = @()
    $saveFilesString = if ($SaveFiles) { "true" } else { "false" }
        
    $scriptContent = @"
# Script to export Bluetooth IRK keys with SYSTEM privileges
`$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
`$regExportPath = "$regExportPath"
`$resultsPath = "$resultsPath"
`$saveFiles = $saveFilesString
`$outputPath = "$OutputPath"
`$deviceData = @()

# Function to get device name from registry
function Get-BluetoothDeviceName {
    param (
        [string]`$deviceMac
    )
    
    # Try standard Bluetooth registry locations
    `$possiblePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$deviceMac",
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTH\Parameters\Devices\$deviceMac"
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
                    `$deviceName = Get-BluetoothDeviceName -deviceMac `$deviceMac
                    
                    # Export this device key to .reg file
                    `$exportCmd = "reg export `"`$(`$device.PSPath.Replace('Microsoft.PowerShell.Core\Registry::',''))`" `"`$regExportPath`" /y"
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
                        
                        # Save IRK to a separate file for each device if requested
                        if (`$saveFiles) {
                            `$irkFilePath = "`$outputPath\IRK_`$deviceMac.txt"
                            `$irk | Out-File -FilePath `$irkFilePath
                        }
                    }
                }
            }
        }
        
        # Export the results to CSV if requested
        if (`$saveFiles -and `$deviceData.Count -gt 0) {
            `$deviceData | Export-Csv -Path `$resultsPath -NoTypeInformation
        }
        
        # Return the data regardless
        `$deviceData | ConvertTo-Json -Compress | Out-File -FilePath "$outputPath\temp_results.json"
    }
}
"@

    Set-Content -Path $tempScriptPath -Value $scriptContent
        
    try {
      # Run PsExec to execute the script with SYSTEM privileges
      Write-Verbose "Extracting Bluetooth IRK values with SYSTEM privileges..."
      $psexecCommand = "& '$psExecPath' -accepteula -i -s powershell.exe -ExecutionPolicy Bypass -File '$tempScriptPath' -WindowStyle Hidden"
      $null = Invoke-Expression $psexecCommand
            
      # Wait for completion
      Start-Sleep -Seconds 2
            
      # Read back the results
      $tempResultsPath = "$OutputPath\temp_results.json"
      if (Test-Path $tempResultsPath) {
        $results = Get-Content -Path $tempResultsPath -Raw | ConvertFrom-Json
                
        # Clean up temporary files
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempResultsPath -Force -ErrorAction SilentlyContinue
        if (-not $SaveFiles) {
          Remove-Item -Path $regExportPath -Force -ErrorAction SilentlyContinue
        }
                
        return $results
      }
      else {
        Write-Warning "No Bluetooth devices with IRK found"
        return $null
      }
    }
    catch {
      Write-Error "Error extracting Bluetooth IRK values: $_"
      return $null
    }
  }
}

function Show-BluetoothIRKTable {
  [CmdletBinding()]
  param (
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [object[]]$IRKData
  )
    
  Begin {
    $allData = @()
  }
    
  Process {
    foreach ($item in $IRKData) {
      $allData += $item
    }
  }
    
  End {
    if ($allData.Count -eq 0) {
      Write-Warning "No Bluetooth IRK data to display"
      return
    }
        
    # Group by adapter
    $groupedData = $allData | Group-Object -Property AdapterMAC
        
    foreach ($adapterGroup in $groupedData) {
      Write-Host "`nBluetooth Adapter: $($adapterGroup.Name)" -ForegroundColor Cyan
      Write-Host "----------------------------------------" -ForegroundColor Cyan
            
      foreach ($device in $adapterGroup.Group) {
        Write-Host "Device: $($device.DeviceName) [$($device.DeviceMAC)]" -ForegroundColor Yellow
        Write-Host "IRK: $($device.IRK)" -ForegroundColor Green
        Write-Host ""
      }
    }
  }
}

# Export the functions
Export-ModuleMember -Function Get-BluetoothIRK, Show-BluetoothIRKTable
