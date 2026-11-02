# Launches one host and N clients on this machine, tiled across the screen, for local
# multiplayer testing. Clients ready up automatically; the host presses Start.
#
# Usage:
#   .\tools\run_local.ps1                      # host + 2 clients (the 3-player minimum)
#   .\tools\run_local.ps1 -Clients 5           # host + 5 clients
#   .\tools\run_local.ps1 -Clients 1 -MinPlayers 2 -AutoStart

param(
    [ValidateRange(1, 7)][int]$Clients = 2,
    [int]$Port = 7777,
    [int]$MinPlayers = 0,
    [switch]$AutoStart
)

. "$PSScriptRoot\godot_path.ps1"

# Use the windowed (non-console) executable so each instance opens a single game window.
$GodotGui = $Godot -replace "_console\.exe$", ".exe"
if (-not (Test-Path $GodotGui)) { $GodotGui = $Godot }

& $Godot --headless --path $ProjectRoot --import | Out-Null

# Tile windows: 2 columns for up to 4 instances, 4 columns for more.
$Total = $Clients + 1
$Columns = if ($Total -le 4) { 2 } else { 4 }
$Width = [int](1920 / $Columns)
$Height = [int]($Width * 9 / 16)

function Start-Instance([int]$Index, [string[]]$GameArgs) {
    $x = ($Index % $Columns) * $Width
    $y = [math]::Floor($Index / $Columns) * ($Height + 32)
    $allArgs = @("--path", "`"$ProjectRoot`"", "--position", "$x,$y", "--resolution", "${Width}x${Height}", "--") + $GameArgs
    Start-Process -FilePath $GodotGui -ArgumentList $allArgs | Out-Null
}

$HostArgs = @("--host", "--name=Host", "--port=$Port")
if ($MinPlayers -gt 0) { $HostArgs += "--min-players=$MinPlayers" }
if ($AutoStart) { $HostArgs += "--auto-start" }
Start-Instance 0 $HostArgs

# Give the host a moment to open its port.
Start-Sleep -Milliseconds 1000

for ($i = 1; $i -le $Clients; $i++) {
    $ClientArgs = @("--join=127.0.0.1:$Port", "--name=Player$i", "--auto-ready")
    if ($MinPlayers -gt 0) { $ClientArgs += "--min-players=$MinPlayers" }
    Start-Instance $i $ClientArgs
}

Write-Host "Started 1 host + $Clients client(s) on port $Port."
