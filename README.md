# Bluetooth IRK Extractor for Windows

Extract Bluetooth Identity Resolving Keys (IRK) from Windows devices with a simple PowerShell script. This tool helps retrieve the IRK keys needed for advanced Bluetooth debugging, security research, or custom implementations.

## Quick Usage

Run this command in PowerShell (as Administrator) to instantly extract IRK keys from all paired Bluetooth devices:

```powershell
# One-line command - run and forget
irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.ps1 | iex; Get-BTIRKOnce
```

## What It Does

This tool:
- Extracts IRK (Identity Resolving Keys) from Windows registry
- Identifies all paired Bluetooth devices and their associated adapters
- Provides device names when available
- Formats the output in a clean, easy-to-read table
- Automatically handles SYSTEM-level access requirements

## Installation Options

### Temporary Use (Recommended)

This method runs the tool without permanent installation:

```powershell
# Load the tool
irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.ps1 | iex

# Extract the keys
Get-BTIRKOnce
```

### Permanent Installation

If you need the tool available in all PowerShell sessions:

```powershell
# Load the loader script
irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.ps1 | iex

# Install the module permanently
Install-BTIRKExtractor

# After installation, you can use it in any new PowerShell session
Import-Module BTIRKExtractor
```

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connection (for initial download)

## Advanced Usage

After installing the module:

```powershell
# Import the module
Import-Module BTIRKExtractor

# Extract keys and save files to disk
$irkData = Get-BluetoothIRK -SaveFiles

# Display formatted table
Show-BluetoothIRKTable -IRKData $irkData

# Work with the data programmatically
$irkData | ForEach-Object {
    "Device: $($_.DeviceName), MAC: $($_.DeviceMAC), IRK: $($_.IRK)"
}
```

## Available Commands

- `Get-BTIRKOnce` - Extract Bluetooth IRK keys without installing the module
- `Install-BTIRKExtractor` - Install the module permanently
- `Get-BluetoothIRK` - Extract IRK keys (available after installation)
- `Show-BluetoothIRKTable` - Display formatted results (available after installation)

## Parameters for Get-BluetoothIRK

| Parameter | Type | Description |
|-----------|------|-------------|
| -SaveFiles | Switch | Save extracted IRK values to disk |
| -OutputPath | String | Custom path to save extracted files (default: ~\BTIRKExtract) |

## Troubleshooting

### Execution Policy Issues

If you encounter execution policy errors, try this alternative command:

```powershell
powershell -ExecutionPolicy Bypass -Command "iex (irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BTIRKExtractor.ps1); Get-BTIRKOnce"
```

### Administrator Privileges

This tool requires administrator privileges. Right-click on PowerShell and select "Run as Administrator" before running the commands.

### No Bluetooth Devices Found

If no devices are found:
- Ensure you have Bluetooth adapters installed and working
- Check that you have paired Bluetooth devices
- Verify you're running with Administrator privileges

## What are IRK Keys?

Identity Resolving Keys (IRKs) are cryptographic keys used in Bluetooth Low Energy (BLE) privacy features. They allow devices to recognize each other even when using random addresses, which helps maintain privacy while enabling reconnection.

## License

MIT License

## Acknowledgments

- Uses Microsoft's PsExec tool from the Sysinternals Suite
- Based on Bluetooth SIG specifications for BLE privacy

---

Created by [ediiiz](https://github.com/ediiiz)
