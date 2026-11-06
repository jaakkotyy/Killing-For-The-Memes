# Builds the game-ready hat from the artist's source file, fitted to the player's head.
#
# Source: "Hat - Accessory.blend" (kept outside the repo, see tools/build_models.ps1): a felt
# hat "Sphere.004" (crown + brim) and its band "Sphere.002", with procedural Cycles materials.
#
# The hat is fitted to the "hat_band" ring that build_player.py measures on the player's head
# (player_metrics.json): scaled so the band goes round the head with a little room, its bottom
# at the ring's height. It is exported in the PLAYER'S model space (rest pose), so Godot only
# has to attach it to the Head bone (see PlayerAvatar). Run build_player.py first.
#
# Usage (Blender 2.81):
#   blender -b --factory-startup "<Hat - Accessory.blend>" --python build_hat.py -- \
#       --metrics <repo>/assets/models/player/player_metrics.json --out <repo>/assets/models/player
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HAT = "Sphere.004"
BAND = "Sphere.002"
# The band's inner size over the head's size at that height (felt, hair, a loose fit).
FIT = 1.12
# Raise the hat this far above the measured ring (metres) and tip it back (degrees), so the
# brim clears the eyes of a player looking down at their monitor.
LIFT = 0.02
TILT_BACK = 8.0
SUBDIVISION = 1
BUDGET = 6000

# The source's colour ramps averaged to one colour each (linear RGB); the bump detail is too
# fine to read at game distance.
MATERIALS = {
	"HatFelt": ((0.0, 0.1, 0.19, 1.0), 1.0),
	"HatBand": ((0.42, 0.01, 0.005, 1.0), 0.75),
}


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--metrics", required=True)
	parser.add_argument("--out", required=True)
	return parser.parse_args(argv)


def material(name):
	colour, roughness = MATERIALS[name]
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = colour
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Specular"].default_value = 0.2
	return mat


def select_only(objects, active):
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = active


def prepare(obj, mat):
	for mod in list(obj.modifiers):
		if mod.type == "SUBSURF":
			mod.levels = SUBDIVISION
			mod.render_levels = SUBDIVISION
		elif mod.type in ("COLLISION", "PARTICLE_SYSTEM"):
			obj.modifiers.remove(mod)
	obj.hide_set(False)
	obj.hide_viewport = False
	select_only([obj], obj)
	bpy.ops.object.convert(target="MESH")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	obj.data.materials.clear()
	obj.data.materials.append(mat)


def extents(obj):
	xs = [v.co.x for v in obj.data.vertices]
	ys = [v.co.y for v in obj.data.vertices]
	zs = [v.co.z for v in obj.data.vertices]
	return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def main():
	args = parse_args()
	with open(args.metrics) as handle:
		ring = json.load(handle)["hat_band"]
	gx, gy, gz = ring["center"]
	# Godot model space -> Blender game space (-Y forward, Z up).
	centre = Vector((gx, -gz, gy + LIFT))

	for obj in list(bpy.data.objects):
		if obj.name not in (HAT, BAND):
			bpy.data.objects.remove(obj, do_unlink=True)
	hat = bpy.data.objects[HAT]
	band = bpy.data.objects[BAND]
	prepare(hat, material("HatFelt"))
	prepare(band, material("HatBand"))

	# Fit by the band: its size sets the head opening, its bottom sits on the ring.
	low, high = extents(band)
	band_size = high - low
	scale = FIT * max(ring["width"] / band_size.x, ring["depth"] / band_size.y)
	anchor = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))

	select_only([hat, band], hat)
	bpy.ops.object.join()
	joined = bpy.context.view_layer.objects.active
	joined.name = "Hat"
	joined.data.name = "Hat"
	# Blender game space faces -Y, so a negative turn about X lifts the front of the brim.
	tilt = Matrix.Rotation(math.radians(-TILT_BACK), 3, "X")
	for v in joined.data.vertices:
		v.co = tilt @ ((v.co - anchor) * scale) + centre

	before = sum(len(p.vertices) - 2 for p in joined.data.polygons)
	if before > BUDGET:
		decimate = joined.modifiers.new("Decimate", "DECIMATE")
		decimate.ratio = BUDGET / before
		decimate.use_collapse_triangulate = True
		bpy.ops.object.modifier_apply(modifier=decimate.name)
	bpy.ops.object.shade_smooth()
	joined.data.use_auto_smooth = True
	joined.data.auto_smooth_angle = math.radians(50)

	low, high = extents(joined)
	tris = sum(len(p.vertices) - 2 for p in joined.data.polygons)
	print("HAT tris=%d (from %d) scale=%.4f brim=%.3fx%.3f m top=%.3f m" % (
		tris, before, scale, high.x - low.x, high.y - low.y, high.z))

	select_only([joined], joined)
	path = os.path.join(args.out, "hat.glb")
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", export_selected=True, export_apply=True,
		export_normals=True, export_texcoords=False, export_materials=True,
		export_colors=False, export_animations=False, export_skins=False, export_morph=False,
		export_yup=True, export_cameras=False, export_lights=False)
	print("WROTE", path)


main()
