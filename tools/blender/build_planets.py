# Builds the two planets of the space backdrop from the artist's planets.blend.
#
# Source (kept outside the repo, see tools/build_models.ps1): "Sphere" (the big red planet,
# material "planeetta") and "Sphere.001" (the small pale moon, "planeetta 2"). Their colour
# is procedural: two noise textures through colour ramps, mixed ("Mix.001" feeds the base
# colour). Their glowing rim (a fresnel emission on the lit side) is rebuilt in Godot by
# src/world/space/planet.gdshader, with the rim colours listed in RIM below.
#
# For each planet: apply the subdivision, bake the base colour to a texture by routing it
# through an emission shader (exact for procedural colour, unlike a diffuse bake), centre
# the mesh, scale it to a 1 m radius (the game sizes it) and export
# assets/models/planets/<name>.glb plus <name>_albedo.png. The source file is never saved.
#
# Usage (Blender 2.81):
#   blender -b --factory-startup "<planets.blend>" --python build_planets.py -- --out <repo>/assets/models/planets
import argparse
import json
import os
import sys

import bpy

# game name: (source object, source material, subdivision levels, texture width)
PLANETS = {
	"planet_red": ("Sphere", "planeetta", 2, 2048),
	"planet_moon": ("Sphere.001", "planeetta 2", 2, 1024),
}
# The emission colours of the rims in the source materials (node "Emission").
RIM = {
	"planet_red": (0.246, 0.029, 0.03),
	"planet_moon": (0.901, 0.828, 0.85),
}


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", required=True)
	return parser.parse_args(argv)


def select_only(obj):
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj


def bake_albedo(obj, material_name, width, path):
	"""Bakes the material's procedural base colour (the "Mix.001" node) into a PNG."""
	mat = bpy.data.materials[material_name]
	tree = mat.node_tree
	nodes, links = tree.nodes, tree.links
	output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
	colour = nodes["Mix.001"].outputs["Color"]
	emit = nodes.new("ShaderNodeEmission")
	emit.inputs["Strength"].default_value = 1.0
	links.new(colour, emit.inputs["Color"])
	links.new(emit.outputs["Emission"], output.inputs["Surface"])
	image = bpy.data.images.new(obj.name + "_bake", width=width, height=width // 2)
	target = nodes.new("ShaderNodeTexImage")
	target.image = image
	nodes.active = target
	# Only this planet's material: the other slot ("Material.001") has no faces.
	obj.active_material_index = 0
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 4
	scene.cycles.bake_type = "EMIT"
	select_only(obj)
	bpy.ops.object.bake(type="EMIT", margin=8)
	image.filepath_raw = path
	image.file_format = "PNG"
	image.save()
	print("WROTE", path)


def main():
	args = parse_args()
	os.makedirs(args.out, exist_ok=True)
	sizes = {}
	for name, (source, material, levels, width) in PLANETS.items():
		obj = bpy.data.objects[source]
		for mod in obj.modifiers:
			if mod.type == "SUBSURF":
				mod.levels = levels
				mod.render_levels = levels
		select_only(obj)
		bpy.ops.object.convert(target="MESH")
		bpy.ops.object.shade_smooth()
		bake_albedo(obj, material, width, os.path.join(args.out, name + "_albedo.png"))
		# Centre it and make the radius 1 m: the game places and sizes the planets.
		radius = max(obj.dimensions) / 2.0
		sizes[name] = round(radius, 3)
		obj.location = (0.0, 0.0, 0.0)
		obj.rotation_euler = (0.0, 0.0, 0.0)
		obj.scale = (1.0 / radius * obj.scale[0], 1.0 / radius * obj.scale[1], 1.0 / radius * obj.scale[2])
		bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
		# A plain material; Godot swaps in planet.gdshader with the baked texture.
		obj.data.materials.clear()
		obj.data.materials.append(bpy.data.materials.new(name))
		select_only(obj)
		path = os.path.join(args.out, name + ".glb")
		bpy.ops.export_scene.gltf(
			filepath=path, export_format="GLB", export_selected=True, export_apply=True,
			export_normals=True, export_texcoords=True, export_materials=True,
			export_colors=False, export_animations=False, export_skins=False, export_morph=False,
			export_yup=True, export_cameras=False, export_lights=False)
		tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
		print("PLANET %s from %s: %d triangles, source radius %.2f" % (name, source, tris, radius))
		print("WROTE", path)
	info = {"source_radius": sizes, "rim": {k: list(v) for k, v in RIM.items()}}
	info_path = os.path.join(args.out, "planets.json")
	with open(info_path, "w") as f:
		json.dump(info, f, indent=2)
	print("WROTE", info_path)


main()
