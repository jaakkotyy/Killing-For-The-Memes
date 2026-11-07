# CLAUDE.md — Killing for the Memes

Context for AI coding sessions. Keep this file current when architecture or conventions change.

## What this is

Online multiplayer (3–8 players) dark-comedy party game. Players chained around a table in a
3D room make memes on in-world CRT monitors (camera zooms into a 2D editor); memes are judged
on a wall TV with a spotlight; worst meme's author dies a cartoon death; last survivor wins.
Full design: `docs/GAME_DESIGN.md` (source of truth for rules and default numbers).
A second mode is planned: "Who Am I?" guessing with a database search terminal
(`docs/GUESS_MODE.md`, milestones G1–G5).

## Hard requirements

- Downloadable **desktop app** (Windows first). Not a browser game.
- Online multiplayer, **server-authoritative** (the hosting player is the server).
- Must be Steam-ready: Steamworks lobbies, invites, P2P networking and achievements must be
  addable **without touching game logic**. All networking goes through the transport layer.
- **Everything we ship is original.** Nothing from Saw or other copyrighted media. Only assets
  whose license allows commercial use; every third-party asset goes in `CREDITS.md` in the same commit.
  The one exception is opt-out and never shipped: popular meme templates fetched at run time
  from Imgflip, memes from Reddit (via meme-api.com) and GIF templates from GIPHY (`src/meme/online/`). They are other people's
  copyrighted images; their use must be cleared (or the source swapped for a licensed one)
  before a commercial release. Never commit an API key: the GIPHY key lives in the
  `GIPHY_API_KEY` environment variable or the user's `settings.cfg`.

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
.\tools\smoke_test.ps1 -Clients 3 -FullGame   # ...and bots play a whole match to GAME_OVER
.\tools\smoke_test.ps1 -FullGame -Online      # same, with popular templates from Imgflip (needs internet)
.\tools\run_local.ps1 -Clients 2     # host + 2 clients in tiled windows for manual testing
.\tools\run_local.ps1 -Bots -FastRounds      # play the host against bot clients
.\tools\build_windows.ps1 [-Debug]   # export builds/windows/KillingForTheMemes.exe
.\tools\build_models.ps1 [-SkipBake] [-PropsOnly] # Blender sources -> assets/models/** (docs/ASSET_PIPELINE.md)
.\tools\capture_templates.ps1        # re-render the meme templates from the room (opens a window)
.\tools\build_identities.ps1         # rebuild guess mode's identity packs from Wikidata (Python, internet)
```

To look at the 3D room without networking: `--room-preview=<n> [--room-camera=seat|tv|overview|editor]`
(`editor` starts zoomed into your CRT's meme editor).
To change the character models, use the project skill `.claude/skills/blender-pipeline/`.

Run `run_tests.ps1` before every commit and `smoke_test.ps1` (both modes) before merging
networking changes. Developer launch flags (`--host`, `--join=`, `--auto-ready`, …) are documented in
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
  - `MatchView`: a client's parsed snapshot plus the client-side copies of the vote/shoot
    rules. The presentation diffs a view against the previous one to find shots, deaths
    and new spotlights, so the server sends no separate events.
  - `guess/`: guess mode's database (`docs/GUESS_MODE.md`). `IdentityPack` loads and
    validates `data/identities/<pack>.json` (typed fields, entries, stock questions),
    `IdentityFilter` is one condition (an unknown value never crosses an entry out;
    `negated()` is what a "No" means), `IdentityQuery` is a terminal search (filters,
    name text, struck-out candidates, fame order), `IdentityDeck` deals distinct
    identities from the best known `pool_size`.
  - Test style: `tests/unit/test_game_match.gd` for rules, `test_game_simulation.gd` for
    seeded random full games with invariant checks. Add both kinds for new rules.
- **`src/net/`** — `NetTransport` base class with `EnetTransport` now and `SteamTransport`
  (stub) later. A transport only creates a Godot `MultiplayerPeer` (reported through the
  `peer_ready`/`failed` signals, because Steam lobby creation is async) and reports join info.
  RPC code never knows which transport is active; `Net.set_transport()` swaps it.
  - `ServerController` (host only) owns the authoritative state, validates every intent
    (RPC arguments arrive as `Variant` and are type-checked), and emits signals saying what
    to broadcast. It never touches the network, so it is unit-tested directly.
    It owns the `GameMatch`: Session calls `update(now)` and `flush()` every frame, and any
    change (phase, intent, player leaving) emits one `match_changed` per frame, on which
    Session sends every player their own `snapshot_for(id, now)`.
  - `Session` autoload is the RPC bridge on every peer: client→server intents via
    `rpc_id(1, …)`, server→client snapshots via `rpc_id(peer, …)`. The host calls
    `ServerController` directly instead of sending RPCs to itself. Clients keep a read-only
    mirror (`Session.lobby`, `Session.match_view`) rebuilt from snapshots, and the UI only
    reads that mirror (`Session.match_updated(view, previous)`). Clients count `time_left`
    down locally; the editor auto-submits `auto_submit_lead` seconds before the deadline.
  - Clients send **intents** only (`request_join`, `set_ready`, `submit_meme`,
    `cast_vote`, `shoot`, the host's `return_to_lobby`), never state. `server_relay` is off: clients never talk to each other.
  - All RPC method names and payload shapes are listed in `src/net/protocol.gd`. Bump
    `Protocol.VERSION` when any of them change.
  - `JoinCode` turns IPv4 + port into a 10-character code (Crockford base32). It is a
    convenience only, not a matchmaking service.
- **`src/platform/`** — `PlatformService` (achievements, friend names, invites, rich presence)
  with `NullPlatform` now, `SteamPlatform` later.
- **`src/meme/`** — memes travel over the network as a small `MemeSpec` dictionary
  (template id + captions), never as images. Every client renders them locally with
  `MemeRenderer` (template + outlined captions that shrink to fit). `MemeTemplateLibrary`
  reads `data/meme_templates.json`; its `ids()` are what the server allows. Template images
  (`assets/meme_templates/<id>.jpg`) are original: staged shots of our own room, rendered by
  `tools/capture_templates.ps1` (`templates/template_studio.gd`, one `_shot_<id>()` each).
  `online/`: online templates. On the host, `OnlineTemplateSource` fetches Imgflip's top
  stills and, with a GIPHY key (`Settings.get_giphy_api_key()`), reaction GIFs from GIPHY
  while people join (plus random Imgflip template pages and subreddit memes from meme-api.com,
  `RedditCatalogue`, shuffled); each provider falls back to its part of the catalogue saved last time.
  Every online id names its image file (`imgflip-<file>[-png]`, `giphy-<id>`,
  `reddit-<file>-<ext>`), so `TemplateCatalogue.resolve(id)` draws any valid id and the
  server accepts any of them (`MemeTemplateLibrary.accepts`, `GameMatch.template_accepts`).
  `TemplateSearch` (host, App) answers players' editor searches (`Session.search_templates`,
  Imgflip + GIPHY, or `r/<subreddit>`); results join the library with `add_found()`.
  `HttpText` runs the host's GETs in parallel.
  App puts it in the library and `Session.set_template_catalogue()`, and
  `_rpc_game_started` sends it to everyone. `TemplateCatalogue` validates it on both ends,
  per provider: `ImgflipCatalogue`, `GiphyCatalogue` and `RedditCatalogue`, all with URLs
  rebuilt from the id, never taken from data. `TemplateImageCache` downloads each file
  once per machine into `user://template_cache/`, decoding on worker threads: stills stay in
  memory, whole GIFs (`AnimatedTemplate`, the last 4) only while needed. `GifDecoder` is
  our own GIF87a/89a decoder (Godot has none), tested pixel-for-pixel against Pillow with
  `tests/fixtures/gif/` (regenerate with `make_fixtures.py`). The library's
  `image_updated` signal tells the renderer and editor when an image arrives. Online ids
  come first in `ids()`; GIF templates show their still in the list and play in the
  preview and on the TV. `MemeRenderer` letterboxes any aspect inside the 4:3 frame,
  captions on the image. Off with `Settings.online_templates` or `--offline-templates`.
  `editor/MemeEditor` (800x600) edits a local draft, emits `submitted`, and auto-submits
  the draft when its countdown hits zero.
