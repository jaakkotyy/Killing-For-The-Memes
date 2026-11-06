# Killing for the Memes

A dark-comedy online multiplayer party game for 3–8 players. You're chained to a chair in a
grimy room; every round everyone makes a meme for the host's prompt, the room votes (and
shoots), and the author of the worst meme dies a ridiculous cartoon death. Last survivor wins.

Built with **Godot 4.7.2** (GDScript). Windows first; Linux/macOS later. Designed so Steam
integration (GodotSteam) can be added without rewriting the game.

> Status: **M5 — full round loop** (host/join, lobby, the 3D room; every round: prompt,
> make a meme on your CRT, vote and shoot while each meme is on the wall TV, the worst
> meme's author dies, last survivor wins, play again. Hardening, sound and a playtest
> build come in M6).

## How to play

1. **Prompt.** The host reads the round's prompt on the wall TV.
2. **Make a meme.** The camera turns to your CRT: press **E** or click the monitor to zoom
   in, pick a template, write captions and press *Submit*. When time runs out, your
   draft is submitted for you. **Esc** looks up again.
3. **Spotlight.** Each meme in turn goes up on the TV. Press **1** (good) or **2** (bad);
   press the same key again to take your vote back. **Space** spends one of your bullets
   on the player in the spotlight (each bullet is worth −3 points to them).
4. **Elimination.** The lowest score dies. Dead players watch and still vote, but can't
   shoot. The last one alive wins; the host can then start another game.

**Tab** cycles the camera (your seat, the TV, an overview of the table) at any time.

### Meme templates

