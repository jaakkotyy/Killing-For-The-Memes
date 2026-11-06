---
name: blender-pipeline
description: Turn the user's own Blender character files (D:\Killing-For-The-Memes-Assets) into game-ready Godot assets for Killing for the Memes - inspect and preview .blend files headless, bake normal/AO maps from a sculpt, rig with automatic weights, key seated/flinch poses, export .glb and verify in the 3D room. Use when asked to use, change, re-export, rig, animate or check a character, skull, hat or other model from Blender, or when the models look wrong in game.
---

# Blender characters → Godot

The user makes the models in Blender. The sources stay **outside the repo** in
`D:\Killing-For-The-Memes-Assets\` (hundreds of MB; GitHub rejects files over 100 MB).
Only exports go into `assets/models/**`. Full reference: `docs/ASSET_PIPELINE.md`.

Blender here is **2.81** at `D:\Blender\blender.exe` (or `$env:BLENDER`). Everything runs
headless (`-b --factory-startup <file> --python <script> -- <args>`). **Never save the
user's .blend files**; scripts change data in memory and only export.

## Rebuild what exists

```powershell
.\tools\build_models.ps1            # player: bake + rig + animations + export (~1 min)
.\tools\build_models.ps1 -SkipBake  # faster, reuses committed normal/AO maps
.\tools\build_models.ps1 -SkipBake -Preview "<scratchpad>\prev"   # + Cycles pose renders
```

It prints `SKIN groups=21 unweighted_verts=0 / 9974`, the seat calibration and one
`WROTE` per output (`player.glb`, `player_metrics.json`, maps). Then it re-imports in Godot.

## Verify (always, with your eyes)

1. Read the preview PNGs (`player_apose`, `_seated`, `_seated_side`, `_flinch`). Feet must
   touch the floor plane in the side view; no limbs through the body.
2. Screenshot the room (see the `run-game` skill, mode 4):
   ```bash
   "$G" --path . --resolution 1280x720 --write-movie "C:/<scratchpad>/shots/f.png" --quit-after 90 -- --room-preview=8 --room-camera=overview
   ```
   Use forward slashes in the `--write-movie` path. Check: everyone seated on chairs,
   hands on keyboards, cuffs on wrists, distinct shirt colours, name tags above heads.
   `--room-camera=seat` must show your own CRT glowing in front of you.
3. `.\tools\run_tests.ps1` and `.\tools\smoke_test.ps1 -Clients 3` (the room loads headless).

## Work on a new or changed model

1. **Inspect** (read-only): `scripts/inspect_blend.py` lists objects, triangle counts after
   modifiers, armatures, actions, missing images and materials.
   `scripts/preview_blend.py -- <out_prefix> <obj1,obj2>` renders clay previews.
2. **Measure joints** with `scripts/slice_mesh.py -- <object> 0.1 y`: limb clusters per
   height give knee/elbow/wrist centroids. Put them in `LANDMARKS` (source coordinates).
3. **Budget**: game meshes under ~20k triangles per character. Bake detail from the sculpt
   into normal/AO maps instead of shipping it.
4. Extend `tools/blender/build_player.py` (or add `build_<thing>.py` beside it and call it
   from `tools/build_models.ps1`). Poses are world directions per bone; see the
   `SEATED`/`FLINCH` dictionaries and `make_action()`.
5. Godot strips a `_loop` suffix from animation names and loops them. Update the names in
   `src/world/player/player_avatar.gd` when adding animations.
6. **Static props** (no rig): add an entry to `PROPS` in `tools/blender/build_props.py`
   (objects to keep, game material per slot, subdivision level, real height or width,
   triangle budget) and the name to the loop in `tools/build_models.ps1`; then
   `.\tools\build_models.ps1 -PropsOnly`. Check its `PROP <name> tris=... size=...` line:
   sizes must be real-world metres. Studio floors/lights/particle helpers are left out.
   Close-up check in Godot: a throwaway scene with a Camera3D aimed at `seat.drink`
   (delete it afterwards). Glass reads greenish because the CRTs light the room green.
7. Credits: the user's own models go in `CREDITS.md` as original work. Ask who made any
   model before crediting it.

## Pitfalls (all hit in practice)

- **Workbench/Eevee crash** in background mode on 2.81 (`EXCEPTION_ACCESS_VIOLATION`).
  Use Cycles CPU for previews and bakes (16–32 samples is enough).
- **Hidden objects can't bake** ("No valid selected objects"): the user's sculpts are often
  hidden; un-hide (`hide_set`, `hide_viewport`, `hide_render`, collection exclude) first.
- **2.81 API gaps**: no `BakeSettings.max_ray_distance`; glTF exporter has
  `export_nla_strips` but no `export_def_bones`. Check an operator's properties with
  `bpy.ops.export_scene.gltf.get_rna_type().properties` before using a newer option.
- **Multiple animations**: each action must be on its own NLA track (muted) with
  `export_nla_strips=True`, or only the active action exports.
- **Axes**: Blender −Y forward → glTF/Godot +Z forward. The room places models with +Z
  toward the table. `player_metrics.json` is already in Godot model space.
- **Missing textures**: the source files reference images by absolute paths on the
  artist's old desktop (`normal4K.png`, iris/sclera PNGs). Bake new maps instead of
  relinking unless the user provides the files.
- **Big files**: loading `Player Model.blend` (370 MB) takes ~5 s; the bake ~40 s.
  Run longer jobs with `run_in_background` and redirect output to a log.
