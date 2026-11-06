class_name PlayerAvatar
extends Node3D
## One player's body at the table: the artist's character (assets/models/player, built by
## tools/blender/build_player.py) with per-seat clothes and skin, seated animations, wrist
## cuffs and a floating name tag.
##
## The origin is on the floor under the knees; the body faces +Z (toward the table).

const MODEL: PackedScene = preload("res://assets/models/player/player.glb")
const BODY_SHADER: Shader = preload("res://src/world/player/player_body.gdshader")
const NORMAL_MAP: Texture2D = preload("res://assets/models/player/player_normal.png")
const AO_MAP: Texture2D = preload("res://assets/models/player/player_ao.png")
const METRICS_PATH: String = "res://assets/models/player/player_metrics.json"
## The artist's hat, already fitted to the head in the body's rest pose (build_hat.py).
const HAT_MODEL: PackedScene = preload("res://assets/models/player/hat.glb")
const HAT_BONE: String = "Head"
## Dead players slump forward over the keyboard (radians, pivoting at the hips).
const DEATH_SLUMP: float = 0.5
const DEATH_SECONDS: float = 0.9

## Godot's importer strips the "_loop" suffix of the Blender action and makes it loop.
const ANIM_IDLE: StringName = &"seated_idle"
const ANIM_FLINCH: StringName = &"flinch"
const ANIM_LOOK_UP: StringName = &"look_up"

## Muted, slightly sickly shirt colours so everyone is easy to tell apart under dim light.
const SHIRT_COLORS: Array[Color] = [
	Color(0.72, 0.58, 0.22), Color(0.20, 0.50, 0.52), Color(0.55, 0.17, 0.18),
	Color(0.42, 0.48, 0.22), Color(0.30, 0.38, 0.62), Color(0.78, 0.40, 0.16),
	Color(0.45, 0.28, 0.55), Color(0.78, 0.76, 0.68),
]
const SKIN_TONES: Array[Color] = [
	Color(0.86, 0.66, 0.53), Color(0.55, 0.37, 0.26), Color(0.75, 0.55, 0.41),
	Color(0.38, 0.25, 0.18), Color(0.92, 0.74, 0.62), Color(0.65, 0.46, 0.33),
]
const TROUSER_COLORS: Array[Color] = [
	Color(0.16, 0.15, 0.14), Color(0.22, 0.20, 0.16), Color(0.14, 0.16, 0.20),
]

static var _metrics: Dictionary = {}

var display_name: String = ""
var look_index: int = 0

var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _body: MeshInstance3D
var _material: ShaderMaterial
var _label: Label3D
var _wrists: Dictionary = {}  # "L"/"R" -> BoneAttachment3D
var _hat: Node3D
var _dead: bool = false


## Seated measurements exported with the model (seat height, eye position, wrists...).
static func metrics() -> Dictionary:
	if _metrics.is_empty():
		var file := FileAccess.open(METRICS_PATH, FileAccess.READ)
		var json := JSON.new()
		if file != null and json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_metrics = json.data
		else:
			push_error("Missing or broken %s; run tools/build_models.ps1" % METRICS_PATH)
			_metrics = {"seat_height": 0.4, "forearm_bottom": 0.72, "seated_eyes": [0, 1.28, 0.05]}
	return _metrics


static func metric_vector(key: String) -> Vector3:
	var value: Variant = metrics().get(key, [0, 0, 0])
	if value is Array and (value as Array).size() == 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func color_for(index: int) -> Color:
	return SHIRT_COLORS[posmod(index, SHIRT_COLORS.size())]


func setup(p_name: String, p_look_index: int) -> void:
	display_name = p_name
	look_index = p_look_index
	if is_node_ready():
		_apply_look()


func _ready() -> void:
	_model = MODEL.instantiate()
	add_child(_model)
	_anim = _model.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_body = _model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D

	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("normal_map", NORMAL_MAP)
	_material.set_shader_parameter("ao_map", AO_MAP)
	_body.material_override = _material

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.outline_size = 10
	_label.position = metric_vector("seated_eyes") + Vector3(0, 0.38, -0.05)
	add_child(_label)

	_add_cuffs()
	_add_hat()
	_apply_look()
	if _anim != null:
		_anim.playback_default_blend_time = 0.25
		_anim.play(ANIM_IDLE)
		# Don't let the whole table breathe in sync.
		_anim.seek(randf() * _anim.current_animation_length, true)


## Short recoil, e.g. when shot at. Returns to the idle loop afterwards.
func flinch() -> void:
	if not _dead:
		_play_once(ANIM_FLINCH)


## Raises the head toward the wall TV (spotlight phase).
func look_up() -> void:
	if not _dead:
		_play_once(ANIM_LOOK_UP)


func idle() -> void:
	if _anim != null and not _dead:
		_anim.play(ANIM_IDLE)


## Freezes the body at `time` seconds into `animation` (for staged shots and tests).
func hold_pose(animation: StringName, time: float) -> void:
	if _anim == null or not _anim.has_animation(animation):
		return
	_anim.play(animation, 0.0)
	_anim.seek(time, true)
	_anim.pause()


