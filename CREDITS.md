# Credits & Asset Licenses

Every third-party asset, font, sound, model, image and code library in this repository must be
listed here with its source and license. **Only licenses that allow commercial use** are
permitted (e.g. CC0, CC-BY, OFL, MIT). Record attribution text exactly as the license requires.

## Engine & libraries

| Name | Version | Author | License | Source | Used for |
|---|---|---|---|---|---|
| Godot Engine | 4.7.2 | Godot Engine contributors | MIT | https://godotengine.org | Game engine |
| GUT (Godot Unit Test) | 9.7.1 | Tom "Butch" Wesley & contributors | MIT | https://github.com/bitwes/Gut | Unit tests (dev only, not shipped) |

## Fonts

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| _none yet_ | | | | |

The UI uses Godot's built-in default font (bundled with the engine, covered by the Godot licence).

## 3D models

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| Player character (sculpt, low-poly body, UVs) | jaakkotyy (project owner) | Original work, all rights reserved | Own Blender source, kept outside the repo | `assets/models/player/` |
| Hat (felt hat with band) | jaakkotyy (project owner) | Original work, all rights reserved | Own Blender source (`Hat - Accessory.blend`), kept outside the repo | `assets/models/player/hat.glb` |
| Table props: cup and saucer, soda can, glass of beer | jaakkotyy (project owner) | Original work, all rights reserved | Own Blender sources (`cup.blend`, `can.blend`, `beer.blend`), kept outside the repo | `assets/models/props/` |
| Planets: the red planet and its moon (meshes, procedural materials baked to textures) | jaakkotyy (project owner) | Original work, all rights reserved | Own Blender source (`planets.blend`), kept outside the repo; exported by `tools/blender/build_planets.py` | `assets/models/planets/` |

## Animations

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| Player animations: seated idles, sit and drink, stand, wave and sit down | Generated with [Meshy](https://www.meshy.ai) by jaakkotyy (project owner) | Owned by the project owner: generated on a paid Meshy plan, whose output belongs to the user with full commercial rights and no attribution required (free-plan output would be CC BY 4.0). Credited here anyway. | `Meshy_AI_Player_Model_20261106_animated_mixamo_All_animation.fbx`, kept outside the repo; retargeted onto our rig by `tools/blender/retarget_mixamo.py` | `assets/models/player/player.glb` |
| Player animations: typing idle, flinch, look up | jaakkotyy (project owner) | Original work, all rights reserved | Keyed by `tools/blender/build_player.py` | `assets/models/player/player.glb` |

## Textures & images

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| _none (third-party)_ | | | | |

The starfield and nebula sky is drawn by our own shader (`src/world/space/space_sky.gdshader`).

## Data

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| Identity packs (musicians, movies, actors, historical figures, video game characters: names, years, countries, genres, roles, awards, series, publishers, sitelink counts) | Wikidata contributors | CC0 1.0 (public domain) | https://www.wikidata.org, built by `tools/build_identities.py` | `data/identities/*.json` |

The packs store Wikimedia Commons file names for portraits but no images; each Commons
file has its own license, so portraits (if used) are fetched at run time and not shipped.
Video game character names belong to their publishers; the packs only name them as facts
in a guessing game, with no images or other material from the games.

The example custom pack `data/identity_examples/friends.json` is original (made-up people).

### Portraits (not shipped)

| Name | Owner | License | Source | Path |
|---|---|---|---|---|
| Identity portraits (250 px thumbnails) | Each file's author on Wikimedia Commons | Per file (mostly CC BY-SA or public domain); **not checked or attributed per file yet** | `upload.wikimedia.org`, URL rebuilt from the pack's file name | Downloaded at run time to `user://portrait_cache/` |

Before a commercial release, show each portrait's author and license (Commons' API has
them) or turn portraits off.

## Audio

| Name | Author | License | Source | Path |
|---|---|---|---|---|
| Background music "Forgotten Rooms" (melancholy half-time loop, 120 BPM, 112 s) | Composed for this project | Original work, all rights reserved | Synthesised (detuned pads, music box, slow arpeggio, soft drums from noise and sine sweeps, quiet sub, reversed swells, crackle, reverb) by `tools/make_music.py`, standard library only | `assets/music/forgotten_rooms.wav` |

## Original work

Everything not listed above (code, `icon.svg`, scenes, shaders, the rig, animations and
baked maps of the player character) is original work created for this project. The
platform's surfaces use Godot's procedural noise, not image textures.
