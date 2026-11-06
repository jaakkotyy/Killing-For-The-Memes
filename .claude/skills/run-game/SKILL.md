---
name: run-game
description: Launch, drive and verify Killing for the Memes (Godot 4.7.2, Windows) as a real app - headless multiplayer smoke tests, custom multi-instance scenarios with per-instance logs, tiled windowed instances for the user, and screenshots of game windows. Use when asked to run, start, play or screenshot the game, or to confirm a change works in the running game rather than only in unit tests.
---

# Running Killing for the Memes

Running the game means launching real Godot instances and checking what they did:
log lines for headless runs, screenshots for windowed runs. **Look at every screenshot**;
a blank or black frame means the launch failed.

Godot lives at `%USERPROFILE%\Tools\godot\4.7.2\` (or `$env:GODOT`); `tools/godot_path.ps1`
resolves it. Use the `_console.exe` for headless runs (so stdout can be captured) and the
plain `.exe` for windows the user will look at.

## Pick the mode

| Goal | Mode |
|---|---|
| "Does multiplayer still work?" after a networking change | 1. Smoke test |
| Reproduce a specific scenario (late joiner, bad address, timing) | 2. Custom headless run |
| The user wants to see or play it | 3. Windowed instances + capture |
| Screenshot one screen without disturbing the user's desktop | 4. Offscreen frames |
| Look at the 3D room, characters, lighting | 5. Room preview |

### 1. Smoke test (automated, about 10 s)

```powershell
.\tools\smoke_test.ps1 -Clients 3
```

Host + N headless clients join, auto-ready and auto-start. Every instance must print
`SMOKE_TEST PASS: game started` and exit 0. Per-instance logs go to `%TEMP%\kftm_smoke_test\`.

### 2. Custom headless scenario

Run from the Bash tool so each instance gets its own log file and `timeout` bounds it.
Use a fresh port per run (7800+) so you never collide with windows the user has open.

```bash
G="$USERPROFILE/Tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"; S="<scratchpad>/repro"; mkdir -p "$S"
timeout 15 "$G" --headless --path . -- --host --port=7801 --name=Host --auto-start > "$S/host.log" 2>&1 &
sleep 1
timeout 15 "$G" --headless --path . -- --join=127.0.0.1:7801 --name=P1 --auto-ready > "$S/p1.log" 2>&1 &
timeout 15 "$G" --headless --path . -- --join=127.0.0.1:7801 --name=P2 --auto-ready > "$S/p2.log" 2>&1 &
wait; grep -h "^\[" "$S"/*.log
```

Healthy log lines: `[Net] Hosting via ENet.`, `[Net] Connected as peer <id>.`,
`[Session] Game started with N players.`, `[Session] Rejecting peer <id>: <reason>`.
Add `--smoke-test` to an instance to make it exit with 0 on game start and 1 on failure,
and print the failure reason (for example a join rejection message).

Launch flags (after `--`): `--host`, `--join=<ip|ip:port|code>`, `--name=`, `--port=`,
`--auto-ready`, `--auto-start`, `--min-players=<n>` (debug builds), `--smoke-test`,
`--room-preview=<n>`, `--room-camera=seat|tv|overview`.
The source of truth is `src/util/launch_options.gd`.

### 3. Windowed instances for the user

```powershell
.\tools\run_local.ps1 -Clients 2        # host + 2 clients tiled on the primary monitor
.\.claude\skills\run-game\scripts\capture_windows.ps1 -OutDir "<scratchpad>"
```

The capture script saves `win0.png` (host, the first one started), `win1.png`, ... using
`PrintWindow`, so overlapping or off-screen windows are captured too. Read the PNGs.
Without `-AutoStart`, clients ready up automatically and the host waits for a Start click.

Close the instances you started:

```powershell
Get-Process | Where-Object { $_.MainWindowTitle -like "Killing for the Memes*" } | Stop-Process -Force
```

### 4. Offscreen frames of one instance

```bash
"$G" --path . --resolution 1280x720 --write-movie "<win-path>\\f.png" --quit-after 60 -- <flags>
```

This writes `f00000000.png` ... `f00000059.png`; read the last one. A window still opens
briefly. Pair it with headless peers (mode 2) to capture, for example, a populated lobby.
Write the movie path with **forward slashes** (`C:/Users/.../f.png`); a mangled path makes
Godot log `Condition "d.is_null()"` and write nothing.

### 5. Room preview (3D room, no network)

```bash
"$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/room/f.png" --quit-after 220 -- --room-preview=8 --room-camera=overview
```

Opens the room with n fake players (local player = seat 1, "You"). The spotlight hops to
the next player 0.5 s after start and then every 3 s, and that player flinches, so frame
~40 shows a flinch and a lit player. Correct frames: everyone seated with hands on the
keyboards, distinct shirt colours, name tags, glowing CRTs, the host with a green pixel
face beside the TV. `--room-camera=seat` shows your own CRT with static, `tv` the wall TV
reading "KILLING FOR THE MEMES". Mouse look is off while recording a movie.
In a debug window: Tab cycles cameras, F flinches someone, G moves the spotlight.
The models come from the `blender-pipeline` skill.

## Pitfalls (all hit in practice)

- **The user may be clicking the windows.** In mode 3 the user often interacts (Ready is a
  toggle, Start is a click). Before calling a state a bug, reproduce it headless (mode 2)
  or capture immediately after launch.
- **Shared log file.** Every instance writes `user://logs/godot.log` (in
  `%APPDATA%\Godot\app_userdata\Killing for the Memes\logs\`), so concurrent logs overwrite
  each other. Capture stdout per instance instead.
- **Output floods.** Headless Godot can print thousands of lines (for example on a stale
  import cache). From PowerShell, redirect to a file (`*> file.log`) and then search it;
  piping directly into `Select-String` once crashed PowerShell with a stack overflow.
- **Engine noise on kill.** When `timeout` kills an instance, Godot prints
  `BUG: Unreferenced static string`, `RID allocations ... leaked` and similar lines.
  They come from the forced shutdown, not from the game.
- **Multi-monitor positions.** Godot's `--position` counts from the virtual desktop's
  top-left, not the primary monitor's. `run_local.ps1` already offsets for this. Do the
  same in any new launcher.
- **Paths with spaces.** The project folder contains spaces. `Start-Process -ArgumentList`
  does not quote for you, so wrap the path in escaped quotes the way `tools/run_local.ps1`
  does for `--path`.
- **Exit codes from Start-Process.** Read `$proc.Handle` right after starting, or
  `$proc.ExitCode` comes back empty.
- **Fresh clone.** Run `--headless --import` once (all `tools/*.ps1` scripts do) before
  launching, or global class names such as `LobbyState` won't resolve.

## Keep this skill current

When a milestone adds scenes or launch flags (the 3D room in M3, the meme editor in M4,
the round loop in M5), update the modes above with how to reach and verify the new screen.
For example, add a flag that jumps straight into the meme editor and document what a
correct screenshot looks like.
