# BTIRKExtractor Loader
# This script loads the Bluetooth IRK Extractor module

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function global:Install-BTIRKExtractor {
  [CmdletBinding()]
  param()
    
  # Create module directory if it doesn't exist
  $modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\BTIRKExtractor"
  if (-not (Test-Path -Path $modulePath)) {
    New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
  }
    
  # Download module file
  $moduleUrl = "https://raw.githubusercontent.com/ediiizBT-IRK-Extractor/mainBT-IRK-Extractor.psm1"
  $moduleDestination = "$modulePath\BTIRKExtractor.psm1"
    
  try {
    Invoke-WebRequest -Uri $moduleUrl -OutFile $moduleDestination
        
    # Create module manifest
    $manifestParams = @{
      Path              = "$modulePath\BTIRKExtractor.psd1"
      RootModule        = "BTIRKExtractor.psm1"
      ModuleVersion     = "1.0.0"
      Author            = "Your Name"
      Description       = "Bluetooth IRK Extractor for Windows"
      PowerShellVersion = "5.1"
      FunctionsToExport = @('Get-BluetoothIRK', 'Show-BluetoothIRKTable')
    }
        
    New-ModuleManifest @manifestParams
        
    Write-Host "BTIRKExtractor module has been installed successfully." -ForegroundColor Green
    Write-Host "To use, run: Import-Module BTIRKExtractor" -ForegroundColor Green
  }
  catch {
    Write-Error "Failed to install BTIRKExtractor module: $_"
  }
}

function global:Get-BTIRKOnce {
  [CmdletBinding()]
  param()
    
  # Check for admin privileges
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Error "This function requires administrative privileges. Please run PowerShell as Administrator."
    return
  }
    
  # Create temporary directory
  $tempDir = "$env:TEMP\BTIRKExtractorTemp"
  if (-not (Test-Path -Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
  }
    
  # Download module file to temp location
  $moduleUrl = "https://raw.githubusercontent.com/ediiizBT-IRK-Extractor/mainBT-IRK-Extractor.psm1"
  $tempModulePath = "$tempDir\BTIRKExtractor.psm1"
    
  try {
    Invoke-WebRequest -Uri $moduleUrl -OutFile $tempModulePath
        
    # Import the module from temp location
    Import-Module $tempModulePath -Force
        
    # Run the extraction and display results
    $irkData = Get-BluetoothIRK -OutputPath $tempDir
    Show-BluetoothIRKTable -IRKData $irkData
        
    # Suggest installation
    Write-Host "`nTo install BTIRKExtractor permanently, run: Install-BTIRKExtractor" -ForegroundColor Yellow
        
    # Return the data
    return $irkData
  }
  catch {
    Write-Error "Failed to run BTIRKExtractor: $_"
  }
}

# Display welcome message
Write-Host "Bluetooth IRK Extractor loaded successfully" -ForegroundColor Cyan
Write-Host "Available commands:" -ForegroundColor Yellow
Write-Host "  Get-BTIRKOnce - Extract Bluetooth IRK keys without installing the module" -ForegroundColor Green
Write-Host "  Install-BTIRKExtractor - Install the module permanently" -ForegroundColor Green

# Return functions to the global scope
Export-ModuleMember -Function Get-BTIRKOnce, Install-BTIRKExtractor
