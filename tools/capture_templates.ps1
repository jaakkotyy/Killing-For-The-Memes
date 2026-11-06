# Re-renders the meme templates (assets/meme_templates/*.jpg) from the game's own room.
# One template per entry in data/meme_templates.json; the shots are staged in
# src/meme/templates/template_studio.gd. Opens a window for a few seconds (rendering needs it).
#
#   .\tools\capture_templates.ps1
. "$PSScriptRoot\godot_path.ps1"

$log = Join-Path $env:TEMP "kftm_capture_templates.log"
& $Godot --headless --path $ProjectRoot --import *> (Join-Path $env:TEMP "kftm_import.log")
$proc = Start-Process -FilePath $Godot -ArgumentList @("--path", "`"$ProjectRoot`"", "--resolution", "1600x1200",
    "res://src/meme/templates/template_studio.tscn") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
Select-String -Path $log -Pattern "^TEMPLATE" | ForEach-Object { Write-Host $_.Line }
& $Godot --headless --path $ProjectRoot --import *> (Join-Path $env:TEMP "kftm_import.log")
if ($proc.ExitCode -ne 0) { Write-Error "Template capture failed; see $log"; exit 1 }