Besides our own templates (shots of this room), the host offers the 40 most popular meme
templates from [Imgflip](https://imgflip.com). The host fetches the list while people
join; every player downloads the images once and keeps them in
`%APPDATA%\Godot\app_userdata\Killing for the Memes\template_cache\`. Without internet the
game falls back to the list saved last time, and then to our own templates only. Turn it
off with `--offline-templates` (or `online_templates=false` in `settings.cfg`). Those
images belong to their owners; see [CREDITS.md](CREDITS.md).

## Requirements

- [Godot 4.7.2 (standard, not .NET)](https://godotengine.org/download/archive/4.7.2-stable/)
- Godot export templates for 4.7.2 (only needed to build an `.exe`):
  Editor → *Manage Export Templates* → *Download and Install*
- Windows 10/11 + PowerShell for the helper scripts in `tools/`

The scripts look for Godot at `%USERPROFILE%\Tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`.
To use another location, set the `GODOT` environment variable to your Godot **console** executable:

```powershell
$env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
```

## Running the game

Open the project in Godot (*Import* → select `project.godot`) and press **F5**.

## Running the tests

Unit tests use [GUT](https://github.com/bitwes/Gut) and live in `tests/unit/`.

```powershell
.\tools\run_tests.ps1
```

You can also run them inside the editor from the **GUT** bottom panel.

## Building a Windows executable

```powershell
.\tools\build_windows.ps1          # release build
.\tools\build_windows.ps1 -Debug   # debug build (shows console)
```

Output: `builds/windows/KillingForTheMemes.exe` (single file, game data embedded).
Or in the editor: *Project → Export… → Windows Desktop*.

## Previewing the 3D room

Open the room directly with fake players, no network needed (the spotlight hops between
players, who flinch):

```powershell
& $env:GODOT --path . -- --room-preview=8                       # first-person seat view
& $env:GODOT --path . -- --room-preview=8 --room-camera=overview # or tv
```

From your seat, press **E** or click your monitor to zoom into the meme editor; **Esc**
looks up again. `--room-camera=editor` starts zoomed in. In debug builds: **Tab** cycles
the camera, **F** makes someone flinch, **G** moves the spotlight.

The meme templates are rendered from the room itself. After changing the room or the
characters, re-render them with `.\tools\capture_templates.ps1` (opens a window briefly).

## Character models

The player character comes from our own Blender files, kept outside the repo. To rebuild
`assets/models/player/` after changing them, see [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md):

```powershell
.\tools\build_models.ps1
```

## Testing multiplayer locally

You can run several instances of the game on one machine; they connect over `127.0.0.1`.

**Script (recommended):** starts a host plus N clients in tiled windows. Clients ready up
automatically; press **Start game** in the host window.

```powershell
.\tools\run_local.ps1                 # host + 2 clients (3 is the minimum to start)
.\tools\run_local.ps1 -Clients 5      # host + 5 clients
.\tools\run_local.ps1 -Clients 1 -MinPlayers 2 -AutoStart
.\tools\run_local.ps1 -Bots -FastRounds  # play the host against bots on short timers
```

**Automated smoke test:** runs headless instances that join, ready up and start a game,
and fails if any of them doesn't get there. `-FullGame` makes every instance a bot and
plays a whole match on short timers; each must reach the win screen. Run both before
merging networking changes.

```powershell
.\tools\smoke_test.ps1 -Clients 3
.\tools\smoke_test.ps1 -Clients 3 -FullGame
.\tools\smoke_test.ps1 -Clients 3 -FullGame -Online   # with Imgflip templates (needs internet)
```

**From the editor:** *Debug → Customize Run Instances…* → enable multiple instances, then
set launch arguments per instance, e.g. `-- --host --name=Host` for the first and
`-- --join=127.0.0.1 --name=Bob --auto-ready` for the others. F5 launches them all.

**By hand:** start the game twice, click *Host game* in one and type `127.0.0.1` in the other.

### Developer launch flags

Pass these after `--` (e.g. `Godot.exe --path . -- --host`):

| Flag | Effect |
|---|---|
| `--host` | Host immediately |
| `--join=<target>` | Join immediately (IP, IP:port or join code) |
| `--name=<name>` | Player name for this instance (not saved) |
| `--port=<port>` | Port to host on (default 7777) |
| `--auto-ready` | Ready up automatically in the lobby |
| `--auto-start` | Host starts as soon as everyone is ready |
| `--min-players=<n>` | Lower the 3-player minimum (debug builds only) |
| `--smoke-test` | Exit 0 once the game starts, non-zero on failure |
| `--smoke-test=game` | Exit 0 once a whole game is over, non-zero on failure |
| `--auto-play` | A bot plays for this instance (random memes, votes and shots) |
| `--fast-rounds` | Short phase timers (host, debug builds only) |
| `--seed=<n>` | Fixed random seed for the match: prompts, spotlight order, tie-breaks (host) |
| `--offline-templates` | Host only our own templates; don't fetch popular ones from Imgflip |
| `--room-preview=<n>` | Open the 3D room directly with n fake players (no network) |
| `--room-camera=<view>` | First room camera: `seat` (default), `tv`, `overview` or `editor` |

## Playing over the internet (before Steam)

Until Steam networking is integrated, connections are direct (ENet over UDP). The host must
either forward **UDP port 7777** on their router, or everyone joins the same virtual LAN with
a tool like [Tailscale](https://tailscale.com) or [ZeroTier](https://www.zerotier.com) and
connects to the host's virtual IP. Steam's relay networking will remove this requirement.

The lobby shows the host's addresses with a **join code** for each. A join code is just
the IP and port written in a friendlier form (e.g. `60N1J-907KH`), so it only works where
that address is reachable. With port forwarding, friends type the host's *public* IP instead.

## Project structure

```
addons/        third-party Godot addons (GUT now, GodotSteam later)
assets/        fonts, models, textures, audio, meme templates
data/prompts/  prompt packs (JSON)
docs/          design documents
src/
  autoload/    global singletons (Settings, Platform, Net, Session, App)
  core/        pure game rules — no nodes, no networking
  net/         transport abstraction (ENet now, Steam later), server controller, protocol
  platform/    platform services abstraction (Null now, Steam later)
  util/        small helpers (launch options)
  world/       3D room, seats, CRT monitors, wall TV, host, camera rig
  meme/        meme editor and renderer, template library
  activities/  modular "while you wait" activities (post-MVP)
  ui/          menus, lobby, HUD, voting, win screen
tests/unit/    GUT unit tests
tools/         PowerShell helper scripts (tests, build, local multiplayer, smoke test, models)
tools/blender/ Blender export scripts (run headless by tools/build_models.ps1)
```

## Credits

All third-party assets and their licenses are listed in [CREDITS.md](CREDITS.md).

## License

Copyright © the Killing for the Memes developers. All rights reserved.
Third-party components are under their own licenses (see CREDITS.md).
