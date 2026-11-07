# End-to-end multiplayer smoke test: starts a headless host and N headless clients on this
# machine, waits until all of them have joined, readied up and seen the game start, and
# fails if any instance does not get there.
#
# -FullGame plays a whole match instead: every instance is a bot (--auto-play) on short
# timers (--fast-rounds), and each must see GAME_OVER with a winner.
#
# Popular online templates are off by default so the test never depends on the internet;
# -Online makes the host fetch them from Imgflip and every client download the images.
#
# -Mode guess plays guess mode ("Who Am I?") instead of the meme game; -Pack picks its
# identity pack (default: musicians).
#
# Usage: .\tools\smoke_test.ps1 [-Clients 2] [-Port 7790] [-FullGame] [-Seed 7] [-Online] [-Mode guess] [-Pack movies]

param(
    [ValidateRange(1, 7)][int]$Clients = 2,
    [int]$Port = 7790,
    [int]$TimeoutSeconds = 0,
    [switch]$FullGame,
    [int]$Seed = 7,
    [switch]$Online,
    [ValidateSet("memes", "guess")][string]$Mode = "memes",
    [string]$Pack = ""
)

if ($TimeoutSeconds -le 0) { $TimeoutSeconds = if ($FullGame) { 150 } else { 45 } }
# @(...) around the if: PowerShell unwraps a one-item array returned from it into a string,
# and += would then glue the next flag onto it.
$SmokeArgs = @(if ($FullGame) {
    "--smoke-test=game", "--auto-play", "--fast-rounds", "--seed=$Seed"
} else {
    "--smoke-test"
})
if (-not $Online) { $SmokeArgs += "--offline-templates" }

. "$PSScriptRoot\godot_path.ps1"

& $Godot --headless --path $ProjectRoot --import | Out-Null

$LogDir = Join-Path ([System.IO.Path]::GetTempPath()) "kftm_smoke_test"
New-Item -ItemType Directory -Force $LogDir | Out-Null
Get-ChildItem $LogDir -Filter "*.log" | Remove-Item -Force

$MinPlayers = $Clients + 1
$Instances = @()

function Start-Instance([string]$Name, [string[]]$GameArgs) {
    $allArgs = @("--headless", "--path", "`"$ProjectRoot`"", "--", "--name=$Name", "--min-players=$MinPlayers") + $SmokeArgs + $GameArgs
    $log = Join-Path $LogDir "$Name.log"
    $proc = Start-Process -FilePath $Godot -ArgumentList $allArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $null = $proc.Handle  # Keep a handle so ExitCode is available after exit.
    return [pscustomobject]@{ Name = $Name; Process = $proc; Log = $log }
}

$HostArgs = @("--host", "--port=$Port", "--auto-start", "--mode=$Mode")
if ($Pack) { $HostArgs += "--pack=$Pack" }
$Instances += Start-Instance "Host" $HostArgs
Start-Sleep -Milliseconds 1000
for ($i = 1; $i -le $Clients; $i++) {
    $Instances += Start-Instance "Client$i" @("--join=127.0.0.1:$Port", "--auto-ready")
}

$Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
foreach ($inst in $Instances) {
    $remaining = [int][math]::Max(1, ($Deadline - (Get-Date)).TotalSeconds)
    if (-not $inst.Process.WaitForExit($remaining * 1000)) {
        $inst.Process.Kill()
        $inst.Process.WaitForExit()
    }
}

$Failed = $false
foreach ($inst in $Instances) {
    $code = $inst.Process.ExitCode
    $result = Select-String -Path $inst.Log -Pattern "SMOKE_TEST" -SimpleMatch | Select-Object -Last 1
    $line = if ($result) { $result.Line } else { "(no result line)" }
    Write-Host ("{0,-8} exit={1}  {2}" -f $inst.Name, $code, $line)
    if ($code -ne 0) { $Failed = $true }
}

if ($Failed) {
    Write-Host "`nSMOKE TEST FAILED. Logs: $LogDir" -ForegroundColor Red
    exit 1
}
Write-Host "`nSMOKE TEST PASSED ($($Instances.Count) instances)." -ForegroundColor Green
exit 0
