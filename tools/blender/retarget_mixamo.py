# Copies animations from a Mixamo-style rig (for example the one Meshy builds) onto our
# 21-bone player rig. Used by build_player.py; Blender 2.81.
#
# Both rigs are made from the same A-posed body, so a bone's motion transfers as a WORLD
# rotation relative to its rest pose: target_world = (source_world * source_rest^-1) *
# target_rest. That keeps twist (head turns, a rolled wrist) that pure aiming would lose,
# and works although the two rigs place and roll their bones differently.
#
# The hips also move: the source's hip motion, scaled to our body height, is added to our
# seated hip position, and the whole clip is then lifted or lowered so the backside rests
# at our chair's seat height in its first frame. Chairs come from player_metrics.json, so
# every clip sits on the same chair as the keyboard pose.
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

# Our bone -> the source bone whose world rotation it follows. Our spine has fewer bones:
# Spine follows the source's middle spine bone and Chest its upper one, which together
# carry the whole bend.
BONE_MAP = {
	"Hips": "mixamorig:Hips",
	"Spine": "mixamorig:Spine1",
	"Chest": "mixamorig:Spine2",
	"Neck": "mixamorig:Neck",
	"Head": "mixamorig:Head",
}
for _ours, _theirs in (("L", "Left"), ("R", "Right")):
	BONE_MAP.update({
		"Shoulder." + _ours: "mixamorig:%sShoulder" % _theirs,
		"UpperArm." + _ours: "mixamorig:%sArm" % _theirs,
		"LowerArm." + _ours: "mixamorig:%sForeArm" % _theirs,
		"Hand." + _ours: "mixamorig:%sHand" % _theirs,
		"UpperLeg." + _ours: "mixamorig:%sUpLeg" % _theirs,
		"LowerLeg." + _ours: "mixamorig:%sLeg" % _theirs,
		"Foot." + _ours: "mixamorig:%sFoot" % _theirs,
		"Toes." + _ours: "mixamorig:%sToeBase" % _theirs,
	})


