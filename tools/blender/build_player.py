# Builds the game-ready player character from the artist's source file.
#
# Source: "Player Model.blend" (kept outside the repo, see tools/build_models.ps1). It holds a
# high-poly sculpt ("hires") and a UV-mapped low-poly body ("Low") in an A-pose, about 7 units
# tall, facing +X. This script never saves the source file; it only exports.
#
# Steps: bake hires -> Low normal + AO maps, move Low to game space (1.8 m, facing -Y, feet on
# the floor), build a 21-bone skeleton from landmarks measured on the mesh, skin it with
# automatic weights, write clothing masks into vertex colours, create the animations and export
# assets/models/player/player.glb.
#
# Usage (Blender 2.81):
#   blender -b --factory-startup "<Player Model.blend>" --python build_player.py -- \
#       --out <repo>/assets/models/player [--skip-bake] [--bake-size 2048] [--preview <png prefix>]
import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

TARGET_HEIGHT = 1.8
FPS = 30

# Joint landmarks in the SOURCE file's space (Low object, +X forward, +Y = character's left,
# feet at z = -3.85). Measured from horizontal slices of the mesh (centroids of the limb
# cross-sections); see docs/ASSET_PIPELINE.md. Left side only, the right side is mirrored.
SRC_FEET_Z = -3.846
SRC_TOP_Z = 3.183
SRC_CENTER_X = 1.46
LANDMARKS = {
	"hips": (1.45, 0.0, -0.55),
	"spine": (1.38, 0.0, 0.45),
	"chest": (1.36, 0.0, 1.30),
	"neck": (1.45, 0.0, 2.15),
	"head": (1.60, 0.0, 2.45),
	"head_top": (1.60, 0.0, 3.18),
	"clavicle.L": (1.45, 0.15, 1.98),
	"shoulder.L": (1.45, 0.82, 1.80),
	"elbow.L": (1.42, 1.22, 0.55),
	"wrist.L": (1.38, 1.72, -0.38),
	"hand_tip.L": (1.40, 1.78, -1.02),
	"hip.L": (1.45, 0.48, -0.55),
	"knee.L": (1.40, 0.53, -2.00),
	"ankle.L": (1.20, 0.53, -3.35),
	"ball.L": (1.70, 0.56, -3.72),
	"toe.L": (1.98, 0.57, -3.80),
}

# name: (head landmark, tail landmark, parent)
BONES = [
	("Hips", "hips", "spine", None),
	("Spine", "spine", "chest", "Hips"),
	("Chest", "chest", "neck", "Spine"),
	("Neck", "neck", "head", "Chest"),
	("Head", "head", "head_top", "Neck"),
]
for side in ("L", "R"):
	BONES += [
		("Shoulder." + side, "clavicle." + side, "shoulder." + side, "Chest"),
		("UpperArm." + side, "shoulder." + side, "elbow." + side, "Shoulder." + side),
		("LowerArm." + side, "elbow." + side, "wrist." + side, "UpperArm." + side),
		("Hand." + side, "wrist." + side, "hand_tip." + side, "LowerArm." + side),
		("UpperLeg." + side, "hip." + side, "knee." + side, "Hips"),
		("LowerLeg." + side, "knee." + side, "ankle." + side, "UpperLeg." + side),
		("Foot." + side, "ankle." + side, "ball." + side, "LowerLeg." + side),
		("Toes." + side, "ball." + side, "toe." + side, "Foot." + side),
	]

