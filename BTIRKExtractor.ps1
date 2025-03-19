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
      
    # Define paths
    $psExecPath = "$OutputPath\PsExec64.exe"
    $regExportPath = "$OutputPath\BTKeys.reg"
    $tempResultsPath = "$OutputPath\temp_results.json"
    $resultsPath = "$OutputPath\IRK_Summary.csv"
      
    # Download PsExec if needed
    if (-not (Test-Path -Path $psExecPath)) {
      Write-Verbose "Downloading PsExec64.exe..."
          
      try {
        $psExecUrl = "https://download.sysinternals.com/files/PSTools.zip"
        $zipPath = "$OutputPath\PSTools.zip"
              
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
              
        Write-Verbose "PsExec64.exe has been downloaded to $psExecPath"
      }
      catch {
        throw "Failed to download PsExec: $_"
      }
    }
  }
  
  Process {
    # Create direct PowerShell command to run as SYSTEM
    $psCommand = @'
# Extraction script
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$regExportPath = "{0}"
$tempResultsPath = "{1}"
$saveFiles = ${2}
$outputPath = "{3}"
$resultsPath = "{4}"
$deviceData = @()

# Function to get device name from registry
function Get-BluetoothDeviceName {
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
  
  # Try to get from user-friendly names in device manager
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

# Check if the registry path exists
if (Test-Path -Path $regPath) {
  # Get the Bluetooth adapter MAC address subfolder
  $adapterKeys = Get-ChildItem -Path $regPath
  
  if ($adapterKeys.Count -gt 0) {
      foreach ($adapter in $adapterKeys) {
          # Get device keys under this adapter
          $deviceKeys = Get-ChildItem -Path $adapter.PSPath
          
          if ($deviceKeys.Count -gt 0) {
              foreach ($device in $deviceKeys) {
                  $deviceMac = $device.PSChildName
                  $deviceName = Get-BluetoothDeviceName -deviceMac $deviceMac
                  
                  # Export this device key to .reg file
                  $exportCmd = "reg export `"$($device.PSPath.Replace('Microsoft.PowerShell.Core\Registry::',''))`" `"$regExportPath`" /y"
                  cmd /c $exportCmd | Out-Null
                  
                  # Read the exported REG file
                  $content = Get-Content -Path $regExportPath -Raw
                  
                  # Look for the IRK value
                  if ($content -match 'IRK"=hex:([0-9a-f,]+)') {
                      $irkWithCommas = $matches[1]
                      $irk = $irkWithCommas -replace ',', ''
                      
                      # Add to device data
                      $deviceObj = [PSCustomObject]@{
                          DeviceName = $deviceName
                          DeviceMAC = $deviceMac
                          AdapterMAC = $adapter.PSChildName
                          IRK = $irk
                      }
                      $deviceData += $deviceObj
                      
                      # Save IRK to a separate file for each device if requested
                      if ($saveFiles) {
                          $irkFilePath = "$outputPath\IRK_$deviceMac.txt"
                          $irk | Out-File -FilePath $irkFilePath
                      }
                  }
              }
          }
      }
      
      # Export the results to CSV if requested
      if ($saveFiles -and $deviceData.Count -gt 0) {
          $deviceData | Export-Csv -Path $resultsPath -NoTypeInformation
      }
      
      # Always export results to temp file for retrieval
      if ($deviceData.Count -gt 0) {
          $deviceData | ConvertTo-Json | Out-File -FilePath $tempResultsPath
      }
  }
}
'@
      
    # Format the command with the specific paths
    $saveFilesValue = if ($SaveFiles) { '$true' } else { '$false' }
    $formattedCommand = $psCommand -f $regExportPath, $tempResultsPath, $saveFilesValue, $OutputPath, $resultsPath
      
    # Encode the command to avoid quoting issues
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($formattedCommand)
    $encodedCommand = [Convert]::ToBase64String($bytes)
      
    try {
      Write-Host "Extracting Bluetooth IRK values..." -ForegroundColor Yellow
          
      # Run PsExec with the encoded command
      $psExecArgs = "-accepteula -i -s powershell.exe -EncodedCommand $encodedCommand -ExecutionPolicy Bypass -WindowStyle Hidden"
      Start-Process -FilePath $psExecPath -ArgumentList $psExecArgs -Wait -NoNewWindow
          
      # Wait a moment to ensure the process completes
      Start-Sleep -Seconds 2
          
      # Check if results were generated
      if (Test-Path -Path $tempResultsPath) {
        try {
          $results = Get-Content -Path $tempResultsPath -Raw | ConvertFrom-Json
                  
          # Clean up temporary file
          Remove-Item -Path $tempResultsPath -Force -ErrorAction SilentlyContinue
                  
          if (-not $SaveFiles) {
            Remove-Item -Path $regExportPath -Force -ErrorAction SilentlyContinue
          }
                  
          return $results
        }
        catch {
          Write-Error "Error processing results: $_"
          return $null
        }
      }
      else {
        Write-Host "No Bluetooth devices with IRK found" -ForegroundColor Yellow
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
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$IRKData
  )
  
  Begin {
    $allData = @()
  }
  
  Process {
    if ($IRKData) {
      foreach ($item in $IRKData) {
        $allData += $item
      }
    }
  }
  
  End {
    if ($allData.Count -eq 0) {
      Write-Host "No Bluetooth IRK data to display" -ForegroundColor Yellow
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
