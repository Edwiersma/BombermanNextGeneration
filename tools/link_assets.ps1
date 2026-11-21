# Link the local (non-git) asset folder into the project as res://assets_ext
# Usage: .\tools\link_assets.ps1 [-Target ..\..\assets\export]
param([string]$Target = "$PSScriptRoot\..\..\assets\export")

$link = Join-Path (Resolve-Path "$PSScriptRoot\..").Path "assets_ext"
$Target = (Resolve-Path $Target).Path

if (Test-Path $link) {
    Write-Host "assets_ext already exists: $link"
    exit 0
}
New-Item -ItemType Junction -Path $link -Target $Target | Out-Null
Write-Host "Linked $link -> $Target"
