# CLAUDE.md — Adrift

Context for AI coding sessions. Keep this file current when architecture or conventions change.

## What this is

**Adrift**: an online multiplayer (3–8 players) "Who am I?" party game. Players sit
chained around a table of CRT terminals on a round platform floating in deep space (a red
planet and its moon, a starfield). Everyone gets a secret identity from a Wikidata-built
pack that floats on a sign over their head; everyone can read it except its owner. Players
ask yes/no questions, the others answer, and each searches the identity database on their
own CRT (the camera zooms into a 2D terminal) and guesses. Points over three rounds;
nobody dies. Tone: mysterious, a little melancholy, no violence.
Full design: `docs/GAME_DESIGN.md` (source of truth for rules and default numbers).

History: until 2026-11-08 this was "Killing for the Memes", a meme game with guns and
deaths, with "Who am I?" as a second mode. The meme game was deleted (branch
`feature/space`); only the guessing game remains. The repo folder and GitHub repo keep the
old name, and so does the external assets folder.

## Hard requirements

- Downloadable **desktop app** (Windows first). Not a browser game.
- Online multiplayer, **server-authoritative** (the hosting player is the server).
- Must be Steam-ready: Steamworks lobbies, invites, P2P networking and achievements must be
  addable **without touching game logic**. All networking goes through the transport layer.
- **Everything we ship is original** or properly licensed, and every third-party asset
  goes in `CREDITS.md` in the same commit. The game is for friends, not for sale, but
  don't recreate a specific existing game. Portraits are fetched at run time from
  Wikimedia Commons and never shipped.

## Stack

- Godot **4.7.2** (pinned), typed GDScript, Forward+ renderer.
- GUT 9.7.1 for unit tests (`addons/gut`, dev only, excluded from exports).
- Later: GodotSteam (GDExtension) + its `SteamMultiplayerPeer`.
- Godot on this dev machine: `%USERPROFILE%\Tools\godot\4.7.2\` (or `$env:GODOT`).
- Blender 2.81 at `D:\Blender\blender.exe` (or `$env:BLENDER`), headless only, for the model
  pipeline. Model sources live outside the repo in `D:\Killing-For-The-Memes-Assets\`.

## Commands

```powershell
.\tools\run_tests.ps1                # import + run all unit tests headless
.\tools\smoke_test.ps1 -Clients 3    # headless host + 3 clients must join, ready and start
.\tools\smoke_test.ps1 -Clients 3 -FullGame [-Pack movies]   # ...and bots play a whole game to GAME_OVER
.\tools\smoke_test.ps1 -FullGame -Online      # same, with portraits from Commons (needs internet)
.\tools\run_local.ps1 -Clients 2     # host + 2 clients in tiled windows for manual testing
.\tools\run_local.ps1 -Bots -FastRounds      # play the host against bot clients
.\tools\build_windows.ps1 [-Debug]   # export builds/windows/Adrift.exe
.\tools\build_models.ps1 [-SkipBake] [-PropsOnly] # Blender sources -> assets/models/** (docs/ASSET_PIPELINE.md)
.\tools\build_identities.ps1         # rebuild the identity packs from Wikidata (Python, internet)
python tools/make_music.py           # re-render the background music loop (assets/music/)
```

PowerShell's execution policy blocks the scripts here; run them as
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\<script>.ps1`.

To look at the platform without networking: `--room-preview=<n> [--pack=<id>]
[--room-camera=seat|tv|overview|editor]` (a local game against fake players; `editor`
starts zoomed into your terminal).

Run `run_tests.ps1` before every commit and `smoke_test.ps1` (lobby and `-FullGame`)
before merging networking changes. Developer launch flags (`--host`, `--join=`,
`--auto-ready`, …) are documented in `src/util/launch_options.gd` and the README.
After adding a new asset (WAV, PNG, glb), run the tests twice: the first import pass can
report a spurious parse error.

Godot headless output can be very large; when running it from PowerShell, redirect to a
file (`*> file.log`) and search the file instead of piping straight into `Select-String`.

To run, drive or screenshot the actual game (headless scenarios, windowed instances, window
captures), use the project skill `.claude/skills/run-game/`. Update it whenever new
screens or launch flags arrive.

