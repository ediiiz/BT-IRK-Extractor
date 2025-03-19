# BT-IRK-Extractor Loader
# This script loads the Bluetooth IRK Extractor module directly in memory

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function global:Install-BT-IRK-Extractor {
  [CmdletBinding()]
  param()
    
  # Create module directory if it doesn't exist
  $modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\BT-IRK-Extractor"
  if (-not (Test-Path -Path $modulePath)) {
    New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
  }
    
  # Download module content
  $moduleUrl = "https://raw.githubusercontent.com/yourusername/BT-IRK-Extractor/main/BT-IRK-Extractor.psm1"
    
  try {
    $moduleContent = (Invoke-WebRequest -Uri $moduleUrl -UseBasicParsing).Content
    $moduleContent | Set-Content -Path "$modulePath\BT-IRK-Extractor.psm1" -Force
        
    # Create module manifest
    $manifestParams = @{
      Path              = "$modulePath\BT-IRK-Extractor.psd1"
      RootModule        = "BT-IRK-Extractor.psm1"
      ModuleVersion     = "1.0.0"
      Author            = "Your Name"
      Description       = "Bluetooth IRK Extractor for Windows"
      PowerShellVersion = "5.1"
      FunctionsToExport = @('Get-BluetoothIRK', 'Show-BluetoothIRKTable')
    }
        
    New-ModuleManifest @manifestParams
        
    Write-Host "BT-IRK-Extractor module has been installed successfully." -ForegroundColor Green
    Write-Host "To use, run: Import-Module BT-IRK-Extractor" -ForegroundColor Green
  }
  catch {
    Write-Error "Failed to install BT-IRK-Extractor module: $_"
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
    
  # Download module content directly
  $moduleUrl = "https://raw.githubusercontent.com/yourusername/BT-IRK-Extractor/main/BT-IRK-Extractor.psm1"
    
  try {
    # Load the module content directly into memory to bypass execution policy
    $moduleContent = (Invoke-WebRequest -Uri $moduleUrl -UseBasicParsing).Content
    $scriptBlock = [ScriptBlock]::Create($moduleContent)
        
    # Create a temporary module in memory
    $tempModule = New-Module -Name BT-IRK-ExtractorTemp -ScriptBlock $scriptBlock
    Import-Module $tempModule -Force
        
    # Create temporary working directory
    $tempDir = "$env:TEMP\BTIRKTemp"
    if (-not (Test-Path -Path $tempDir)) {
      New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }
        
    # Run the extraction and display results
    $irkData = Get-BluetoothIRK -OutputPath $tempDir
    Show-BluetoothIRKTable -IRKData $irkData
        
    # Suggest installation
    Write-Host "`nTo install BT-IRK-Extractor permanently, run: Install-BT-IRK-Extractor" -ForegroundColor Yellow
        
    # Clean up temporary module
    Remove-Module BT-IRK-ExtractorTemp -Force -ErrorAction SilentlyContinue
        
    # Return the data
    return $irkData
  }
  catch {
    Write-Error "Failed to run BT-IRK-Extractor: $_"
  }
}

# Display welcome message
Write-Host "Bluetooth IRK Extractor loaded successfully" -ForegroundColor Cyan
Write-Host "Available commands:" -ForegroundColor Yellow
Write-Host "  Get-BTIRKOnce - Extract Bluetooth IRK keys immediately" -ForegroundColor Green
Write-Host "  Install-BT-IRK-Extractor - Install the module permanently" -ForegroundColor Green

# Export functions so they're available in the global scope
Export-ModuleMember -Function Get-BTIRKOnce, Install-BT-IRK-Extractor
