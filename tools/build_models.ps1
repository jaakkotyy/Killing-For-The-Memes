# Rebuilds the game-ready models from the artist's Blender source files.
#
# The .blend sources are large (hundreds of MB) and live OUTSIDE the repo. Only the exported
# results (assets/models/**: .glb, baked maps, metrics JSON) are committed.
#
#   .\tools\build_models.ps1                         # full build, including the bakes (~1 min)
#   .\tools\build_models.ps1 -SkipBake               # reuse the committed normal/AO maps
#   .\tools\build_models.ps1 -Preview C:\tmp\prev    # also render pose previews (PNG)
#   .\tools\build_models.ps1 -PropsOnly              # only the table props (cup, can, beer)
#
# Sources: -AssetsDir, else $env:KFTM_ASSETS, else D:\Killing-For-The-Memes-Assets.
# Blender 2.81+: -Blender, else $env:BLENDER, else D:\Blender\blender.exe.
param(
    [string]$AssetsDir = "",
    [string]$Blender = "",
    [switch]$SkipBake,
    [string]$Preview = "",
    [switch]$PropsOnly
)

. "$PSScriptRoot\godot_path.ps1"

if (-not $AssetsDir) { $AssetsDir = if ($env:KFTM_ASSETS) { $env:KFTM_ASSETS } else { "D:\Killing-For-The-Memes-Assets" } }
if (-not $Blender) { $Blender = if ($env:BLENDER) { $env:BLENDER } else { "D:\Blender\blender.exe" } }

if (-not (Test-Path $Blender)) { Write-Error "Blender not found at '$Blender'. Pass -Blender or set `$env:BLENDER."; exit 1 }

# Runs one headless Blender export; fails if Blender exits badly or prints an error.
function Invoke-BlenderExport([string]$Label, [string[]]$BlenderArgs, [string]$Log, [string]$Pattern) {
    Write-Host "Building $Label (log: $Log)..."
    $proc = Start-Process -FilePath $Blender -ArgumentList $BlenderArgs -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
    $results = Select-String -Path $Log -Pattern "^($Pattern)|Error|Traceback"
    $results | ForEach-Object { Write-Host "  $($_.Line)" }
    if ($proc.ExitCode -ne 0 -or ($results | Where-Object { $_.Line -match "Error|Traceback" })) {
        Write-Error "Blender export of $Label failed; see $Log"
        exit 1
    }
}

if (-not $PropsOnly) {
    $playerSource = Join-Path $AssetsDir "Player Model.blend"
    if (-not (Test-Path $playerSource)) { Write-Error "Source not found: '$playerSource'. Pass -AssetsDir or set `$env:KFTM_ASSETS."; exit 1 }

    $outDir = Join-Path $ProjectRoot "assets\models\player"
    $script = Join-Path $PSScriptRoot "blender\build_player.py"
    $blenderArgs = @("-b", "--factory-startup", "`"$playerSource`"", "--python", "`"$script`"", "--", "--out", "`"$outDir`"")
    if ($SkipBake) { $blenderArgs += "--skip-bake" }
    if ($Preview) { $blenderArgs += @("--preview", "`"$(Join-Path $Preview 'player')`"") }
    Invoke-BlenderExport "player from '$playerSource'" $blenderArgs (Join-Path $env:TEMP "kftm_build_player.log") "WROTE|SKIN|SEAT|ACTION"
}

# Table props: one small source file each; build_props.py lists which objects to use.
$propsDir = Join-Path $ProjectRoot "assets\models\props"
$propsScript = Join-Path $PSScriptRoot "blender\build_props.py"
foreach ($prop in @("cup", "can", "beer")) {
    $source = Join-Path $AssetsDir "$prop.blend"
    if (-not (Test-Path $source)) { Write-Error "Source not found: '$source'. Pass -AssetsDir or set `$env:KFTM_ASSETS."; exit 1 }
    $propArgs = @("-b", "--factory-startup", "`"$source`"", "--python", "`"$propsScript`"", "--",
        "--prop", $prop, "--out", "`"$propsDir`"")
    Invoke-BlenderExport $prop $propArgs (Join-Path $env:TEMP "kftm_build_$prop.log") "WROTE|PROP"
}

Write-Host "Re-importing in Godot..."
& $Godot --headless --path $ProjectRoot --import *> (Join-Path $env:TEMP "kftm_import.log")
Write-Host "Done. Check the room with: Godot --path . -- --room-preview=8 --room-camera=overview"
