class_name Seat
extends Node3D
## One place at the table: a chair, the player's body, a keyboard, their CRT monitor and the
## chains from their wrists to bolts in the table. Placed by the room from SeatLayout.
##
## Seat space: origin on the floor under the player's knees, +Z toward the table centre.
## The table edge is at `table_edge` along +Z.

const AVATAR_SCENE: PackedScene = preload("res://src/world/player/player_avatar.tscn")
const MONITOR_SCENE: PackedScene = preload("res://src/world/crt/crt_monitor.tscn")
## The artist's drinks (tools/blender/build_props.py), handed out round the table by seat.
const DRINK_SCENES: Array[PackedScene] = [
	preload("res://assets/models/props/can.glb"),
	preload("res://assets/models/props/cup.glb"),
	preload("res://assets/models/props/beer.glb"),
]
## Seat-space spot for the drink: right of the keyboard, clear of the monitor and the chains.
const DRINK_OFFSET: Vector2 = Vector2(-0.36, 0.6)

var player_id: int = 0
var table_height: float = 0.71
var table_edge: float = 0.05

var avatar: PlayerAvatar
var monitor: CrtMonitor
var drink: Node3D
## Guess mode's sign over the player's head (made on first use).
var placard: IdentityPlacard


## Builds everything. `look_index` picks the player's colours.
func setup(p_player_id: int, player_name: String, look_index: int, p_table_height: float, p_table_edge: float) -> void:
	player_id = p_player_id
	table_height = p_table_height
	table_edge = p_table_edge
	name = "Seat_%d" % player_id

	avatar = AVATAR_SCENE.instantiate()
	avatar.setup(player_name, look_index)
	add_child(avatar)
	_build_chair()
	_build_desk_items()
	_build_drink(look_index)
	monitor = MONITOR_SCENE.instantiate()
	monitor.glow_color = PlayerAvatar.color_for(look_index).lerp(Color(0.4, 1.0, 0.75), 0.6)
	monitor.position = Vector3(0, table_height, 1.02)
	monitor.rotation.y = PI  # screen toward the player
	add_child(monitor)
	_build_chains.call_deferred()


## Camera pose for this player's first-person view, looking at their monitor.
func get_eye_pose() -> Transform3D:
	var eye: Vector3 = to_global(PlayerAvatar.metric_vector("seated_eyes") + Vector3(0, 0, 0.07))
	# Aim a little above the screen so the room stays in view around it.
	var screen: Vector3 = monitor.get_screen_transform().origin + Vector3.UP * 0.14
	return CameraRig.pose_looking_at(eye, screen)


func get_eye_position() -> Vector3:
	return to_global(PlayerAvatar.metric_vector("seated_eyes") + Vector3(0, 0, 0.07))


## A muzzle flash from under the table edge: this player just fired at someone.
func flash_shot(target: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.light_energy = 6.0
	flash.omni_range = 2.2
	flash.position = Vector3(0.18, table_height + 0.05, table_edge + 0.25)
	add_child(flash)
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 16
	sparks.lifetime = 0.25
	sparks.explosiveness = 1.0
	sparks.spread = 12.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3.ZERO
	var bit := SphereMesh.new()
	bit.radius = 0.008
	bit.height = 0.016
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.85, 0.4)
	bit.material = hot
	sparks.mesh = bit
	flash.add_child(sparks)
	var aim: Vector3 = target - flash.global_position
	if aim.length_squared() > 0.0001:
		sparks.direction = flash.global_basis.inverse() * aim.normalized()
	sparks.emitting = true
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.15)
	tween.tween_interval(0.3)
	tween.tween_callback(flash.queue_free)


## Guess mode: shows [param text] on the sign over this player's head (made on first use).
func show_placard(text: String, state: IdentityPlacard.State) -> void:
	if placard == null:
		placard = IdentityPlacard.new()
		placard.name = "Placard"
		placard.position = PlayerAvatar.metric_vector("seated_eyes") + Vector3(0, 0.66, -0.05)
		add_child(placard)
	placard.visible = true
	placard.show_identity(text, state)


func hide_placard() -> void:
	if placard != null:
		placard.visible = false


## Where a spotlight should aim to light this player.
func get_spotlight_target() -> Vector3:
	return to_global(Vector3(0, 0.95, -0.05))


func _build_chair() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.22, 0.2)
	metal.metallic = 0.7
	metal.roughness = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.2, 0.13)
	wood.roughness = 0.85
	var seat_top: float = float(PlayerAvatar.metrics().get("seat_height", 0.4))
	var hips_z: float = PlayerAvatar.metric_vector("seated_hips").z
	var seat_z: float = hips_z - 0.06
	_box(Vector3(0.5, 0.05, 0.46), wood, Vector3(0, seat_top - 0.025, seat_z))
	_box(Vector3(0.5, 0.55, 0.04), wood, Vector3(0, seat_top + 0.35, seat_z - 0.26)).rotation.x = -0.08
	for x: float in [-0.22, 0.22]:
		for z: float in [-0.2, 0.2]:
			_box(Vector3(0.035, seat_top - 0.05, 0.035), metal, Vector3(x, (seat_top - 0.05) / 2.0, seat_z + z))
		_box(Vector3(0.035, 0.6, 0.035), metal, Vector3(x, seat_top + 0.3, seat_z - 0.25))


func _build_desk_items() -> void:
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.5, 0.47, 0.41)
	plastic.roughness = 0.7
	var keys := StandardMaterial3D.new()
	keys.albedo_color = Color(0.32, 0.3, 0.27)
	keys.roughness = 0.8
	var wrist: Vector3 = PlayerAvatar.metric_vector("seated_wrist_l")
	var keyboard_z: float = wrist.z + 0.11
	_box(Vector3(0.44, 0.025, 0.15), plastic, Vector3(0, table_height + 0.012, keyboard_z))
	_box(Vector3(0.40, 0.012, 0.11), keys, Vector3(0, table_height + 0.03, keyboard_z + 0.005))


## Which drink a seat gets: deterministic, so every client sees the same table.
static func drink_index(look_index: int) -> int:
	return posmod(look_index, DRINK_SCENES.size())


func _build_drink(look_index: int) -> void:
	drink = DRINK_SCENES[drink_index(look_index)].instantiate()
	drink.name = "Drink"
	drink.position = Vector3(DRINK_OFFSET.x, table_height, DRINK_OFFSET.y)
	# A different turn per seat, so the cup handles and can seams don't all line up.
	drink.rotation.y = look_index * 2.4
	add_child(drink)


func _build_chains() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.34, 0.32)
	steel.metallic = 0.9
	steel.roughness = 0.5
	var bolt_mesh := TorusMesh.new()
	bolt_mesh.inner_radius = 0.012
	bolt_mesh.outer_radius = 0.022
	for side: String in ["L", "R"]:
		var wrist: Vector3 = PlayerAvatar.metric_vector("seated_wrist_" + side.to_lower())
		var bolt_local := Vector3(wrist.x * 0.35, table_height + 0.022, table_edge + 0.07)
		var bolt := MeshInstance3D.new()
		bolt.mesh = bolt_mesh
		bolt.material_override = steel
		bolt.position = bolt_local
		bolt.rotation.x = PI / 2.0
		add_child(bolt)
		var chain := WristChain.new()
		add_child(chain)
		chain.setup(avatar.get_wrist(side), to_global(bolt_local + Vector3(0, 0.02, 0)), steel)


func _box(size: Vector3, material: Material, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance
