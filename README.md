# Adrift

An online "Who am I?" party game for 3–8 players. You wake up on a round platform
floating in deep space, at a table of old CRT terminals, with a red planet and its moon
hanging in the dark. Everyone has a secret identity, a famous musician, movie, actor,
historical figure or game character, floating on a sign above their head. Everyone can
read yours except you. Ask yes/no questions, search the database on your terminal, and
guess who you are before the others do.

Built with **Godot 4.7.2** (GDScript). Windows first; Linux/macOS later. Designed so Steam
integration (GodotSteam) can be added without rewriting the game. Rules and numbers:
[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md).

## How to play

1. **Deal.** Everyone gets an identity from the host's chosen database. The signs light up.
2. **Your turn.** Ask one yes/no question: type your own ("Do I wear a hat?") or pick a
   stock question ("Was I born before 1980?"). You have 25 seconds.
3. **Everyone else's turn.** When someone else asks, answer **1** Yes, **2** No or
   **3** I don't know (press again to change). Answering with the majority earns a point
   or two.
4. **Search.** Press **E** or click your monitor to zoom into the database: filter by
   field, turn clear answers into filters, cross candidates out with a right-click.
   **Esc** looks up again.
5. **Guess** any time: select a candidate and press GUESS. Right scores up to 100 points
   (fewer the more questions you asked, +25 for the first in the round); wrong costs 15 and
   your guess until your next turn.
6. Three rounds; most points wins. The host's *Play again* returns everyone to the lobby.

**Tab** cycles the camera (your seat, the screen, an overview of the table) at any time.

### Databases

Musicians (default), Movies, Actors, Historical figures and Video game characters, built
from [Wikidata](https://www.wikidata.org) (CC0). The host can add their own ("Our
friends") with the lobby's *Your packs folder* button; only the host needs the file.
Portraits come from Wikimedia Commons at run time; turn them off with
`--offline-portraits` or `online_portraits=false` in `settings.cfg`.

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

Settings, custom packs and the portrait cache live in
`%APPDATA%\Godot\app_userdata\Adrift\`.

## Running the tests

Unit tests use [GUT](https://github.com/bitwes/Gut) and live in `tests/unit/`.

```powershell
.\tools\run_tests.ps1
```

## Building a Windows executable

```powershell
.\tools\build_windows.ps1          # release build
.\tools\build_windows.ps1 -Debug   # debug build (shows console)
```

Output: `builds/windows/Adrift.exe` (single file, game data embedded).

## Previewing the platform

Open the platform directly with fake players, no network needed. It plays a local round:
you ask first, and the fake players ask and answer stock questions.

```powershell
& $env:GODOT --path . -- --room-preview=6                        # first-person seat view
& $env:GODOT --path . -- --room-preview=6 --room-camera=overview # or tv, editor
& $env:GODOT --path . -- --room-preview=6 --pack=movies
```

## Models

The player character, hat, table props and planets come from our own Blender files, kept
outside the repo. To rebuild `assets/models/` after changing them, see
[docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md):

```powershell
.\tools\build_models.ps1
```

## Testing multiplayer locally

You can run several instances on one machine; they connect over `127.0.0.1`.

```powershell
.\tools\run_local.ps1                 # host + 2 clients (3 is the minimum to start)
.\tools\run_local.ps1 -Clients 5      # host + 5 clients
.\tools\run_local.ps1 -Bots -FastRounds  # play the host against bots on short timers
```

**Automated smoke test:** headless instances join, ready up and start; `-FullGame` makes
every instance a bot and plays a whole game on short timers. Run both before merging
networking changes.

```powershell
.\tools\smoke_test.ps1 -Clients 3
.\tools\smoke_test.ps1 -Clients 3 -FullGame [-Pack movies] [-Online]
```

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
| `--auto-play` | A bot plays for this instance (stock questions, truthful answers, guesses) |
| `--fast-rounds` | Short phase timers (host, debug builds only) |
| `--seed=<n>` | Fixed random seed for the deal and turn order (host) |
| `--pack=<id>` | The identity pack (host): `musicians`, `movies`, `actors`, `history`, `game_characters`, or a custom pack's id |
| `--offline-portraits` | Never download portraits |
| `--no-music` | No background music (the client windows of `run_local.ps1` use it) |
| `--room-preview=<n>` | Open the platform directly with n fake players (no network) |
| `--room-camera=<view>` | First camera: `seat` (default), `tv`, `overview` or `editor` |

## Playing over the internet (before Steam)

Connections are direct (ENet over UDP). The host either forwards **UDP port 7777** on
their router, or everyone joins the same virtual LAN with a tool like
[Tailscale](https://tailscale.com) or [ZeroTier](https://www.zerotier.com). The lobby
shows the host's addresses with a **join code** for each (the IP and port in a friendlier
form, e.g. `60N1J-907KH`), so it only works where that address is reachable.

## Project structure

```
addons/        third-party Godot addons (GUT now, GodotSteam later)
assets/        models (player, props, planets), music, textures
data/          identity packs (identities/) and the example custom pack
docs/          design and asset pipeline
src/
  autoload/    global singletons (Settings, Platform, Net, Session, App)
  core/        pure game rules: GuessMatch, identity packs, queries; no nodes, no networking
  net/         transport abstraction (ENet now, Steam later), server controller, protocol
  platform/    platform services abstraction (Null now, Steam later)
  guess/       the search terminal and the portrait cache
  world/       the platform, seats, CRT monitors, the screen, space backdrop, camera rig
  ui/          title screen, lobby, HUD
  audio/       background music
  util/        launch options, the bot
tests/unit/    GUT unit tests
tools/         helper scripts (tests, build, local multiplayer, smoke test, models, packs, music)
tools/blender/ Blender export scripts (run headless by tools/build_models.ps1)
```

## Credits

All third-party assets and their licenses are listed in [CREDITS.md](CREDITS.md).

## License

Copyright © the Adrift developers. All rights reserved.
Third-party components are under their own licenses (see CREDITS.md).
