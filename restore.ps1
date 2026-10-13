param([string]$Destination = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'relakeep-restore.json'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath $PSScriptRoot
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Pull failed. Resolve local Git changes before restoring.' }
$Source = Join-Path $PSScriptRoot 'vault/latest.atlas-backup.json'
if (!(Test-Path -LiteralPath $Source)) { throw 'This repository has no saved backup yet.' }
if (Test-Path -LiteralPath $Destination) { throw 'Destination already exists. Choose another path.' }
Copy-Item -LiteralPath $Source -Destination $Destination
Write-Host "Backup copied to $Destination. Open Relakeep > Settings > Restore encrypted backup, then enter its master password."
