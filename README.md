# Bluetooth IRK Extractor

Extract Bluetooth Identity Resolving Keys (IRK) from Windows devices.

## Quick Usage

Run this command in PowerShell (as Administrator):

```powershell
irm https://raw.githubusercontent.com/ediiizBT-IRK-Extractor/mainBT-IRK-Extractor.ps1 | iex; Get-BTIRKOnce
