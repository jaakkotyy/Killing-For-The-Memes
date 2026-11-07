# Exports a Windows release build to builds/windows/.
# Requires Godot export templates for the pinned version (Editor > Manage Export Templates).
# Usage: .\tools\build_windows.ps1 [-Debug]

param([switch]$Debug)

. "$PSScriptRoot\godot_path.ps1"

$OutDir = Join-Path $ProjectRoot "builds\windows"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutFile = Join-Path $OutDir "Adrift.exe"

& $Godot --headless --path $ProjectRoot --import | Out-Null

$Mode = if ($Debug) { "--export-debug" } else { "--export-release" }
& $Godot --headless --path $ProjectRoot $Mode "Windows Desktop" $OutFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Built $OutFile"
