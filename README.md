# Killing for the Memes

A dark-comedy online multiplayer party game for 3–8 players. You're chained to a chair in a
grimy room; every round everyone makes a meme for the host's prompt, the room votes (and
shoots), and the author of the worst meme dies a ridiculous cartoon death. Last survivor wins.

Built with **Godot 4.7.2** (GDScript). Windows first; Linux/macOS later. Designed so Steam
integration (GodotSteam) can be added without rewriting the game.

> Status: **M0 — project setup**. See [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) for the
> design and [CLAUDE.md](CLAUDE.md) for architecture and conventions.

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

## Testing multiplayer locally

_Available from milestone M1 (networking skeleton)._ Planned workflow:

- **From the editor:** *Debug → Customize Run Instances…*, enable multiple instances
  (e.g. 4) and give the first one the argument `--host` and the others `--join=127.0.0.1`.
  F5 then launches all of them.
- **From a script:** `.\tools\run_local.ps1 -Clients 3` starts one host and three clients.

## Playing over the internet (before Steam)

Until Steam networking is integrated, connections are direct (ENet over UDP). The host must
either forward **UDP port 7777** on their router, or everyone joins the same virtual LAN with
a tool like [Tailscale](https://tailscale.com) or [ZeroTier](https://www.zerotier.com) and
connects to the host's virtual IP. Steam's relay networking will remove this requirement.

## Project structure

```
addons/        third-party Godot addons (GUT now, GodotSteam later)
assets/        fonts, models, textures, audio, meme templates
data/prompts/  prompt packs (JSON)
docs/          design documents
src/
  autoload/    global singletons (Net, Platform, Session, Settings)
  core/        pure game rules — no nodes, no networking
  net/         transport abstraction (ENet now, Steam later), server/client controllers
  platform/    platform services abstraction (Null now, Steam later)
  world/       3D room, seats, CRT monitors, wall TV, host, camera rig
  meme/        meme editor and renderer, template library
  activities/  modular "while you wait" activities (post-MVP)
  ui/          menus, lobby, HUD, voting, win screen
tests/unit/    GUT unit tests
tools/         PowerShell helper scripts
```

## Credits

All third-party assets and their licenses are listed in [CREDITS.md](CREDITS.md).

## License

Copyright © the Killing for the Memes developers. All rights reserved.
Third-party components are under their own licenses (see CREDITS.md).
