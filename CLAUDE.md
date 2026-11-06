# CLAUDE.md — Killing for the Memes

Context for AI coding sessions. Keep this file current when architecture or conventions change.

## What this is

Online multiplayer (3–8 players) dark-comedy party game. Players chained around a table in a
3D room make memes on in-world CRT monitors (camera zooms into a 2D editor); memes are judged
on a wall TV with a spotlight; worst meme's author dies a cartoon death; last survivor wins.
Full design: `docs/GAME_DESIGN.md` (source of truth for rules and default numbers).

## Hard requirements

- Downloadable **desktop app** (Windows first). Not a browser game.
- Online multiplayer, **server-authoritative** (the hosting player is the server).
- Must be Steam-ready: Steamworks lobbies, invites, P2P networking and achievements must be
  addable **without touching game logic**. All networking goes through the transport layer.
- **Everything original.** Nothing from Saw or other copyrighted media. Only assets whose
  license allows commercial use; every third-party asset goes in `CREDITS.md` in the same commit.

## Stack

- Godot **4.7.2** (pinned), typed GDScript, Forward+ renderer.
- GUT 9.7.1 for unit tests (`addons/gut`, dev only, excluded from exports).
- Later: GodotSteam (GDExtension) + its `SteamMultiplayerPeer`.
- Godot on this dev machine: `%USERPROFILE%\Tools\godot\4.7.2\` (or `$env:GODOT`).

## Commands

```powershell
.\tools\run_tests.ps1                # import + run all unit tests headless
.\tools\smoke_test.ps1 -Clients 3    # headless host + 3 clients must join, ready and start
.\tools\run_local.ps1 -Clients 2     # host + 2 clients in tiled windows for manual testing
.\tools\build_windows.ps1 [-Debug]   # export builds/windows/KillingForTheMemes.exe
```

Run `run_tests.ps1` before every commit and `smoke_test.ps1` before merging networking
changes. Developer launch flags (`--host`, `--join=`, `--auto-ready`, …) are documented in
`src/util/launch_options.gd` and the README.

Godot headless output can be very large; when running it from PowerShell, redirect to a
file (`*> file.log`) and search the file instead of piping straight into `Select-String`.

To run, drive or screenshot the actual game (headless scenarios, windowed instances, window
captures), use the project skill `.claude/skills/run-game/`. Update it whenever a milestone
adds new screens or launch flags.

## Architecture

Layers, with dependencies pointing **downward only**:

```
ui/, world/, meme/        presentation: read Session state, call Session methods, listen to signals
        │
autoload/App              scene flow (menu → lobby → room) driven by Session signals
autoload/Session          RPC bridge: the ONLY place with @rpc functions; holds the client mirror
        │                 and (on the host) a ServerController
net/ServerController      authoritative logic on the host; validates intents, emits what to broadcast
autoload/Net + transports connection lifecycle; installs the MultiplayerPeer from a NetTransport
        │