## Architecture

Layers, with dependencies pointing **downward only**:

```
ui/, world/, guess/       presentation: read Session state, call Session methods, listen to signals
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
  - `guess/GuessMatch`: the round state machine (WAITING → DEAL → (ASK → ANSWER →
    RESULT)×n → REVEAL → … → GAME_OVER), phase timers plus a round clock, points. The
    server calls `update(now)` every frame and the intent methods (`ask`, `answer`,
    `guess`, `remove_player`), which take untrusted `Variant` input and return an
    `Intent.Result` (`core/intent.gd`). `to_snapshot(now, viewer_id)` is the per-player
    view; it never contains the viewer's own unsolved identity. Never send anything else
    to clients. `GuessMatch.sanitize_question()` cleans typed questions.
  - `guess/GuessView`: a client's parsed snapshot plus client-side copies of the rules
    (`can_ask`, …). The presentation diffs a view against the previous one to find new
    questions, answers, solves and reveals, so the server sends no separate events.
  - `guess/IdentityPack` loads and validates `data/identities/<pack>.json` (typed fields,
    entries, stock questions); `IdentityFilter` is one condition (an unknown value never
    crosses an entry out; `negated()` is what a "No" means); `IdentityQuery` is a terminal
    search (filters, name text, struck-out candidates, fame order); `IdentityDeck` deals
    distinct identities from the best known `deal_pool`. `Portrait.url_for()` rebuilds a
    Commons thumbnail URL from an entry's `image`.
  - Shipped packs: musicians (default), movies, actors, history, game_characters. Custom
    packs (`user://identities/<id>.json`, host only; example in `data/identity_examples/`)
    travel as `pack_text` in `_rpc_game_started` and clients validate them with
    `IdentityPack.receive()`; `forget_received()` on leaving. Every client loads shipped
    packs from its own files (`IdentityPack.load_pack`, cached).
  - `PlayerState` (PLAYING/LEFT, score), `LobbyState` (players, ready, the host's `pack`),
    `GameConfig` (Resource): all tunables.
  - Test style: `tests/unit/test_guess_match.gd` for rules, `test_guess_simulation.gd`
    for seeded random full games with invariant checks. Add both kinds for new rules.
- **`src/net/`** — `NetTransport` base class with `EnetTransport` now and `SteamTransport`
  (stub) later. A transport only creates a Godot `MultiplayerPeer` (reported through the
  `peer_ready`/`failed` signals, because Steam lobby creation is async) and reports join info.
  RPC code never knows which transport is active; `Net.set_transport()` swaps it.
  - `ServerController` (host only) owns the authoritative state, validates every intent
    (RPC arguments arrive as `Variant` and are type-checked), and emits signals saying what
    to broadcast. It never touches the network, so it is unit-tested directly. It owns the
    `guess_match`: Session calls `update(now)` and `flush()` every frame, and any change
    (phase, intent, player leaving) emits one `match_changed` per frame, on which Session
    sends every player their own `snapshot_for(id, now)`. `handle_set_pack` is host-only
    and lobby-only.
  - `Session` autoload is the RPC bridge on every peer: client→server intents via
    `rpc_id(1, …)`, server→client snapshots via `rpc_id(peer, …)`. The host calls
    `ServerController` directly instead of sending RPCs to itself. Clients keep a read-only
    mirror (`Session.lobby`, `Session.guess_view`) rebuilt from snapshots and emit
    `guess_updated(view, previous)`. Clients count `time_left` down locally.
  - Clients send **intents** only (`request_join`, `set_ready`, `set_pack` (host),
    `ask_question`, `ask_stock_question`, `answer_question`, `guess_identity`, the host's
    `return_to_lobby`), never state. `server_relay` is off: clients never talk to each other.
  - All RPC method names and payload shapes are listed in `src/net/protocol.gd`. Bump
    `Protocol.VERSION` (now 9) when any of them change.
  - `JoinCode` turns IPv4 + port into a 10-character code (Crockford base32). It is a
    convenience only, not a matchmaking service.
- **`src/platform/`** — `PlatformService` (achievements, friend names, invites, rich presence)
  with `NullPlatform` now, `SteamPlatform` later.
- **`src/guess/`** — `terminal/SearchTerminal` (800x600 Control on the CRT): FILTERS /
  CLUES / ASK panes, results with crossing out, an answer bar, GUESS; it emits
  `ask_requested`, `stock_requested`, `answer_requested`, `guess_requested`.
  `portraits/PortraitCache` downloads each Commons thumbnail once per machine into
  `user://portrait_cache/` (retries 429/503, `static var offline` for tests). Wikimedia
  answers 429 unless the User-Agent (`PortraitCache.USER_AGENT`) carries a contact, which
  is the public repo URL. Portraits show only when `App.online_images_allowed()`.
- **`src/world/`** — the 3D scene.
  - `space/SpaceBackdrop`: the starfield sky (`space_sky.gdshader`, own procedural
    stars and nebula), a directional sun, and the artist's planets from
    `assets/models/planets/` (baked albedo + `planet.gdshader` fresnel rim lit on the sun
    side; rim colours from `planets.json`), turning slowly. `SpaceBackdrop.environment()`
    is the shared Environment. `space/SpaceView` is the drifting camera + backdrop behind
    the title screen and the lobby (a Node3D under their Control root).
  - `room/room.gd` (`GameRoom`) builds the platform in code (deck, glowing seams and edge
    ring, tapered underside, a hovering orb light over the table), adds the backdrop with
    its own WorldEnvironment (SSAO on top), and places one `Seat` per player with
    `SeatLayout` (an arc that leaves the screen side open). A seat holds the chair, a
    drink (the artist's props, `Seat.drink_index`), `PlayerAvatar` (the artist's model,
    tinted per seat by vertex-colour clothing masks, wearing the artist's hat), keyboard,
    `CrtMonitor`, `WristChain`s and the floating `IdentityPlacard` (`Seat.show_placard`).
    Avatars rest relaxed (Meshy idles, occasional sip) or type; solvers and winners
    `celebrate()`, wrong guessers `flinch()`. Your own body always types while the camera
    is in its head. Chair, table and camera sizes come from `player_metrics.json`.
  - `room/GuessPresenter` drives the room from `GuessView`s (screen captions, spotlight
    on the asker, camera, placards, the terminal); it reads a duck-typed `source`
    (Session, or `PreviewGuessGame` for `--room-preview`). `ui/hud/GuessHud` is the overlay.
  - `wall_tv/WallTv`: the floating screen on a pylon (`show_caption()`), its picture a
    `SubViewport` through the CRT shader.
  - `room/CrtStation` → `SearchStation` puts the terminal in a `SubViewport` that is the
    picture on the local player's CRT. `crt/CrtZoom` glides the camera until the screen
    fills `FILL` of the view, then shows the same texture fullscreen through
    `crt_overlay.gdshader` and forwards input (`push_input`, mouse mapped through
    `CrtMonitor.curve_uv`, the same barrel curve as both shaders). Escape reverses it.
  - `CameraRig` glides between seat, screen and overview poses with mouse drift.
- **`src/ui/`** — title screen (`main_menu`: "ADRIFT" / "Who am I?" over a SpaceView),
  lobby (pack picker, *Your packs folder*), `hud/GuessHud`, `crt/CrtTheme` (the phosphor
  look), `theme/main_theme.tres` (deep blue panels, starlight text).
- **`src/util/`** — `LaunchOptions` and `guess_auto_player.gd`, the `--auto-play` bot
  (asks stock questions, answers them truthfully, filters, guesses).
- **`src/audio/`** — `Music`: the background loop (`assets/music/forgotten_rooms.wav`,
  slow, melancholy and mysterious, composed in code by `tools/make_music.py`). App owns
  the player; volume is `Settings.music_volume` (0 = off). No music when headless or with
  `--no-music`. There are no sound effects.
- **`src/activities/`** — post-MVP "while you wait" activities as self-contained plug-ins.
- **`src/autoload/`** — thin singletons only (`Net`, `Platform`, `Session`, `Settings`,
  `App`). No game rules in autoloads.

## Conventions

- **Typed GDScript everywhere** (`untyped_declaration` warning is on): typed vars, params,
  returns. `class_name` for reusable types. Tabs for indentation.
- Files/folders `snake_case`; classes `PascalCase`; constants `UPPER_SNAKE`;
  private members/methods prefixed `_`; signals past tense (`player_joined`, `vote_cast`).
- Doc comments (`##`) on every class and on non-obvious public methods. Comment *why*, not *what*.
- Scenes own their script in the same folder (`foo.tscn` + `foo.gd`).
- Use `%UniqueName` node access instead of long `$Path/To/Node` chains.
- Communicate upward with signals, downward with method calls. No `get_parent()` reaching.
- Tunable numbers (timers, points) live in the game config resource, not literals.
- All user-facing strings go through `tr()`-ready text (English only for now).
- Commit `.uid` files generated by Godot alongside their scripts.
- Never commit `.godot/`, `builds/`, or credentials.

## Git workflow

- `main` is always runnable. One feature branch per milestone/feature (`feature/space`).
- Small, logical commits with imperative messages (`Add ENet transport`), then merge to `main`.
- Add/update unit tests with every `core/` change; run `tools/run_tests.ps1` before committing.

## Milestones

- [x] Project setup, networking skeleton (host/join by IP or code, lobby, ready-up,
  rejections, local multi-instance + smoke tests), the 3D table with the artist's rigged
  character, CRT zoom with input hand-off.
- [x] G1–G4: identity packs, GuessMatch rules, network wiring, the terminal, placards, HUD.
- [x] G5 polish: portraits, five packs, custom packs, background music.
- [x] Space: the meme game removed, the platform in space, title screen and lobby, the
  name Adrift (2026-11-08).
- [ ] Hardening (disconnects, timeouts), sound effects, Windows build, playtest and tuning.
- Later: Steam (GodotSteam), more packs, Linux/macOS.

## Decisions log

- Godot 4 + typed GDScript over C# (GodotSteam is GDScript-first; simpler exports).
- Join "code" before Steam = encoded IP:port. Real codes/NAT traversal arrive with Steam relay.
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
- Character pipeline: our Blender files are the source; a headless Blender script bakes,
  rigs (21 bones from measured landmarks, automatic weights), animates and exports `.glb`.
  Big `.blend` files stay out of git (GitHub's 100 MB limit). Poses are keyed in Blender.
- Clothing is a vertex-colour mask on the one body mesh, tinted per player in a shader.
- The artist's Meshy animations (Mixamo rig) are retargeted onto our own rig in Blender
  (`tools/blender/retarget_mixamo.py`) and pushed out of our table at build time.
- Accessories (the hat) are fitted to the body in Blender and exported in the player's
  rest-pose model space; Godot only attaches them to a bone. The local player's own hat
  is shadow-only in first person.
- The zoom hand-off forwards input with `SubViewport.push_input()` instead of reparenting
  into a `SubViewportContainer`, so the CRT keeps showing the same viewport throughout. A
  container-less SubViewport ignores the mouse until it gets `NOTIFICATION_VP_MOUSE_ENTER`.
  A Control filling a SubViewport sets its `size` (anchors top-left), not full-rect anchors,
  or Godot warns about non-equal opposite anchors.
- Push test input to the root with `push_input(event, true)`: positions must already be in
  the stretched root-viewport space that `_input()` sees (the headless window is tiny).
- Match state reaches clients only as full per-player snapshots, never as events. Effects
  come from diffing two views, so a late or reconnecting client just shows the current
  state, and a lost snapshot is healed by the next one.
- No host character: the hosting player runs the show.
- You can't see your own identity; everyone else can. Questions are always answered by
  players, never by the server. The terminal searches the pack locally.
- Planets: their procedural Blender materials can't go through glTF, so
  `build_planets.py` bakes the base colour (routed into an Emission shader, baked as EMIT)
  and a Godot shader adds the rim glow. Only `planets.blend` is used from the space
  assets (not the spaceship or sci-fi files).
- 2026-11-08: the meme game was removed rather than hidden, so nothing meme-related is
  left to maintain. Renaming `config/name` to "Adrift" moved `user://` to
  `%APPDATA%\Godot\app_userdata\Adrift\` (settings and custom packs start fresh).
