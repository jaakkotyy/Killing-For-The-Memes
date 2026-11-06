# Rebuilds the game-ready character assets from the artist's Blender source files.
#
# The .blend sources are large (hundreds of MB) and live OUTSIDE the repo. Only the exported
# results (assets/models/**: .glb, baked maps, metrics JSON) are committed.
#
#   .\tools\build_models.ps1                         # full build, including the bakes (~1 min)
#   .\tools\build_models.ps1 -SkipBake               # reuse the committed normal/AO maps
#   .\tools\build_models.ps1 -Preview C:\tmp\prev    # also render pose previews (PNG)
#
# Sources: -AssetsDir, else $env:KFTM_ASSETS, else D:\Killing-For-The-Memes-Assets.
# Blender 2.81+: -Blender, else $env:BLENDER, else D:\Blender\blender.exe.
param(
    [string]$AssetsDir = "",
    [string]$Blender = "",
    [switch]$SkipBake,
    [string]$Preview = ""
)

. "$PSScriptRoot\godot_path.ps1"

if (-not $AssetsDir) { $AssetsDir = if ($env:KFTM_ASSETS) { $env:KFTM_ASSETS } else { "D:\Killing-For-The-Memes-Assets" } }
if (-not $Blender) { $Blender = if ($env:BLENDER) { $env:BLENDER } else { "D:\Blender\blender.exe" } }

if (-not (Test-Path $Blender)) { Write-Error "Blender not found at '$Blender'. Pass -Blender or set `$env:BLENDER."; exit 1 }
$playerSource = Join-Path $AssetsDir "Player Model.blend"
if (-not (Test-Path $playerSource)) { Write-Error "Source not found: '$playerSource'. Pass -AssetsDir or set `$env:KFTM_ASSETS."; exit 1 }

$outDir = Join-Path $ProjectRoot "assets\models\player"
$log = Join-Path $env:TEMP "kftm_build_player.log"
$script = Join-Path $PSScriptRoot "blender\build_player.py"
$blenderArgs = @("-b", "--factory-startup", "`"$playerSource`"", "--python", "`"$script`"", "--", "--out", "`"$outDir`"")
if ($SkipBake) { $blenderArgs += "--skip-bake" }
if ($Preview) { $blenderArgs += @("--preview", "`"$(Join-Path $Preview 'player')`"") }

Write-Host "Building player from '$playerSource' (log: $log)..."
$proc = Start-Process -FilePath $Blender -ArgumentList $blenderArgs -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$results = Select-String -Path $log -Pattern "^(WROTE|SKIN|SEAT|ACTION)|Error|Traceback"
$results | ForEach-Object { Write-Host "  $($_.Line)" }
if ($proc.ExitCode -ne 0 -or ($results | Where-Object { $_.Line -match "Error|Traceback" })) {
    Write-Error "Blender export failed; see $log"
    exit 1
}

Write-Host "Re-importing in Godot..."
& $Godot --headless --path $ProjectRoot --import *> (Join-Path $env:TEMP "kftm_import.log")
Write-Host "Done. Check the room with: Godot --path . -- --room-preview=8 --room-camera=overview"
