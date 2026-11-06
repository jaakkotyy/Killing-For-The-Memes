# Asset pipeline: Blender models → Godot

The character models are made in Blender. The source `.blend` files are big (the player
file is ~370 MB because of the high-poly sculpt), so they live **outside the repo** in
`D:\Killing-For-The-Memes-Assets\` (override with `-AssetsDir` or `$env:KFTM_ASSETS`). Back
that folder up separately. Only the exported, game-ready files are committed.

```powershell
.\tools\build_models.ps1             # bake + rig + export (about 1 minute)
.\tools\build_models.ps1 -SkipBake   # keep the committed normal/AO maps
.\tools\build_models.ps1 -PropsOnly  # only the table props (a few seconds)
```

Requires Blender 2.81 or newer (`-Blender` or `$env:BLENDER`, default `D:\Blender\blender.exe`).
The script runs Blender headless and never saves the source file.

## Player (`Player Model.blend` → `assets/models/player/`)

`tools/blender/build_player.py` does, in order:

1. **Bake** the `hires` sculpt onto the UV-mapped `Low` body (Cycles, selected-to-active):
   `player_normal.png` (tangent space) and `player_ao.png`, 2048².
2. **Move to game space:** centre, feet on the floor, face −Y in Blender (= +Z in Godot),
   scale to 1.8 m.
3. **Rig:** builds a 21-bone skeleton (`Hips, Spine, Chest, Neck, Head`, and per side
   `Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes` with `.L`/`.R`) from
   joint landmarks measured on this mesh, then skins with automatic (bone heat) weights.
   The build fails if more than 1 % of vertices end up unweighted.
4. **Clothing masks** in vertex colours, from the bone weights: R = shirt (torso, upper
   arms), G = trousers (hips, legs), B = shoes. The game shader
   (`src/world/player/player_body.gdshader`) tints them per player.
5. **Animations** (aimed poses, keyed): `seated_idle_loop` (breathing), `flinch`,
   `look_up`, `a_pose`. Godot strips `_loop` and makes that one loop, so in game the names
   are `seated_idle`, `flinch`, `look_up`, `a_pose`.
6. **Calibrate and measure** the seated pose: the pelvis drops until the feet touch the
   floor, then `player_metrics.json` records seat height, forearm height, eye and wrist
   positions (Godot model space). The room sizes chairs and the table from it, so changing
   the model or pose never needs hand-tuned numbers in the scene.
7. **Export** `player.glb` (mesh, skin, vertex colours, animations, no materials).

### Landmarks

Joint positions are listed in `LANDMARKS` at the top of the script, in the source file's
coordinates (+X forward, +Y = character's left, feet at z −3.85). They were measured from
horizontal slices of the mesh (centroids of the limb cross-sections). If the body mesh
changes shape, re-measure and update them, then check the previews (`-Preview <dir>`
renders A-pose, seated, seated side and flinch).

### Adding a pose or animation

Poses are dictionaries of **world directions** per bone (Blender game space: −Y forward,
+Z up, +X = character's left); `sided()` mirrors `.L` entries to `.R`. Add a pose, add a
`make_action()` call with keyframes, rebuild, and play it from `PlayerAvatar`.

## Table props (`cup.blend`, `can.blend`, `beer.blend` → `assets/models/props/`)

`tools/blender/build_props.py --prop <name>` runs once per source file. Each file is a small
studio scene; `PROPS` in the script names the objects to keep (floors, lights, cameras and
the beer's bubble particles are dropped). For each prop it:

1. Lowers subdivision to game levels and applies the modifiers, then joins the parts.
2. Decimates to the triangle budget (the can is a 455k-triangle sculpt, now ~4.8k).
3. Scales to real-world size (can 12.2 cm, beer glass 16 cm, saucer 16 cm wide) with the
   origin at the bottom centre, so a prop placed at table height stands on the table.
4. Replaces the Cycles materials with simple game materials (`MATERIALS`: ceramic,
   aluminium, can paint, glass, beer, foam). Glass and beer are alpha-blended and
   single-sided. The can's label is a separate material between two clean edge loops cut
   in after decimation.
5. Exports `<name>.glb` with materials and no textures.

`Seat` puts one drink to the right of each keyboard, chosen by seat (`Seat.drink_index`),
so every client sees the same table.

## Not yet in the pipeline

- `Skull - DeathScene.blend` (1.5 M-triangle skull with a smoke simulation): needs
  decimating and baking; the smoke becomes Godot particles. Planned with the death scenes.
- `Hat - Accessory.blend`: procedural materials need baking; planned as an optional
  accessory on the `Head` bone.
- `Human Eyes.blend`: its iris/sclera textures are missing from the asset folder.

## Pitfalls

- Blender 2.81's Workbench and Eevee renderers crash in background mode
  (`EXCEPTION_ACCESS_VIOLATION`). Previews and bakes use Cycles on the CPU.
- The `hires` object is hidden in the source file; the bake un-hides it in memory.
- `BakeSettings.max_ray_distance` does not exist in 2.81; only `cage_extrusion` is used.
- GitHub rejects files over 100 MB, which is why the `.blend` sources stay out of git.
