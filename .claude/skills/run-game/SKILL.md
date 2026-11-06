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
| Check the meme editor or the CRT zoom | 6. Meme editor |
| Does a whole match play out (rounds, deaths, win screen)? | 1. Smoke test `-FullGame`, then 7 |
| See the round loop: TV, HUD, shots, deaths, win screen | 7. Recorded bot game |

### 1. Smoke test (automated, about 10 s; full game about 30 s)

```powershell
.\tools\smoke_test.ps1 -Clients 3
.\tools\smoke_test.ps1 -Clients 3 -FullGame [-Seed 7] [-Online]
```

Host + N headless clients join, auto-ready and auto-start. Every instance must print
`SMOKE_TEST PASS: game started` and exit 0. Per-instance logs go to `%TEMP%\kftm_smoke_test\`.
With `-FullGame` every instance is an `--auto-play` bot on `--fast-rounds` timers and must
print `SMOKE_TEST PASS: game over after N rounds, winner <name>` (N = players - 1). Also
search the logs for `SCRIPT ERROR`: the room, presenter and HUD run headless on every peer.
Smoke tests pass `--offline-templates` unless `-Online` is given; then the host must log
`[Templates] 40 popular templates from Imgflip.` and bots submit `imgflip-<n>` ids. With a
`GIPHY_API_KEY` in the environment it also logs `[Templates] 25 GIF templates from GIPHY.`
and bots may submit `giphy-<id>` ids; `GIPHY unreachable (or the key was refused)` means
a bad key. Check a key's presence with `[ -n "$GIPHY_API_KEY" ]`, never print it.

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
`[Session] Game started with N players.`, `[Session] Rejecting peer <id>: <reason>`,
`[Session] Round N: CREATE` (one per phase), `[Session] Game over. Winner: <name>`.
Add `--smoke-test` to an instance to make it exit with 0 on game start and 1 on failure,
and print the failure reason (for example a join rejection message).

Launch flags (after `--`): `--host`, `--join=<ip|ip:port|code>`, `--name=`, `--port=`,
`--auto-ready`, `--auto-start`, `--min-players=<n>` (debug builds), `--smoke-test`,
`--smoke-test=game` (exit 0 at GAME_OVER), `--auto-play` (bot), `--fast-rounds` (host,
debug builds: 0.5 / 3 / 1 / 0.8 s phases), `--seed=<n>` (host: same prompts, spotlight
order and tie-breaks every run), `--room-preview=<n>`, `--room-camera=seat|tv|overview|editor`.
The source of truth is `src/util/launch_options.gd`.

### 3. Windowed instances for the user

```powershell
.\tools\run_local.ps1 -Clients 2        # host + 2 clients tiled on the primary monitor
.\tools\run_local.ps1 -Bots -FastRounds # clients play by themselves; the user plays the host
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
keyboards, distinct shirt colours, name tags, glowing CRTs, and no host character (it was
removed). `--room-camera=seat` shows your own CRT with static, `tv` the wall TV
reading "KILLING FOR THE MEMES". Mouse look is off while recording a movie.
In a debug window: Tab cycles cameras, F flinches someone, G moves the spotlight.
The models come from the `blender-pipeline` skill.

### 6. Meme editor and CRT zoom

```bash
"$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/editor/f.png" --quit-after 60 -- --room-preview=6 --room-camera=editor
```

Starts already zoomed into your CRT. A correct frame: the green-phosphor editor fills the
screen with a slight barrel curve and scanlines; prompt at the top, the template list with
thumbnails on the right (first one selected), a 4:3 preview, two caption fields and DONE.
The preview never goes online but loads the Imgflip catalogue saved by the last hosted
game: then the list starts with Drake, Two Buttons, ... (letterboxed in the preview) and
the hint line ends with "Popular templates via imgflip.com". Images not yet in
`user://template_cache/` show LOADING... and fill in as they download.
With `--room-camera=seat` instead, the same editor is the picture on your CRT in 3D.
To see the zoom itself, start at `seat` and record ~120 frames while pressing **E** in a
window (or call `MemeStation.open()` from a test). The automated check of typing, clicking
Done through the curve and Esc is `tests/unit/test_crt_zoom.gd`. A submitted meme prints
`[Room] Meme submitted: ...` and appears on the wall TV. In a real game the presenter
sends it to the server instead, and the editor is locked outside the creation phase.
After room or character changes, re-render the templates with `.\tools\capture_templates.ps1`
and look at the JPGs in `assets/meme_templates/`.

### 7. Recorded bot game (the round loop with your eyes)

One windowed host records frames while headless bots play; everyone is a bot, so the
recording needs no input. 450 frames at 15 fps cover a 4-player fast game.

```bash
S="C:/<scratchpad>/m5vis"; mkdir -p "$S"
"$G" --path . --resolution 960x540 --fixed-fps 15 --write-movie "$S/f.png" --quit-after 450 -- --host --port=7820 --name=Host --auto-start --auto-play --fast-rounds --seed=7 --min-players=4 > "$S/host.log" 2>&1 &
sleep 2
for n in Vlad Gus Bertha; do timeout 90 "$GC" --headless --path . -- --join=127.0.0.1:7820 --name=$n --auto-ready --auto-play --min-players=4 > "$S/$n.log" 2>&1 & done
wait
```

(`$G` = the windowed exe, `$GC` = the console exe.) `--fixed-fps` slows game time to the
frame rate, so the bots must use a long `timeout`. Make contact sheets of every ~10th frame
and look at them. Correct: the TV shows "ROUND n" and the prompt, then the camera turns to
your CRT with the editor; during spotlights the TV fills the middle of the view with a
"BOT MEME" meme, the HUD shows GOOD [1] / BAD [2] / SHOOT [Space], and shots appear as
red "X shot Y!" toasts with a muzzle flash; at elimination the results panel lists scores
(loser in red), the TV says "NAME IS OUT", a puff of smoke rises and that player slumps
over their keyboard, washed out; at the end the win panel shows "<NAME> SURVIVED", the
standings, and *Play again* / *Leave* on the host. A dead host shows "SPECTATING".

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
- **Synthetic input in tests.** Push events to the root with `push_input(event, true)`;
  the headless root viewport is stretched, so plain `push_input` misplaces mouse clicks.
- **Fresh clone.** Run `--headless --import` once (all `tools/*.ps1` scripts do) before
  launching, or global class names such as `LobbyState` won't resolve.

## Keep this skill current

When a milestone adds scenes or launch flags (the 3D room in M3, the meme editor in M4,
the round loop in M5, sound and hardening in M6), update the modes above with how to reach and verify the new screen.
For example, add a flag that jumps straight into the meme editor and document what a
correct screenshot looks like.
