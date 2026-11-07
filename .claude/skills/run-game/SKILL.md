---
name: run-game
description: Launch, drive and verify Adrift (Godot 4.7.2, Windows) as a real app - headless multiplayer smoke tests, custom multi-instance scenarios with per-instance logs, tiled windowed instances for the user, and screenshots of the title screen, lobby and the platform in space. Use when asked to run, start, play or screenshot the game, or to confirm a change works in the running game rather than only in unit tests.
---

# Running Adrift

Running the game means launching real Godot instances and checking what they did:
log lines for headless runs, screenshots for windowed runs. **Look at every screenshot**;
a blank or black frame means the launch failed.

Godot lives at `%USERPROFILE%\Tools\godot\4.7.2\` (or `$env:GODOT`); `tools/godot_path.ps1`
resolves it. Use the `_console.exe` for headless runs (so stdout can be captured) and the
plain `.exe` for windows the user will look at. The PowerShell scripts need
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\<script>.ps1` on this machine.

## Pick the mode

| Goal | Mode |
|---|---|
| "Does multiplayer still work?" after a networking change | 1. Smoke test |
| Reproduce a specific scenario (late joiner, bad address, timing) | 2. Custom headless run |
| The user wants to see or play it | 3. Windowed instances + capture |
| Screenshot the title screen or lobby without disturbing the desktop | 4. Offscreen frames |
| Look at the platform, characters, planets, lighting | 5. Room preview |
| Check the search terminal or the CRT zoom | 6. Terminal |
| See a whole game: screen, HUD, signs, reveals, win screen | 7. Recorded bot game |

### 1. Smoke test (automated, about 10 s; full game about 30 s)

```powershell
.\tools\smoke_test.ps1 -Clients 3
.\tools\smoke_test.ps1 -Clients 3 -FullGame [-Seed 7] [-Pack movies|actors|history|game_characters] [-Online]
```