def import_source(path):
	"""Imports the FBX and returns its armature. The source mesh is deleted (we keep our own
	body), which also makes evaluating frames much faster."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=path)
	added = [o for o in bpy.data.objects if o not in before]
	source = next(o for o in added if o.type == "ARMATURE")
	for obj in added:
		if obj is not source:
			bpy.data.objects.remove(obj, do_unlink=True)
	missing = [b for b in BONE_MAP.values() if b not in source.data.bones]
	if missing:
		raise RuntimeError("source rig is missing bones: %s" % missing)
	print("RETARGET source", source.name, "bones", len(source.data.bones), "actions", len(bpy.data.actions))
	return source


def find_action(name_part):
	for action in bpy.data.actions:
		if name_part in action.name:
			return action
	raise RuntimeError("no action containing '%s'; have %s" % (name_part, [a.name for a in bpy.data.actions]))


def _children_first_order(rig):
	order = []
	queue = [b for b in rig.data.bones if b.parent is None]
	while queue:
		bone = queue.pop(0)
		order.append(bone.name)
		queue += list(bone.children)
	return order


def sample_source(source, action, height_scale):
	"""Per frame: {our bone: world rotation delta}, plus the hip offset from frame one."""
	scene = bpy.context.scene
	source.animation_data.action = action
	start, end = (int(round(v)) for v in action.frame_range)
	world = source.matrix_world
	rest = {ours: (world @ source.data.bones[theirs].matrix_local).to_quaternion()
		for ours, theirs in BONE_MAP.items()}
	frames = []
	first_hips = None
	for frame in range(start, end + 1):
		scene.frame_set(frame)
		deltas = {}
		for ours, theirs in BONE_MAP.items():
			posed = (world @ source.pose.bones[theirs].matrix).to_quaternion()
			deltas[ours] = posed @ rest[ours].inverted()
		hips = world @ source.pose.bones["mixamorig:Hips"].head
		if first_hips is None:
			first_hips = hips.copy()
		frames.append((deltas, (hips - first_hips) * height_scale))
	return frames


ARM_CHAIN = ("UpperArm", "LowerArm", "Hand")


def solve_frame(rig, order, deltas, hips_head, arm_lift=None):
	"""Local pose (rotation, location) per bone that gives each bone its target world rotation.
	arm_lift: {"L"/"R": radians} raises that whole arm about the shoulder (see retarget)."""
	world_rot = {}
	result = {}
	lifts = {}
	for name in order:
		bone = rig.data.bones[name]
		rest_rot = bone.matrix_local.to_quaternion()
		target = deltas[name] @ rest_rot if name in deltas else None
		part, _, side = name.partition(".")
		if target is not None and arm_lift and part in ARM_CHAIN and abs(arm_lift.get(side, 0.0)) > 1e-4:
			if part == "UpperArm":
				# Turn the upper arm's direction toward straight up; children turn with it, so
				# the arm keeps its shape and the hand rises.
				along = target @ Vector((0.0, 1.0, 0.0))
				axis = along.cross(Vector((0.0, 0.0, 1.0)))
				if axis.length < 1e-3:
					axis = Vector((-1.0, 0.0, 0.0))
				lifts[side] = Quaternion(axis.normalized(), arm_lift[side])
			target = lifts[side] @ target
		if bone.parent is None:
			target = target or rest_rot
			matrix = bone.matrix_local.inverted() @ Matrix.Translation(hips_head) @ target.to_matrix().to_4x4()
			result[name] = (matrix.to_quaternion(), matrix.to_translation())
		else:
			parent = bone.parent
			relative = (parent.matrix_local.inverted() @ bone.matrix_local).to_quaternion()
			parent_world = world_rot[parent.name]
			if target is None:
				target = parent_world @ relative
			local = (parent_world @ relative).inverted() @ target
			result[name] = (local, Vector())
		world_rot[name] = target
	return result


def write_action(rig, name, poses):
	"""poses: [{bone: (quaternion, location)}], one per frame from frame 1. Writes the
	F-curves directly (much faster than keyframe_insert) and puts the action on its own muted
	NLA track, like build_player.make_action, so the glTF exporter picks it up."""
	action = bpy.data.actions.new(name)
	rig.animation_data_create()
	for bone in rig.pose.bones:
		bone.rotation_mode = "QUATERNION"
	previous = {}
	for bone_name in poses[0]:
		rot_curves = [action.fcurves.new('pose.bones["%s"].rotation_quaternion' % bone_name, index=i, action_group=bone_name)
			for i in range(4)]
		loc_curves = [action.fcurves.new('pose.bones["%s"].location' % bone_name, index=i, action_group=bone_name)
			for i in range(3)]
		rot_points = [[] for _ in range(4)]
		loc_points = [[] for _ in range(3)]
		for index, pose in enumerate(poses):
			quat, loc = pose[bone_name]
			# Keep neighbouring quaternions in the same hemisphere so interpolation never spins.
			last = previous.get(bone_name)
			if last is not None and last.dot(quat) < 0.0:
				quat = -quat
			previous[bone_name] = quat
			frame = float(index + 1)
			for i in range(4):
				rot_points[i] += [frame, quat[i]]
			for i in range(3):
				loc_points[i] += [frame, loc[i]]
		for curves, points in ((rot_curves, rot_points), (loc_curves, loc_points)):
			for curve, data in zip(curves, points):
				curve.keyframe_points.add(len(data) // 2)
				curve.keyframe_points.foreach_set("co", data)
				for point in curve.keyframe_points:
					point.interpolation = "LINEAR"
				curve.update()
	track = rig.animation_data.nla_tracks.new()
	track.name = name
	track.strips.new(name, 1, action)
	track.mute = True
	print("ACTION", name, tuple(action.frame_range), "(retargeted)")
	return action


def apply_frame(rig, pose):
	for name, (quat, loc) in pose.items():
		pb = rig.pose.bones[name]
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = quat
		pb.location = loc
	bpy.context.view_layer.update()


def _scaled(deltas, lean):
	"""The deltas with the torso's motion scaled toward the rest pose (upright) by `lean`."""
	if lean >= 1.0:
		return deltas
	result = dict(deltas)
	for name in LEAN_BONES:
		result[name] = Quaternion().slerp(deltas[name], lean)
	return result


# The bones whose rotation is scaled down when a clip leans into the table. The arms, legs
# and head keep their own world rotations, so gestures and head turns stay as they were.
LEAN_BONES = ("Hips", "Spine", "Chest")
LEAN_STEPS = (1.0, 0.85, 0.7, 0.55, 0.4, 0.25)
# Arm turns (degrees about the shoulder; positive raises the arm, negative lowers it back
# toward the body), tried in order until a hand clears the table: the smallest change wins.
ARM_STEPS = (0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0, 24.0, -24.0, 32.0, -32.0, 40.0, -40.0)
# Check every n-th frame for table collisions (each check evaluates the skinned mesh).
CHECK_EVERY = 6
ARM_CHECK_EVERY = 3
# Frames (30 fps) an arm lift is held around a collision and eased in/out.
ARM_HOLD_FRAMES = 10
ARM_EASE_FRAMES = 9