# Vertex colour masks (smoothstep-thresholded in the game shader):
# R = shirt, G = trousers, B = shoes. Everything else is skin.
SHIRT_BONES = {"Spine", "Chest", "Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R"}
TROUSER_BONES = {"Hips", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"}
SHOE_BONES = {"Foot.L", "Foot.R", "Toes.L", "Toes.R"}


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", required=True)
	parser.add_argument("--skip-bake", action="store_true")
	parser.add_argument("--bake-size", type=int, default=2048)
	parser.add_argument("--preview", default="")
	return parser.parse_args(argv)


def landmark(name):
	if name.endswith(".R"):
		x, y, z = LANDMARKS[name[:-2] + ".L"]
		return Vector((x, -y, z))
	return Vector(LANDMARKS[name])


def source_to_game():
	"""Source space -> game space: centre, feet at z=0, face -Y, scale to TARGET_HEIGHT."""
	scale = TARGET_HEIGHT / (SRC_TOP_Z - SRC_FEET_Z)
	to_origin = Matrix.Translation((-SRC_CENTER_X, 0.0, -SRC_FEET_Z))
	turn = Matrix.Rotation(math.radians(-90.0), 4, "Z")  # +X forward -> -Y forward
	return Matrix.Scale(scale, 4) @ turn @ to_origin


def select_only(objects, active):
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = active


def clean_scene(keep):
	for obj in list(bpy.data.objects):
		if obj.name not in keep:
			bpy.data.objects.remove(obj, do_unlink=True)


def bake_maps(low, hires, out_dir, size):
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	bake_mat = bpy.data.materials.new("BakeTarget")
	bake_mat.use_nodes = True
	nodes = bake_mat.node_tree.nodes
	image_node = nodes.new("ShaderNodeTexImage")
	low.data.materials.clear()
	low.data.materials.append(bake_mat)
	for poly in low.data.polygons:
		poly.material_index = 0
	# The sculpt is usually hidden in the source file; baking needs it visible and selectable.
	for layer_collection in bpy.context.view_layer.layer_collection.children:
		layer_collection.exclude = False
		layer_collection.hide_viewport = False
	for obj in (low, hires):
		obj.hide_set(False)
		obj.hide_viewport = False
		obj.hide_render = False
		obj.hide_select = False
		for collection in obj.users_collection:
			collection.hide_viewport = False
			collection.hide_render = False
	select_only([low, hires], low)
	print("BAKE selected", [o.name for o in bpy.context.selected_objects], "active", bpy.context.view_layer.objects.active.name)
	results = {}
	for kind, samples in (("NORMAL", 4), ("AO", 32)):
		image = bpy.data.images.new("player_" + kind.lower(), size, size, alpha=False)
		if kind == "NORMAL":
			image.colorspace_settings.name = "Non-Color"
		image_node.image = image
		nodes.active = image_node
		scene.cycles.samples = samples
		scene.render.bake.use_selected_to_active = True
		# Source units: the sculpt sits within ~0.05 of the low-poly surface.
		scene.render.bake.cage_extrusion = 0.08
		scene.render.bake.margin = 8
		print("BAKING", kind, size)
		bpy.ops.object.bake(type=kind, normal_space="TANGENT")
		path = os.path.join(out_dir, "player_%s.png" % kind.lower())
		image.filepath_raw = path
		image.file_format = "PNG"
		image.save()
		results[kind] = path
		print("WROTE", path)
	return results


def build_armature(game_matrix):
	arm_data = bpy.data.armatures.new("PlayerRig")
	rig = bpy.data.objects.new("PlayerRig", arm_data)
	bpy.context.scene.collection.objects.link(rig)
	select_only([rig], rig)
	bpy.ops.object.mode_set(mode="EDIT")
	forward = Vector((0.0, -1.0, 0.0))
	for name, head, tail, parent in BONES:
		bone = arm_data.edit_bones.new(name)
		bone.head = game_matrix @ landmark(head)
		bone.tail = game_matrix @ landmark(tail)
		# Z axis toward the character's front for every bone, so rolls are predictable.
		bone.align_roll(forward if abs(bone.vector.normalized().y) < 0.9 else Vector((0, 0, 1)))
		if parent:
			bone.parent = arm_data.edit_bones[parent]
			bone.use_connect = (bone.head - bone.parent.tail).length < 1e-4
	bpy.ops.object.mode_set(mode="OBJECT")
	return rig


def skin(low, rig):
	select_only([low, rig], rig)
	bpy.ops.object.parent_set(type="ARMATURE_AUTO")
	names = {g.index: g.name for g in low.vertex_groups}
	unweighted = sum(1 for v in low.data.vertices if not any(g.weight > 0.001 for g in v.groups))
	print("SKIN groups=%d unweighted_verts=%d / %d" % (len(names), unweighted, len(low.data.vertices)))
	if unweighted > len(low.data.vertices) * 0.01:
		raise RuntimeError("automatic weights failed for %d vertices" % unweighted)


def write_masks(low):
	mesh = low.data
	names = {g.index: g.name for g in low.vertex_groups}
	per_vertex = []
	for v in mesh.vertices:
		total = sum(g.weight for g in v.groups) or 1.0
		def share(bones):
			return sum(g.weight for g in v.groups if names[g.group] in bones) / total
		per_vertex.append((share(SHIRT_BONES), share(TROUSER_BONES), share(SHOE_BONES)))
	for old in list(mesh.vertex_colors):
		mesh.vertex_colors.remove(old)
	layer = mesh.vertex_colors.new(name="Masks")
	mesh.vertex_colors.active = layer
	for loop in mesh.loops:
		r, g, b = per_vertex[loop.vertex_index]
		layer.data[loop.index].color = (r, g, b, 1.0)


def preview_material(low, maps):
	mat = bpy.data.materials.new("PlayerBody")
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	bsdf = nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (0.62, 0.45, 0.36, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.6
	if "NORMAL" in maps:
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(maps["NORMAL"])
		tex.image.colorspace_settings.name = "Non-Color"
		nmap = nodes.new("ShaderNodeNormalMap")
		mat.node_tree.links.new(tex.outputs["Color"], nmap.inputs["Color"])
		mat.node_tree.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
	low.data.materials.clear()
	low.data.materials.append(mat)


# --- Poses -----------------------------------------------------------------------------------
# A pose is {bone: world direction} in game space (-Y forward, +Z up, +X = character's left),
# plus an optional hips drop. Bones are aimed parent-first, so a direction is absolute.

def mirror(direction):
	return (-direction[0], direction[1], direction[2])


def sided(pose_left):
	pose = {}
	for name, direction in pose_left.items():
		if name.endswith(".L"):
			pose[name] = direction
			pose[name[:-2] + ".R"] = mirror(direction)
		else:
			pose[name] = direction
	return pose


SEATED = sided({
	"Spine": (0.0, -0.12, 1.0),
	"Chest": (0.0, -0.25, 1.0),
	"Neck": (0.0, -0.25, 1.0),
	"Head": (0.0, -0.45, 1.0),
	"UpperArm.L": (0.18, -0.45, -0.88),
	"LowerArm.L": (-0.25, -1.0, 0.05),
	"Hand.L": (-0.15, -1.0, -0.12),
	"UpperLeg.L": (0.08, -1.0, -0.04),
	"LowerLeg.L": (0.02, -0.18, -1.0),
	"Foot.L": (0.04, -1.0, -0.35),
	"Toes.L": (0.04, -1.0, -0.05),
})
SEATED_HIPS_DROP_GUESS = 0.30  # refined by calibrate_seat() so the feet rest on the floor
SEATED_HIPS_BACK = 0.12  # metres the pelvis moves back, so the knees end up near the origin
EYES = (1.86, 0.0, 2.74)  # source-space point between the eyes, for the first-person camera


def with_changes(base, changes):
	pose = dict(base)
	pose.update(sided(changes))
	return pose


BREATHE_IN = with_changes(SEATED, {"Chest": (0.0, -0.21, 1.0), "Head": (0.0, -0.4, 1.0)})
FLINCH = with_changes(SEATED, {
	"Spine": (0.0, 0.1, 1.0),
	"Chest": (0.0, 0.2, 1.0),
	"Neck": (0.0, 0.15, 1.0),
	"Head": (0.15, 0.3, 1.0),
	"UpperArm.L": (0.5, -0.35, -0.6),
	"LowerArm.L": (0.2, -0.6, 0.8),
	"Hand.L": (0.1, -0.3, 1.0),
})
LOOK_UP = with_changes(SEATED, {"Neck": (0.0, -0.1, 1.0), "Head": (0.0, 0.05, 1.0)})


def apply_pose(rig, pose, hips_offset):
	"""Aims each bone at its world direction, parent first, and keys nothing."""
	for pb in rig.pose.bones:
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = Quaternion()
		pb.location = Vector()
	bpy.context.view_layer.update()
	hips = rig.pose.bones["Hips"]
	hips.matrix = Matrix.Translation(hips_offset) @ hips.matrix
	bpy.context.view_layer.update()
	ordered = [b.name for b in rig.data.bones if b.parent is None]
	queue = list(ordered)
	while queue:
		name = queue.pop(0)
		pb = rig.pose.bones[name]
		if name in pose:
			current = pb.matrix.copy()
			current_dir = (current.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
			target = Vector(pose[name]).normalized()
			turn = current_dir.rotation_difference(target).to_matrix().to_4x4()
			head = current.to_translation()
			pb.matrix = Matrix.Translation(head) @ turn @ Matrix.Translation(-head) @ current
			bpy.context.view_layer.update()
		queue += [child.name for child in rig.data.bones[name].children]


def key_pose(rig, frame):
	for pb in rig.pose.bones:
		pb.keyframe_insert("rotation_quaternion", frame=frame)
		pb.keyframe_insert("location", frame=frame)


def make_action(rig, name, keys):
	"""keys: [(frame, pose, hips_offset)]. Pushes the action to its own NLA track for export."""
	action = bpy.data.actions.new(name)
	rig.animation_data_create()
	rig.animation_data.action = action
	for frame, pose, offset in keys:
		apply_pose(rig, pose, offset)
		key_pose(rig, frame)
	for fcurve in action.fcurves:
		for point in fcurve.keyframe_points:
			point.interpolation = "BEZIER"
	track = rig.animation_data.nla_tracks.new()
	track.name = name
	track.strips.new(name, int(action.frame_range[0]), action)
	track.mute = True
	rig.animation_data.action = None
	print("ACTION", name, tuple(action.frame_range))
	return action


def posed_vertices(low):
	depsgraph = bpy.context.evaluated_depsgraph_get()
	evaluated = low.evaluated_get(depsgraph)
	mesh = evaluated.to_mesh()
	points = [v.co.copy() for v in mesh.vertices]
	evaluated.to_mesh_clear()
	return points


def calibrate_seat(rig, low):
	"""Lowers the seated pelvis until the feet touch the floor (z = 0)."""
	sit = Vector((0.0, SEATED_HIPS_BACK, -SEATED_HIPS_DROP_GUESS))
	apply_pose(rig, SEATED, sit)
	lowest = min(p.z for p in posed_vertices(low))
	sit.z -= lowest
	print("SEAT calibrated hips offset", tuple(sit))
	return sit


def to_godot(v):
	"""Blender game space (-Y forward, Z up) -> Godot model space (glTF: +Z forward, Y up)."""
	return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def write_metrics(rig, low, sit, game_matrix, out_dir):
	"""Measures the seated pose so the room can size chairs and the table to the character."""
	import json
	apply_pose(rig, SEATED, sit)
	points = posed_vertices(low)
	hips = rig.pose.bones["Hips"].head
	seat_height = min(p.z for p in points if abs(p.y - hips.y) < 0.1 and abs(p.x) < 0.18)
	forearm_names = {"LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R"}
	group_index = {g.name: g.index for g in low.vertex_groups}
	forearm_ids = {group_index[n] for n in forearm_names}
	forearm_z = [points[v.index].z for v in low.data.vertices
		if any(g.group in forearm_ids and g.weight > 0.5 for g in v.groups)]
	head = rig.pose.bones["Head"]
	rest = rig.data.bones["Head"].matrix_local
	eyes = head.matrix @ rest.inverted() @ (game_matrix @ Vector(EYES))
	wrists = {side: rig.pose.bones["Hand." + side].head for side in ("L", "R")}
	metrics = {
		"note": "Seated pose measurements in Godot model space (metres, +Z = facing). "
			"Generated by tools/blender/build_player.py.",
		"height": TARGET_HEIGHT,
		"seat_height": round(seat_height, 4),
		"forearm_bottom": round(min(forearm_z), 4),
		"seated_eyes": to_godot(eyes),
		"seated_hips": to_godot(hips),
		"seated_wrist_l": to_godot(wrists["L"]),
		"seated_wrist_r": to_godot(wrists["R"]),
		"animations": ["seated_idle", "flinch", "look_up", "a_pose"],  # names after Godot import
	}
	path = os.path.join(out_dir, "player_metrics.json")
	with open(path, "w", newline="\n") as handle:
		json.dump(metrics, handle, indent="\t")
		handle.write("\n")
	print("METRICS", metrics)
	print("WROTE", path)


def make_animations(rig, sit):
	flinch_sit = sit + Vector((0.0, 0.03, 0.0))
	make_action(rig, "seated_idle_loop", [
		(1, SEATED, sit), (46, BREATHE_IN, sit), (91, SEATED, sit)])
	make_action(rig, "flinch", [
		(1, SEATED, sit), (4, FLINCH, flinch_sit), (10, FLINCH, flinch_sit), (24, SEATED, sit)])
	make_action(rig, "look_up", [(1, SEATED, sit), (12, LOOK_UP, sit)])
	make_action(rig, "a_pose", [(1, {}, Vector())])


def render_preview(prefix, rig, low, sit):
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 16
	scene.render.resolution_x = 640
	scene.render.resolution_y = 640
	world = bpy.data.worlds.new("PreviewWorld")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.15, 0.15, 0.17, 1)
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 4.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
	scene.collection.objects.link(sun)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	# A floor and a seat block make it obvious when the feet float or the hips sink.
	bpy.ops.mesh.primitive_plane_add(size=6.0)
	shots = [("apose", {}, Vector(), (2.2, -4.0, 1.4), (0, 0, 0.9)),
		("seated", SEATED, sit, (2.0, -2.6, 1.3), (0, 0, 0.6)),
		("seated_side", SEATED, sit, (3.0, 0.0, 0.8), (0, 0, 0.6)),
		("flinch", FLINCH, sit, (2.0, -2.6, 1.3), (0, 0, 0.6))]
	for label, pose, offset, cam_pos, look_at in shots:
		apply_pose(rig, pose, offset)
		cam.location = Vector(cam_pos)
		cam.rotation_euler = (Vector(look_at) - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = "%s_%s.png" % (prefix, label)
		bpy.ops.render.render(write_still=True)
		print("WROTE", scene.render.filepath)


def export(rig, low, out_dir):
	apply_pose(rig, {}, Vector())
	select_only([rig, low], rig)
	path = os.path.join(out_dir, "player.glb")
	bpy.context.scene.render.fps = FPS
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", export_selected=True, export_apply=False,
		export_colors=True, export_normals=True, export_tangents=True, export_texcoords=True,
		export_materials=False, export_skins=True, export_animations=True,
		export_nla_strips=True, export_force_sampling=True, export_frame_range=False,
		export_morph=False, export_yup=True, export_cameras=False, export_lights=False)
	print("WROTE", path)


def main():
	args = parse_args()
	os.makedirs(args.out, exist_ok=True)
	clean_scene({"Low", "hires"})
	low = bpy.data.objects["Low"]
	hires = bpy.data.objects["hires"]
	maps = {}
	if args.skip_bake:
		for kind in ("NORMAL", "AO"):
			path = os.path.join(args.out, "player_%s.png" % kind.lower())
			if os.path.exists(path):
				maps[kind] = path
	else:
		maps = bake_maps(low, hires, args.out, args.bake_size)
	bpy.data.objects.remove(hires, do_unlink=True)

	game = source_to_game()
	low.data.transform(game)
	low.matrix_world = Matrix()
	low.data.update()
	low.name = "PlayerBody"
	print("BODY dims", tuple(low.dimensions))

	rig = build_armature(game)
	skin(low, rig)
	write_masks(low)
	preview_material(low, maps)
	sit = calibrate_seat(rig, low)
	write_metrics(rig, low, sit, game, args.out)
	make_animations(rig, sit)
	if args.preview:
		render_preview(args.preview, rig, low, sit)
	export(rig, low, args.out)


main()