Host + N headless clients join, auto-ready and auto-start. Every instance must print
`SMOKE_TEST PASS: game started` and exit 0. Per-instance logs go to `%TEMP%\kftm_smoke_test\`.
With `-FullGame` every instance is an `--auto-play` bot on `--fast-rounds` timers and must
print `SMOKE_TEST PASS: game over after 2 rounds, <n> solved in the last, winner <name>`
(fast rounds play 2). The logs show `[Session] Round n: DEAL/ASK/ANSWER/RESULT/REVEAL`
and the bots' `[GuessBot] Guessing <name> (<n> candidates left)`; with 20-second test
rounds many bots don't solve, which is fine. The headless clients still build the room
(GuessPresenter, GuessHud, SearchStation), so search their logs for `SCRIPT ERROR`.
Smoke tests pass `--offline-portraits` unless `-Online` is given.

To smoke-test a custom pack, write one to the host's `user://identities/<id>.json`
(`%APPDATA%\Godot\app_userdata\Adrift\identities\`), run with `-Pack <id>`, check that
clients print `[Session] Received the host's pack <id> (n entries).`, and delete the file.

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
`[Session] Round N: ASK` (one per phase). Add `--smoke-test` to an instance to make it
exit with 0 on game start and 1 on failure, and print the failure reason.

Launch flags (after `--`): `--host`, `--join=<ip|ip:port|code>`, `--name=`, `--port=`,
`--auto-ready`, `--auto-start`, `--min-players=<n>` (debug builds), `--smoke-test`,
`--smoke-test=game` (exit 0 at GAME_OVER), `--auto-play` (bot), `--fast-rounds` (host,
debug builds), `--seed=<n>`, `--pack=<id>`, `--offline-portraits`, `--no-music`,
`--room-preview=<n>`, `--room-camera=seat|tv|overview|editor`.
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
Get-Process | Where-Object { $_.MainWindowTitle -like "Adrift*" } | Stop-Process -Force
```

### 4. Offscreen frames of one instance

```bash
"$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/menu/f.png" --quit-after 60 -- --no-music
```

This writes `f00000000.png` ... `f00000059.png`; read the last one. A window still opens
briefly. Write the movie path with **forward slashes**; a mangled path makes Godot log
`Condition "d.is_null()"` and write nothing.

- **Title screen** (no flags): "A D R I F T" in pale cyan with "Who am I?" under it, the
  name field, *Host a game* / Port, the join field, *Quit*, over a starfield with the red
  planet on the left and the grey moon (lit from the right) on the right; version bottom right.
- **Lobby**: start a windowed `--host --port=7841 --name=Captain` recording (~120 frames)
  and two headless `--join=127.0.0.1:7841` peers (one `--auto-ready`). Correct: "BOARDING",
  the join addresses and code, *Copy code*, "Database:" with the pack dropdown and *Your
  packs folder*, the player rows (host pale blue, ready green, not ready grey), the status
  line and *Start game* (disabled until everyone is ready) / *Leave*, all over space.

### 5. Room preview (the platform, no network)

```bash
"$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/room/f.png" --quit-after 120 -- --no-music --offline-portraits --room-preview=6 --room-camera=overview
```

Opens the platform with n fake players (you = seat 1) and plays a local game
(`PreviewGuessGame`): you ask first; the fake players ask random stock questions and
answer truthfully, but never guess. Correct `overview` frame: a round dark deck with
glowing blue rings floating in space, the red planet behind, the table with six seated
characters (distinct shirts, hats, CRTs glowing green, drinks), the orb light over the
table, a floating sign with a glowing edge over every head (names; yours "???" with a red
edge), the floating screen on its pylon, the HUD's top bar "ROUND 1/3 Dealing identities"
and the scoreboard. `seat` shows your own CRT with the terminal; `tv` the screen saying
"ROUND 1" / "Who am I? Category: Musicians". Add `--pack=movies` for another pack and
`--fast-rounds` for short timers. Mouse look is off while recording a movie.
The models come from the `blender-pipeline` skill.

### 6. Terminal and CRT zoom

```bash
"$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/editor/f.png" --quit-after 120 -- --no-music --offline-portraits --room-preview=5 --room-camera=editor
```

Starts zoomed into your CRT. Correct: the phosphor terminal fills the screen with a
slight barrel curve and scanlines: "MUSICIANS DATABASE", the count "1263 → 1258 left"
(the others' identities are crossed out already), FILTERS / CLUES / ASK tabs, field
buttons with a value list and IS / IS NOT, the search box and results in fame order
("Michael Jackson 1958 · solo artist"), GUESS at the bottom right. From your first turn
the ASK pane shows "YOUR TURN" and the stock questions; while someone else's question is
up, an answer bar (YES / NO / DON'T KNOW) sits above GUESS. To see the zoom itself, start
at `seat` and press **E** in a window. The automated checks are
`tests/unit/test_crt_zoom.gd`, `test_search_terminal.gd` and `test_guess_room.gd`.

### 7. Recorded bot game

One windowed host records frames while headless bots play; everyone is a bot, so the
recording needs no input.

```bash
S="C:/<scratchpad>/game"; mkdir -p "$S"
"$G" --path . --resolution 960x540 --fixed-fps 15 --write-movie "$S/f.png" --quit-after 900 -- --no-music --offline-portraits --host --port=7820 --name=Host --auto-start --auto-play --fast-rounds --seed=7 --min-players=4 > "$S/host.log" 2>&1 &
sleep 2
for n in Vega Lyra Nova; do timeout 180 "$GC" --headless --path . -- --offline-portraits --join=127.0.0.1:7820 --name=$n --auto-ready --auto-play --min-players=4 > "$S/$n.log" 2>&1 & done
wait
```

(`$G` = the windowed exe, `$GC` = the console exe.) `--fixed-fps` slows game time to the
frame rate, so the bots need a long `timeout`. 900 frames cover a 4-player fast game
(2 rounds). Make a contact sheet of every ~60th frame (PIL is installed) and look at it.
Correct: the lobby first; then the bot host is mostly zoomed into its terminal (clue log
filling up with "→ NO" / "→ YES" and FILTER buttons, "Wrong guess. Locked until your next
turn.", "SOLVED: you are <name>."); between turns the floating screen shows the answer
("NO", "0 yes · 3 no · 0 don't know"); at the end the platform overview with the end
panel ("YOU WIN" or the winner, the standings, *Play again* / *Leave* on the host).

## Pitfalls (all hit in practice)

- **The user may be clicking the windows.** In mode 3 the user often interacts. Before
  calling a state a bug, reproduce it headless (mode 2) or capture right after launch.
- **Shared log file.** Every instance writes `user://logs/godot.log`
  (`%APPDATA%\Godot\app_userdata\Adrift\logs\`), so concurrent logs overwrite each other.
  Capture stdout per instance instead.
- **Output floods.** From PowerShell, redirect to a file (`*> file.log`) and search it;
  piping straight into `Select-String` once crashed PowerShell with a stack overflow.
- **Engine noise on kill.** When `timeout` kills an instance, Godot prints
  `BUG: Unreferenced static string`, `RID allocations ... leaked` and similar. They come
  from the forced shutdown, not from the game.
- **Multi-monitor positions.** Godot's `--position` counts from the virtual desktop's
  top-left. `run_local.ps1` already offsets for this.
- **Paths with spaces.** The project folder contains spaces. `Start-Process -ArgumentList`
  does not quote for you; wrap the path in escaped quotes the way `tools/run_local.ps1` does.
- **Exit codes from Start-Process.** Read `$proc.Handle` right after starting, or
  `$proc.ExitCode` comes back empty.
- **Synthetic input in tests.** Push events to the root with `push_input(event, true)`.
- **Fresh clone or new assets.** Run `--headless --import` once (all `tools/*.ps1`
  scripts do) before launching, or global class names won't resolve.
- **Shell variables in `rm -rf`.** Use a fresh scratch folder per run instead of deleting.

## Keep this skill current

When new screens or launch flags arrive, update the modes above with how to reach and
verify them, including what a correct screenshot looks like.