def _smooth(samples, count, every, loop):
	"""Per-frame values from values sampled every `every` frames: interpolated, held around
	each peak (so an arm doesn't bob in and out) and eased with a moving average. Loops wrap
	around, so the clip's seam stays seamless."""
	values = []
	for frame in range(count):
		i = frame // every
		t = (frame % every) / every
		a = samples[min(i, len(samples) - 1)]
		b = samples[min(i + 1, len(samples) - 1)]
		values.append(a + (b - a) * t)

	def at(seq, i):
		return seq[i % count] if loop else seq[min(max(i, 0), count - 1)]

	held = [max(at(values, i + k) for k in range(-ARM_HOLD_FRAMES, ARM_HOLD_FRAMES + 1)) for i in range(count)]
	width = 2 * ARM_EASE_FRAMES + 1
	return [sum(at(held, i + k) for k in range(-ARM_EASE_FRAMES, ARM_EASE_FRAMES + 1)) / width for i in range(count)]


def retarget(rig, source, action, name, seated_hips_head, height_scale, seat_contact, seat_height,
		body_penetration=None, arm_penetration=None, tolerance=0.015):
	"""Retargets one source action onto our rig as `name`.

	seated_hips_head: where our hips sit in the keyboard pose (world).
	seat_contact(rig): measures where the posed body touches the seat; seat_height is our
	chair's height. The clip is moved vertically so they match in frame one.

	The source clips were made for a chair without a table, so two checks keep them out of
	ours (functions of the posed rig returning how deep, in metres, it is in the table):
	body_penetration(rig) (head and torso): the torso's motion is scaled down (LEAN_STEPS)
	until no checked frame goes deeper than `tolerance`.
	arm_penetration(rig, side): where a hand would sink into the table top, that arm is
	raised about the shoulder (ARM_STEPS), held and eased over time."""
	order = _children_first_order(rig)
	frames = sample_source(source, action, height_scale)
	count = len(frames)
	loop = name.endswith("_loop")

	def solve_one(index, lean, lift, arm_lift=None):
		deltas, offset = frames[index]
		return solve_frame(rig, order, _scaled(deltas, lean),
			seated_hips_head + offset + Vector((0.0, 0.0, lift)), arm_lift)

	lean = 1.0
	lift = 0.0
	depth = 0.0
	for lean in LEAN_STEPS:
		apply_frame(rig, solve_one(0, lean, 0.0))
		lift = seat_height - seat_contact(rig)
		if body_penetration is None:
			break
		depth = 0.0
		for index in range(0, count, CHECK_EVERY):
			apply_frame(rig, solve_one(index, lean, lift))
			depth = max(depth, body_penetration(rig))
		print("RETARGET %s lean %.2f: torso deepest in the table %.3f m" % (name, lean, depth))
		if depth <= tolerance:
			break

	lifts = {"L": [0.0] * count, "R": [0.0] * count}
	if arm_penetration is not None:
		for side in ("L", "R"):
			samples = []
			for index in range(0, count, ARM_CHECK_EVERY):
				best = (float("inf"), 0.0)
				for degrees in ARM_STEPS:
					apply_frame(rig, solve_one(index, lean, lift, {side: math.radians(degrees)}))
					depth_here = arm_penetration(rig, side)
					if depth_here < best[0]:
						best = (depth_here, degrees)
					if depth_here <= tolerance:
						best = (depth_here, degrees)
						break
				samples.append(math.radians(best[1]))
			# Raising and lowering are smoothed apart, so a sign flip eases through zero.
			ups = _smooth([max(0.0, v) for v in samples], count, ARM_CHECK_EVERY, loop)
			downs = _smooth([max(0.0, -v) for v in samples], count, ARM_CHECK_EVERY, loop)
			lifts[side] = [u - d for u, d in zip(ups, downs)]

	poses = [solve_one(index, lean, lift, {"L": lifts["L"][index], "R": lifts["R"][index]}) for index in range(count)]
	arm_depth = 0.0
	if arm_penetration is not None:
		for pose in poses[::CHECK_EVERY]:
			apply_frame(rig, pose)
			arm_depth = max(arm_depth, arm_penetration(rig, "L"), arm_penetration(rig, "R"))
	lifted = sum(1 for i in range(count) if max(abs(lifts["L"][i]), abs(lifts["R"][i])) > math.radians(1.0))
	print("RETARGET %s from %s: %d frames, lifted %.3f m, lean %.2f (torso depth %.3f m), "
		"arms moved %d%% of the time, up to %.0f deg (hand depth %.3f m)" % (
		name, action.name, count, lift, lean, depth, round(100.0 * lifted / count),
		math.degrees(max(abs(v) for v in lifts["L"] + lifts["R"])), arm_depth))
	return write_action(rig, name, poses), poses


def remove_source(source):
	actions = {a for a in bpy.data.actions if "|" in a.name}  # FBX takes are named "Rig|Take|Layer"
	bpy.data.objects.remove(source, do_unlink=True)
	for action in actions:
		bpy.data.actions.remove(action)
