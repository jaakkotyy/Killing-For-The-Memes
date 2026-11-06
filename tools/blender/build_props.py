# Builds game-ready table props (drinks) from the artist's source files.
#
# Sources (kept outside the repo, see tools/build_models.ps1), each a small studio scene with
# one prop modelled at an arbitrary scale:
#   cup.blend   saucer "Circle", cup "Circle.001", handle "Circle.002"
#   can.blend   can body "Cylinder" (a 455k-triangle sculpt)
#   beer.blend  glass "Circle", beer "neste", foam "Circle.001"
# Studio floors, lights, cameras and particle helpers are left out.
#
# For each prop: lower the subdivision levels, apply modifiers, join, decimate to the
# triangle budget, scale to real-world height, put the origin at the bottom centre, assign
# simple game materials (base colour, metallic, roughness, alpha) and export
# assets/models/props/<name>.glb. The source file is never saved.
#
# Usage (Blender 2.81), once per source file:
#   blender -b --factory-startup "<cup.blend>" --python build_props.py -- --prop cup --out <repo>/assets/models/props
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

# Game material name: (base colour RGBA, metallic, roughness)
MATERIALS = {
	"Ceramic": ((0.92, 0.9, 0.86, 1.0), 0.0, 0.35),
	"Aluminium": ((0.75, 0.75, 0.77, 1.0), 0.9, 0.35),
	"CanPaint": ((0.62, 0.08, 0.06, 1.0), 0.6, 0.4),
	"Glass": ((0.85, 0.92, 0.95, 0.14), 0.0, 0.05),
	"Beer": ((0.78, 0.36, 0.04, 0.9), 0.0, 0.1),
	"Foam": ((0.98, 0.94, 0.82, 1.0), 0.0, 0.8),
}
TRANSPARENT = {"Glass", "Beer"}

# objects: source object -> (game material per source slot, subdivision levels to use)
# height (or width, the larger horizontal extent): real-world size in metres.
# budget: max triangles after decimation.
PROPS = {
	"cup": {
		"objects": {
			"Circle": (["Ceramic"], 1),
			"Circle.001": (["Ceramic"], 0),
			"Circle.002": (["Ceramic"], 1),
		},
		# Scaled by the saucer, which sets the footprint on the table.
		"width": 0.16,
		"budget": 4000,
	},
	"can": {
		"objects": {"Cylinder": (["Aluminium"], 0)},
		"height": 0.122,
		"budget": 4000,
		"label": "CanPaint",
	},
	"beer": {
		"objects": {
			"Circle": (["Glass"], 1),
			"neste": (["Glass", "Beer"], 1),
			"Circle.001": (["Glass", "Foam"], 0),
		},
		"height": 0.16,
		"budget": 8000,
	},
}


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--prop", required=True, choices=sorted(PROPS))
	parser.add_argument("--out", required=True)
	return parser.parse_args(argv)


_made = {}


def game_material(name):
	if name in _made:
		return _made[name]
	colour, metallic, roughness = MATERIALS[name]
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = colour
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Alpha"].default_value = colour[3]
	if name in TRANSPARENT:
		mat.blend_method = "BLEND"
		# Single-sided: double-sided blended surfaces sort badly against themselves in Godot.
		mat.use_backface_culling = True
	_made[name] = mat
	return mat


def select_only(objects, active):
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = active


def triangles(obj):
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def prepare(obj, slots, levels):
	"""Applies the modifiers (at game subdivision levels) and swaps in game materials."""
	for mod in obj.modifiers:
		if mod.type == "SUBSURF":
			mod.levels = levels
			mod.render_levels = levels
		elif mod.type in ("COLLISION", "PARTICLE_SYSTEM"):
			obj.modifiers.remove(mod)
	select_only([obj], obj)
	bpy.ops.object.convert(target="MESH")
	materials = obj.data.materials
	if len(materials) == 0:
		materials.append(None)
	for i in range(len(materials)):
		materials[i] = game_material(slots[min(i, len(slots) - 1)])


def paint_label(obj, label_name):
	"""Gives the can's straight middle a painted label; rims, top and bottom stay bare metal.

	Run after decimating: the label borders are cut in as clean horizontal edge loops, so the
	paint ends in a straight line instead of following the decimated triangles."""
	obj.data.materials.append(game_material(label_name))
	label_index = len(obj.data.materials) - 1
	zs = [v.co.z for v in obj.data.vertices]
	low, high = min(zs), max(zs)
	band_low = low + (high - low) * 0.08
	band_high = low + (high - low) * 0.84
	select_only([obj], obj)
	bpy.ops.object.mode_set(mode="EDIT")
	for z in (band_low, band_high):
		bpy.ops.mesh.select_all(action="SELECT")
		bpy.ops.mesh.bisect(plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0))
	bpy.ops.object.mode_set(mode="OBJECT")
	for poly in obj.data.polygons:
		if band_low < poly.center.z < band_high and abs(poly.normal.z) < 0.5:
			poly.material_index = label_index


def main():
	args = parse_args()
	spec = PROPS[args.prop]
	os.makedirs(args.out, exist_ok=True)
	keep = set(spec["objects"])
	for obj in list(bpy.data.objects):
		if obj.name not in keep:
			bpy.data.objects.remove(obj, do_unlink=True)
	parts = []
	for name, (slots, levels) in spec["objects"].items():
		obj = bpy.data.objects[name]
		obj.hide_set(False)
		obj.hide_viewport = False
		obj.hide_render = False
		prepare(obj, slots, levels)
		parts.append(obj)

	select_only(parts, parts[0])
	bpy.ops.object.join()
	prop = bpy.context.view_layer.objects.active
	prop.name = args.prop
	prop.data.name = args.prop
	# Bake object transforms into the vertices so measurements are in world units.
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

	before = triangles(prop)
	if before > spec["budget"]:
		decimate = prop.modifiers.new("Decimate", "DECIMATE")
		decimate.ratio = spec["budget"] / before
		decimate.use_collapse_triangulate = True
		bpy.ops.object.modifier_apply(modifier=decimate.name)

	if "label" in spec:
		paint_label(prop, spec["label"])

	# Real-world size, origin at the bottom centre.
	zs = [v.co.z for v in prop.data.vertices]
	xs = [v.co.x for v in prop.data.vertices]
	ys = [v.co.y for v in prop.data.vertices]
	if "width" in spec:
		scale = spec["width"] / max(max(xs) - min(xs), max(ys) - min(ys))
	else:
		scale = spec["height"] / (max(zs) - min(zs))
	offset = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
	for v in prop.data.vertices:
		v.co = (v.co - offset) * scale

	bpy.ops.object.shade_smooth()
	prop.data.use_auto_smooth = True
	prop.data.auto_smooth_angle = math.radians(40)

	size = Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))) * scale
	print("PROP %s tris=%d (from %d) size=%.3fx%.3fx%.3f m" % (
		args.prop, triangles(prop), before, size.x, size.y, size.z))

	select_only([prop], prop)
	path = os.path.join(args.out, args.prop + ".glb")
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", export_selected=True, export_apply=True,
		export_normals=True, export_texcoords=False, export_materials=True,
		export_colors=False, export_animations=False, export_skins=False, export_morph=False,
		export_yup=True, export_cameras=False, export_lights=False)
	print("WROTE", path)


main()
