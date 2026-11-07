# Asset pipeline: Blender models → Godot

The character models are made in Blender. The source `.blend` files are big (the player
file is ~370 MB because of the high-poly sculpt), so they live **outside the repo** in
`D:\Killing-For-The-Memes-Assets\` (override with `-AssetsDir` or `$env:KFTM_ASSETS`). Back
that folder up separately. Only the exported, game-ready files are committed.

```powershell
.\tools\build_models.ps1             # bake + rig + export (about 1 minute)
.\tools\build_models.ps1 -SkipBake   # keep the committed normal/AO maps
.\tools\build_models.ps1 -PropsOnly  # skip the player: hat and table props (a few seconds)
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
5. **Animations** (aimed poses, keyed): `seated_idle_loop` (breathing, hands on the
   keyboard), `flinch`, `look_up`, `a_pose`. Godot strips `_loop` and makes that one loop,
   so in game the names are `seated_idle`, `flinch`, `look_up`, `a_pose`. Then the
   **retargeted clips** from the Meshy FBX (see below): `relax_still`, `relax_lean`,
   `relax_fidget` (loops), `drink`, `stand_wave`.
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

### Retargeted animations (Meshy / Mixamo FBX)

The artist rigged and animated the player in Meshy, which exports a Mixamo-style rig
(`mixamorig:Hips` ...) with several takes in one FBX:
`<assets>\meshy\Meshy_AI_Player_Model_20261106_animated_mixamo_All_animation.fbx`
(`build_models.ps1 -Animations <fbx>` picks another one). `tools/blender/retarget_mixamo.py`
copies takes onto our rig, so the hat, clothing masks and metrics keep working:

- Each of our bones follows one source bone's **world rotation relative to its rest pose**
  (`BONE_MAP`). Both rigs were made from the same A-posed body, so this keeps twists and
  head turns. Hip motion is scaled to our height and added to our seated hips.
- Each clip is lifted or lowered (by about 1 cm) so the backside rests at our chair's seat
  height in its first frame.
- The takes were made for a chair without a table. The script keeps them out of ours
  (`TABLE_*` in `build_player.py`, which must match `room.gd`). If the head or torso goes
  into the table top, the torso's lean is scaled down (`relax_lean` and `relax_fidget` keep
  55 %). If a hand would sink into the table top more than 10 cm in from the edge, that
  arm turns about the shoulder until it clears, eased over about half a second. Hands in
  the lap pass under the edge, which looks right because the edge is level with the belly.
- Which takes are used, and their names, are in `RETARGETED_CLIPS`. Walking, running and
  sitting on the floor are left out because players never leave their chairs.

The build log prints one `RETARGET` line per clip (lift, lean, how often the arms were
moved). `-Preview <dir>` also renders four frames of each clip, front and side.

## Hat (`Hat - Accessory.blend` → `assets/models/player/hat.glb`)

`build_player.py` measures a **hat band ring** on the rest-pose head: a horizontal slice 30 %
of the way down from the top of the Head-weighted vertices (`HAT_BAND_DEPTH`), written to
`player_metrics.json` as `hat_band` (centre, width, depth). `tools/blender/build_hat.py` then:

1. Keeps the felt hat (`Sphere.004`) and its band (`Sphere.002`), applies the modifiers at
   subdivision 1 and replaces the procedural materials with two flat colours (`HatFelt`,
   `HatBand`, averaged from the source's colour ramps).
2. Scales the hat so the band goes round the ring with 12 % room (`FIT`), puts the band's
   bottom on the ring, lifts it 2 cm and tips it back 8° (`LIFT`, `TILT_BACK`) so players
   looking down at their monitor still show their eyes.
3. Decimates to 6k triangles and exports `hat.glb` **in the player's model space**.

`PlayerAvatar` puts it on a `BoneAttachment3D` for the `Head` bone, undoing the bone's rest
transform, so it sits exactly as fitted and follows every animation. For your own player in
seat and TV views the hat only casts its shadow (`set_first_person`), or the brim would cover
the top of the screen. Run the player build before the hat build (the script does).

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
- `Human Eyes.blend`: its iris/sclera textures are missing from the asset folder.

## Pitfalls

- Blender 2.81's Workbench and Eevee renderers crash in background mode
  (`EXCEPTION_ACCESS_VIOLATION`). Previews and bakes use Cycles on the CPU.
- The `hires` object is hidden in the source file; the bake un-hides it in memory.
- `BakeSettings.max_ray_distance` does not exist in 2.81; only `cage_extrusion` is used.
- GitHub rejects files over 100 MB, which is why the `.blend` sources stay out of git.