## The cartoon death: a last flinch, a puff of smoke, and the body slumps over the
## keyboard, washed out. [param animated] false jumps straight to the end (e.g. when a
## client joins the room after the player already died).
func die(animated: bool = true) -> void:
	if _dead:
		return
	_dead = true
	set_spectator(true)
	if not animated:
		_freeze_dead()
		_model.transform = _slump_transform(1.0)
		return
	_play_once(ANIM_FLINCH)
	_puff()
	var tween := create_tween()
	tween.tween_interval(0.25)
	tween.tween_callback(_freeze_dead)
	tween.tween_method(func(t: float) -> void: _model.transform = _slump_transform(t),
		0.0, 1.0, DEATH_SECONDS).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func is_dead() -> bool:
	return _dead


## Spectators (eliminated players) are drawn washed out.
func set_spectator(enabled: bool) -> void:
	_material.set_shader_parameter("desaturate", 0.85 if enabled else 0.0)


## Shows or hides the hat (it follows the head through every animation).
func set_hat_visible(on: bool) -> void:
	if _hat != null:
		_hat.visible = on


func is_hat_visible() -> bool:
	return _hat != null and _hat.visible


## For the local player's own body while the camera is in their head: the hat brim would
## fill the top of the view, so it only casts its shadow.
func set_first_person(on: bool) -> void:
	if _hat == null:
		return
	var mode: GeometryInstance3D.ShadowCastingSetting = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for mesh: Node in _hat.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = mode


## The wrist cuff nodes ("L"/"R"), for chains to follow.
func get_wrist(side: String) -> Node3D:
	return _wrists.get(side) as Node3D


## Hides the name tag (your own, in first person).
func set_label_visible(on: bool) -> void:
	_label.visible = on


func _freeze_dead() -> void:
	hold_pose(ANIM_FLINCH, 0.1)


## Rotation about the seated hips: t = 0 upright, 1 fully slumped.
func _slump_transform(t: float) -> Transform3D:
	var pivot: Vector3 = metric_vector("seated_hips")
	var turn := Transform3D(Basis(Vector3.RIGHT, DEATH_SLUMP * t), Vector3.ZERO)
	return Transform3D(Basis(), pivot) * turn * Transform3D(Basis(), -pivot)


## A one-shot puff of pale smoke rising from the head.
func _puff() -> void:
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.amount = 24
	puff.lifetime = 1.4
	puff.explosiveness = 0.9
	puff.direction = Vector3.UP
	puff.spread = 60.0
	puff.initial_velocity_min = 0.3
	puff.initial_velocity_max = 0.8
	puff.gravity = Vector3(0, 0.25, 0)
	puff.scale_amount_min = 0.6
	puff.scale_amount_max = 1.4
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	sphere.radial_segments = 8
	sphere.rings = 4
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.85, 0.85, 0.8, 0.55)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = smoke
	puff.mesh = sphere
	puff.position = metric_vector("seated_eyes") + Vector3(0, 0.1, 0)
	add_child(puff)
	puff.emitting = true
	puff.finished.connect(puff.queue_free)


func _play_once(animation: StringName) -> void:
	if _anim == null or not _anim.has_animation(animation):
		return
	_anim.play(animation, 0.08)
	if animation != ANIM_LOOK_UP:
		_anim.queue(ANIM_IDLE)


func _apply_look() -> void:
	var shirt: Color = color_for(look_index)
	_material.set_shader_parameter("shirt_color", shirt)
	# Different strides so neighbours rarely share skin tone and trousers with a shirt.
	_material.set_shader_parameter("skin_color", SKIN_TONES[posmod(look_index * 5 + 1, SKIN_TONES.size())])
	_material.set_shader_parameter("trouser_color", TROUSER_COLORS[posmod(look_index, TROUSER_COLORS.size())])
	_label.text = display_name
	_label.modulate = shirt.lightened(0.35)


func _add_cuffs() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.40, 0.38)
	steel.metallic = 0.85
	steel.roughness = 0.45
	var ring := TorusMesh.new()
	ring.inner_radius = 0.038
	ring.outer_radius = 0.052
	for side: String in ["L", "R"]:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "Hand." + side
		_skeleton.add_child(attachment)
		var cuff := MeshInstance3D.new()
		cuff.mesh = ring
		cuff.material_override = steel
		# A little up the forearm from the wrist joint; the bone's Y axis runs along the hand.
		cuff.position = Vector3(0.0, -0.035, 0.0)
		attachment.add_child(cuff)
		_wrists[side] = cuff


func _add_hat() -> void:
	var bone: int = _skeleton.find_bone(HAT_BONE)
	if bone == -1:
		push_error("Player model has no %s bone; the hat is skipped" % HAT_BONE)
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = HAT_BONE
	_skeleton.add_child(attachment)
	_hat = HAT_MODEL.instantiate()
	_hat.name = "Hat"
	# hat.glb is in the model's rest space; undo the bone's rest placement so it sits on the
	# head in the rest pose and then moves with the bone.
	var head_rest: Transform3D = _skeleton_in_model() * _skeleton.get_bone_global_rest(bone)
	_hat.transform = head_rest.affine_inverse()
	attachment.add_child(_hat)


## The skeleton's transform relative to the imported model's root.
func _skeleton_in_model() -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node = _skeleton
	while node != null and node != _model:
		if node is Node3D:
			result = (node as Node3D).transform * result
		node = node.get_parent()
	return result
