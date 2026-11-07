# Exports the models in one .blend as a single .glb under a size limit, for uploading to
# Meshy (or anything else that wants FBX/OBJ/glTF/GLB, not .blend). Blender 2.81, headless:
#
#   blender -b --factory-startup <file.blend> --python export_for_meshy.py -- <out.glb> [max_mb]
#
# Never saves the .blend: every change (decimation, unhiding) happens in memory only.
#
# What gets exported: the mesh objects that are visible in the file (hidden helpers and
# backups stay out). If nothing is visible, every mesh. Modifiers are applied, materials
# and textures embedded, no animation or rig (Meshy wants a static mesh). If the file is
# too big, a Decimate modifier is added to every mesh and the ratio lowered until it fits;
# textures are re-encoded as JPEG first if the exporter supports it.
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0]
MAX_MB = float(argv[1]) if len(argv) > 1 else 95.0
MAX_BYTES = int(MAX_MB * 1024 * 1024)
GLTF_PROPS = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()


def visible(obj):
	try:
		return obj.visible_get()
	except Exception:
		return not obj.hide_viewport and not obj.hide_render


def eval_tris(objects):
	depsgraph = bpy.context.evaluated_depsgraph_get()
	total = 0
	for obj in objects:
		ev = obj.evaluated_get(depsgraph)
		mesh = ev.to_mesh()
		total += sum(len(p.vertices) - 2 for p in mesh.polygons)
		ev.to_mesh_clear()
	return total


def export(objects, jpeg):
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	options = dict(
		filepath=OUT, export_format="GLB", export_selected=True, export_apply=True,
		export_normals=True, export_texcoords=True, export_materials=True, export_colors=True,
		export_animations=False, export_skins=False, export_morph=False, export_yup=True,
		export_cameras=False, export_lights=False)
	if jpeg and "export_image_format" in GLTF_PROPS:
		options["export_image_format"] = "JPEG"
	bpy.ops.export_scene.gltf(**options)
	return os.path.getsize(OUT)


def main():
	meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
	chosen = [o for o in meshes if visible(o)] or meshes
	if not chosen:
		print("MESHY_SKIP no meshes in", bpy.data.filepath)
		return
	# Selection needs the objects to be selectable and in the view layer.
	for obj in chosen:
		obj.hide_set(False)
		obj.hide_viewport = False
		obj.hide_select = False
	full = eval_tris(chosen)
	print("MESHY_OBJECTS", len(chosen), [o.name for o in chosen][:12], "tris", full)

	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	jpeg = False
	size = export(chosen, jpeg)
	print("MESHY_TRY ratio 1.0 size %.1f MB" % (size / 1048576))
	if size > MAX_BYTES and "export_image_format" in GLTF_PROPS:
		jpeg = True
		size = export(chosen, jpeg)
		print("MESHY_TRY jpeg textures size %.1f MB" % (size / 1048576))

	ratio = 1.0
	decimators = []
	attempt = 0
	while size > MAX_BYTES and attempt < 6:
		attempt += 1
		if not decimators:
			for obj in chosen:
				mod = obj.modifiers.new("MeshyDecimate", "DECIMATE")
				mod.decimate_type = "COLLAPSE"
				decimators.append(mod)
		# Mesh data scales roughly with triangles; aim a little under the limit.
		ratio = max(0.002, ratio * (MAX_BYTES / size) * 0.85)
		for mod in decimators:
			mod.ratio = ratio
		size = export(chosen, jpeg)
		print("MESHY_TRY ratio %.4f size %.1f MB" % (ratio, size / 1048576))

	tris = eval_tris(chosen)
	status = "MESHY_OK" if size <= MAX_BYTES else "MESHY_TOO_BIG"
	print("%s %s %.1f MB tris %d of %d (ratio %.4f, jpeg %s)" % (status, OUT, size / 1048576, tris, full, ratio, jpeg))


main()
