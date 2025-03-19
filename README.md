# Bluetooth IRK Extractor for Windows

Extract Bluetooth Identity Resolving Keys (IRK) from Windows devices with a simple PowerShell script.

## Quick Usage

Run this command in PowerShell (as Administrator):

```powershell
# One-line command - run instantly
irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BT-IRK-Extractor.ps1 | iex
```

## What It Does

This tool:
- Extracts IRK (Identity Resolving Keys) from Windows registry
- Identifies all paired Bluetooth devices and their associated adapters
- Provides device names when available
- Formats the output in a clean, easy-to-read table
- Offers an option to save results to your desktop

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connection (for initial download)

## Troubleshooting

### Execution Policy Issues

If you encounter execution policy errors, try this alternative command:

```powershell
powershell -ExecutionPolicy Bypass -Command "& {iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BT-IRK-Extractor.ps1'))}"
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

---

Created by [ediiiz](https://github.com/ediiiz)
```

This approach should solve the issue by:

1. Making the script completely self-contained (no separate module/loader structure)
2. Eliminating the `Export-ModuleMember` command that was causing problems
3. Simplifying the usage to a single command with no additional functions to call
4. Providing an alternative execution method for users experiencing execution policy issues
5. Including an option to save results to the desktop at the end of execution

All the user needs to do is run a single command, and the script will handle everything else automatically.
