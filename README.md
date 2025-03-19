# Bluetooth IRK Extractor

Extract Bluetooth Identity Resolving Keys (IRK) from Windows devices.

## Quick Usage

Run this command in PowerShell (as Administrator):

```powershell
irm https://raw.githubusercontent.com/ediiiz/BT-IRK-Extractor/main/BT-IRK-Extractor.ps1 | iex; Get-BTIRKOnce