core/                     pure rules: RefCounted classes, no Nodes, no networking, no scene tree
```

Autoload order: `Settings`, `Platform`, `Net`, `Session`, `App`.

- **`src/core/`** — game rules as plain `RefCounted` classes. Deterministic given inputs
  (inject RNG/seed, pass `now` in). Fully unit-tested. Never references `multiplayer`,
  nodes or UI.
  - `GameMatch`: the round state machine (WAITING → PROMPT → CREATE → SPOTLIGHT×n →
    ELIMINATION → … → GAME_OVER). The server calls `update(now)` every frame and the intent
    methods (`submit_meme`, `cast_vote`, `shoot`, `remove_player`), which take untrusted
    `Variant` input and return an `IntentResult`. `to_snapshot(now, viewer_id)` is the
    per-player view with hidden information removed; never send anything else to clients.
  - `Scoring`: score formula and elimination choice. `GameConfig` (Resource): all tunables.
  - `MemeSpec`, `PlayerState`, `PromptDeck` (packs in `data/prompts/*.json`), `LobbyState`.
  - Test style: `tests/unit/test_game_match.gd` for rules, `test_game_simulation.gd` for
    seeded random full games with invariant checks. Add both kinds for new rules.
- **`src/net/`** — `NetTransport` base class with `EnetTransport` now and `SteamTransport`
  (stub) later. A transport only creates a Godot `MultiplayerPeer` (reported through the
  `peer_ready`/`failed` signals, because Steam lobby creation is async) and reports join info.
  RPC code never knows which transport is active; `Net.set_transport()` swaps it.
  - `ServerController` (host only) owns the authoritative state, validates every intent
    (RPC arguments arrive as `Variant` and are type-checked), and emits signals saying what
    to broadcast. It never touches the network, so it is unit-tested directly.
  - `Session` autoload is the RPC bridge on every peer: client→server intents via
    `rpc_id(1, …)`, server→client snapshots via `rpc_id(peer, …)`. The host calls
    `ServerController` directly instead of sending RPCs to itself. Clients keep a read-only
    mirror (`Session.lobby`) rebuilt from snapshots, and the UI only reads that mirror.
  - Clients send **intents** only (`request_join`, `set_ready`, later `submit_meme`,
    `cast_vote`, `shoot`…), never state. `server_relay` is off: clients never talk to each other.
  - All RPC method names and payload shapes are listed in `src/net/protocol.gd`. Bump
    `Protocol.VERSION` when any of them change.
  - `JoinCode` turns IPv4 + port into a 10-character code (Crockford base32). It is a
    convenience only, not a matchmaking service.
- **`src/platform/`** — `PlatformService` (achievements, friend names, invites, rich presence)
  with `NullPlatform` now, `SteamPlatform` later.
- **`src/meme/`** — memes travel over the network as a small `MemeSpec` dictionary
  (template id + captions), never as images. Every client renders them locally.
- **`src/world/`** — 3D room. The CRT screen shows a `SubViewport` that hosts the 2D meme
  editor; the zoom transition tweens the camera to a pose where the screen fills the view,
  then hands the same viewport to fullscreen with input (reverse on exit).
- **`src/activities/`** — post-MVP "while you wait" activities as self-contained plug-ins
  sharing a base class, registered with the server so it can validate their intents.
- **`src/autoload/`** — thin singletons only (`Net`, `Platform`, `Session`, `Settings`).
  No game rules in autoloads.

## Conventions

- **Typed GDScript everywhere** (`untyped_declaration` warning is on): typed vars, params,
  returns. `class_name` for reusable types. Tabs for indentation.
- Files/folders `snake_case`; classes `PascalCase`; constants `UPPER_SNAKE`;
  private members/methods prefixed `_`; signals past tense (`player_joined`, `vote_cast`).
- Doc comments (`##`) on every class and on non-obvious public methods. Comment *why*, not *what*.
- Scenes own their script in the same folder (`foo.tscn` + `foo.gd`).
- Use `%UniqueName` node access instead of long `$Path/To/Node` chains.
- Communicate upward with signals, downward with method calls. No `get_parent()` reaching.
- Tunable numbers (timers, points, bullets) live in the game config resource, not literals.
- All user-facing strings go through `tr()`-ready text (English only for now).
- Commit `.uid` files generated by Godot alongside their scripts.
- Never commit `.godot/`, `builds/`, or credentials.

## Git workflow

- `main` is always runnable. One feature branch per milestone/feature (`feature/m1-networking`).
- Small, logical commits with imperative messages (`Add ENet transport`), then merge to `main`.
- Add/update unit tests with every `core/` change; run `tools/run_tests.ps1` before committing.

## Milestones

- [x] **M0** Project setup: Godot project, docs, GUT, Windows export preset
- [x] **M1** Networking skeleton: main menu, host/join (IP or code), lobby with names, ready-up,
  join rejection (version/full/started/timeout), local multi-instance + smoke test scripts.
  The room scene (`src/world/room/`) is still a 2D placeholder.
- [x] **M2** Core rules (pure, unit-tested): state machine, scoring, bullets, elimination, win,
  disconnects, per-player snapshots, default prompt pack. Not wired to the network yet (M5).
- [ ] **M3** 3D greybox room: auto-placed seats, wall TV, host placeholder, lighting, camera rig
- [ ] **M4** Meme editor + CRT zoom transition
- [ ] **M5** Full round loop wired end to end, win screen
- [ ] **M6** Hardening (disconnects, timeouts), SFX, Windows build, playtest
- Post-MVP: Steam (GodotSteam), ghosts, activities, HP mode, GIFs, prompt packs, Linux/macOS

## Decisions log

- Godot 4 + typed GDScript over C# (GodotSteam is GDScript-first; simpler exports).
- Join "code" before Steam = encoded IP:port. Real codes/NAT traversal arrive with Steam relay.
- Meme font: an OFL Impact-alike (e.g. Anton) — Impact itself is not redistributable.
- Eliminated players spectate and can still vote in the MVP (prevents final 1v1 deadlock).
- Code is proprietary (all rights reserved); no open-source license.
- No Git LFS until binary assets grow large.
- Do NOT use `MultiplayerPeer.refuse_new_connections` to lock a started game: ENet lets the
  peer connect and then silently ignores it, so the client hangs. Let late joiners connect;
  `ServerController` rejects them with a readable reason and Session kicks them.
- The host never needs to "ready up"; pressing Start is its readiness.
- Use `JSON.new().parse()`, not `JSON.parse_string()`, for untrusted JSON: the latter logs an
  engine error on bad input, and GUT fails tests on unexpected engine errors.
- `Array.filter()`/`map()` return untyped arrays: `assign()` them into `Array[int]` etc.
  instead of assigning directly, which fails at runtime.
