# Launches one host and N clients on this machine, tiled across the screen, for local
# multiplayer testing. Clients ready up automatically; the host presses Start.
#
# Usage:
#   .\tools\run_local.ps1                      # host + 2 clients (the 3-player minimum)
#   .\tools\run_local.ps1 -Clients 5           # host + 5 clients
#   .\tools\run_local.ps1 -Clients 1 -MinPlayers 2 -AutoStart
#   .\tools\run_local.ps1 -Bots -FastRounds    # you play the host against bot clients

param(
    [ValidateRange(1, 7)][int]$Clients = 2,
    [int]$Port = 7777,
    [int]$MinPlayers = 0,
    [switch]$AutoStart,
    # Clients play by themselves (random memes, votes and shots).
    [switch]$Bots,
    # Short phase timers (debug builds), for checking the round loop quickly.
    [switch]$FastRounds
)

. "$PSScriptRoot\godot_path.ps1"

# Use the windowed (non-console) executable so each instance opens a single game window.
$GodotGui = $Godot -replace "_console\.exe$", ".exe"
if (-not (Test-Path $GodotGui)) { $GodotGui = $Godot }

& $Godot --headless --path $ProjectRoot --import | Out-Null

# Tile windows on the primary monitor's work area: 2 columns for up to 4 instances, 4 for more.
# Godot's --position counts from the top-left of the whole virtual desktop (all monitors),
# so offset by where the primary monitor sits inside it.
Add-Type -AssemblyName System.Windows.Forms
Add-Type 'using System.Runtime.InteropServices; public static class KftmDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[KftmDpi]::SetProcessDPIAware() | Out-Null
$Work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$Virtual = [System.Windows.Forms.SystemInformation]::VirtualScreen
$OriginX = $Work.X - $Virtual.X
$OriginY = $Work.Y - $Virtual.Y

$TitleBar = 40   # Approximate window frame + title bar height.
$Total = $Clients + 1
$Columns = if ($Total -le 4) { 2 } else { 4 }
$Rows = [math]::Ceiling($Total / $Columns)
$CellWidth = [int]($Work.Width / $Columns)
$CellHeight = [int]($Work.Height / $Rows)
$Height = [int][math]::Min(($CellWidth - 16) * 9 / 16, $CellHeight - $TitleBar)
$Width = [int]($Height * 16 / 9)

function Start-Instance([int]$Index, [string[]]$GameArgs) {
    $x = $OriginX + ($Index % $Columns) * $CellWidth
    $y = $OriginY + [math]::Floor($Index / $Columns) * $CellHeight + $TitleBar
    $allArgs = @("--path", "`"$ProjectRoot`"", "--position", "$x,$y", "--resolution", "${Width}x${Height}", "--") + $GameArgs
    Start-Process -FilePath $GodotGui -ArgumentList $allArgs | Out-Null
}

$HostArgs = @("--host", "--name=Host", "--port=$Port")
if ($MinPlayers -gt 0) { $HostArgs += "--min-players=$MinPlayers" }
if ($AutoStart) { $HostArgs += "--auto-start" }
if ($FastRounds) { $HostArgs += "--fast-rounds" }
Start-Instance 0 $HostArgs

# Give the host a moment to open its port.
Start-Sleep -Milliseconds 1000

for ($i = 1; $i -le $Clients; $i++) {
    $ClientArgs = @("--join=127.0.0.1:$Port", "--name=Player$i", "--auto-ready")
    if ($MinPlayers -gt 0) { $ClientArgs += "--min-players=$MinPlayers" }
    if ($Bots) { $ClientArgs += "--auto-play" }
    Start-Instance $i $ClientArgs
}

Write-Host "Started 1 host + $Clients client(s) on port $Port."
