# Export the Web build to build\web\index.html
# Usage: .\tools\export_web.ps1 [-DebugBuild]
# Set $env:GODOT to override the Godot executable path.
param([switch]$DebugBuild)

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Program Files\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" }

$project = (Resolve-Path "$PSScriptRoot\..").Path
$out = Join-Path $project "build\web"
New-Item -ItemType Directory -Force $out | Out-Null

$mode = "--export-release"
if ($DebugBuild) { $mode = "--export-debug" }

& $godot --headless --path $project $mode "Web" (Join-Path $out "index.html")
exit $LASTEXITCODE