- **`src/world/`** — 3D room. `room/room.gd` builds the greybox room in code and places one
  `Seat` per player with `SeatLayout` (an arc that leaves the TV side open for the host).
  A seat holds the chair, a drink (the artist's props from `assets/models/props/`, picked by
  `Seat.drink_index`), `PlayerAvatar` (the artist's model from `assets/models/player/`,
  tinted per seat by vertex-colour clothing masks, wearing the artist's hat on its Head bone), keyboard, `CrtMonitor` and
  `WristChain`s. An avatar rests either relaxed (one of the artist's Meshy idles per seat,
  with an occasional sip) or typing (`type_on_keyboard()`, during CREATE). Your own body
  always types while the camera is in its head, so a leaning idle never leaves the camera
  inside your skull. The winner `celebrate()`s (stands up and waves). `CameraRig` glides between seat, TV and overview poses with mouse drift.
  Chair, table and camera sizes come from `player_metrics.json` written by the Blender
  export, never from hand-tuned numbers. The room only reads Session state.
  `room/MatchPresenter` drives it from `MatchView`s: TV captions and memes, spotlight,
  camera views, the editor's lock and timer, muzzle flashes
  (`Seat.flash_shot`) and deaths (`PlayerAvatar.die`: puff, slump over the keyboard).
  `MemeStation` (local seat only) puts the `MemeEditor` in a `SubViewport` that is the
  picture on the player's CRT. `crt/CrtZoom` glides the camera until the screen fills
  `FILL` of the view, then shows the same texture fullscreen through `crt_overlay.gdshader`
  and forwards input (`push_input`, mouse mapped through `CrtMonitor.curve_uv`, the same
  barrel curve as both shaders, so nothing jumps). Escape reverses it. The wall TV's
  picture is a `SubViewport` too (`WallTv.show_meme()` / `show_caption()`).
- **`src/ui/`** — main menu, lobby, and `hud/MatchHud` in the room: round, phase, timer,
  bullets, vote/shoot buttons (keys 1, 2, Space), shot toasts, results and the win screen
  (the host's *Play again* returns everyone to the lobby).
- **`src/util/`** — `LaunchOptions` and `AutoPlayer`, the `--auto-play` bot used by the
  full-game smoke test (random template, random votes, sometimes shoots).
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
- [x] **M2** Core rules (pure, unit-tested): state machine, scoring, bullets, elimination, win,
  disconnects, per-player snapshots, default prompt pack.
- [x] **M3** 3D greybox room: auto-placed seats, wall TV, host placeholder, lighting, camera rig,
  the artist's player model rigged/animated via `tools/build_models.ps1`, `--room-preview`.
- [x] **M4** Meme editor + CRT zoom transition: 8 original templates from our own room, editor
  with live preview and auto-submit, zoom with input hand-off.
- [x] **M5** Full round loop wired end to end: per-player snapshots (protocol v2), HUD with
  voting/shooting, presenter choreography, deaths, win screen, play again, bot players and
  a full-game smoke test.
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
- Character pipeline: our Blender files are the source; a headless Blender script bakes,
  rigs (21 bones from measured landmarks, automatic weights), animates and exports `.glb`.
  Big `.blend` files stay out of git (GitHub's 100 MB limit). Poses are keyed in Blender,
  not built procedurally in Godot, so they can be previewed in Cycles renders.
- Clothing is a vertex-colour mask on the one body mesh, tinted per player in a shader,
  instead of separate clothing meshes: one draw call per player and no clipping.
- Meme templates are rendered from our own 3D room (players in poses, the room), not
  downloaded images: always original, always on-style, and re-renderable when the art changes.
- The zoom hand-off forwards input with `SubViewport.push_input()` instead of reparenting
  into a `SubViewportContainer`, so the CRT keeps showing the same viewport throughout. A
  container-less SubViewport ignores the mouse until it gets `NOTIFICATION_VP_MOUSE_ENTER`.
- Push test input to the root with `push_input(event, true)`: positions must already be in
  the stretched root-viewport space that `_input()` sees (the headless window is tiny).
- Popular templates are fetched at run time, not bundled: the images aren't ours to ship,
  and a runtime source can be switched off or swapped for a licensed one without touching
  game logic. Clients download them straight from the image host (memes still travel as
  ids + captions), and validate the host's catalogue so it can only point at Imgflip
  and GIPHY.
- GIFs are decoded by our own GDScript `GifDecoder` on worker threads (a 40-frame 200 px
  GIF takes about 0.4 s): Godot can't load GIFs, and GIPHY's MP4/WebP renditions would
  need video or animated-WebP support Godot doesn't have either.
- The artist's Meshy animations (Mixamo rig) are retargeted onto our own rig in Blender
  (`tools/blender/retarget_mixamo.py`, world rotations relative to the rest pose). We don't
  swap in Meshy's rig and mesh: that keeps the hat bone, clothing masks, metrics and the
  20k-triangle body. The clips are pushed out of our table at build time (less torso lean,
  arms turned at the shoulder), because they were made for a chair without a table.
- Accessories (the hat) are fitted to the body in Blender and exported in the player's
  rest-pose model space; Godot only attaches them to a bone. Refitting never needs
  hand-tuned offsets in Godot. The local player's own hat is shadow-only in first person.
- Match state reaches clients only as full per-player snapshots, never as events. Effects
  (shots, deaths, new spotlights) come from diffing two views, so a late or reconnecting
  client just shows the current state, and a lost snapshot is healed by the next one.
- No host character: the hosting player runs the show. The spotlight is host-paced by
  default (`GameConfig.host_paces_spotlight`): it has no timer (snapshot `time_left` -1,
  `MatchView.timed` false) and ends on `GameMatch.present_next(from_index)`, which only
  the host can send. `from_index` makes a double press harmless. Host-only actions need
  no RPC, because the host runs the server. Bot hosts (`--auto-play`) present after
  `spotlight_duration`, so automated full games still finish.
