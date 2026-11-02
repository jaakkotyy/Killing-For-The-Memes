# Resolves the Godot executable used by the other tool scripts.
# Override by setting the GODOT environment variable to your Godot console executable.
# Dot-source this file: . "$PSScriptRoot\godot_path.ps1"

$GodotVersion = "4.7.2"

if ($env:GODOT -and (Test-Path $env:GODOT)) {
    $Godot = $env:GODOT
} else {
    $Godot = Join-Path $env:USERPROFILE "Tools\godot\$GodotVersion\Godot_v$GodotVersion-stable_win64_console.exe"
}

if (-not (Test-Path $Godot)) {
    Write-Error "Godot not found at '$Godot'. Install Godot $GodotVersion or set `$env:GODOT."
    exit 1
}

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
