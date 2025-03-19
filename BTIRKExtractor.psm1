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
    
  # Download module content
  $moduleUrl = "https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.psm1"
    
  try {
    $moduleContent = (Invoke-WebRequest -Uri $moduleUrl -UseBasicParsing).Content
    $moduleContent | Set-Content -Path "$modulePath\BTIRKExtractor.psm1" -Force
        
    # Create module manifest
    $manifestParams = @{
      Path              = "$modulePath\BTIRKExtractor.psd1"
      RootModule        = "BTIRKExtractor.psm1"
      ModuleVersion     = "1.0.0"
      Author            = "ediiiz"
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
    
  # Download module content directly
  $moduleUrl = "https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.psm1"
    
  try {
    # Load the module content directly into memory to bypass execution policy
    $moduleContent = (Invoke-WebRequest -Uri $moduleUrl -UseBasicParsing).Content
    $scriptBlock = [ScriptBlock]::Create($moduleContent)
        
    # Create a temporary module in memory
    $tempModule = New-Module -Name BTIRKExtractorTemp -ScriptBlock $scriptBlock
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
    Write-Host "`nTo install BTIRKExtractor permanently, run: Install-BTIRKExtractor" -ForegroundColor Yellow
        
    # Clean up temporary module
    Remove-Module BTIRKExtractorTemp -Force -ErrorAction SilentlyContinue
        
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

# Make the functions available without export-modulemember
$ExecutionContext.SessionState.Module.ExportedFunctions.Add('Get-BTIRKOnce', (Get-Item function:Get-BTIRKOnce))
$ExecutionContext.SessionState.Module.ExportedFunctions.Add('Install-BTIRKExtractor', (Get-Item function:Install-BTIRKExtractor))
