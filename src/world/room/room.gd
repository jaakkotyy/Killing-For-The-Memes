class_name GameRoom
extends Node3D
## The 3D room: a round table with one seat per player, the wall TV, a flickering lamp and
## a spotlight. Reads players from the Session mirror and never changes game state
## itself. In a real game a MatchPresenter drives it from match snapshots (TV, spotlight,
## camera, shots, deaths) and a MatchHud shows timers, voting and the win screen.
## The local player's MemeStation puts the meme editor on their CRT.
##
## `--room-preview=<n>` opens this scene directly with n fake players (no network).

enum View { SEAT, TV, OVERVIEW }

const TV_SCENE: PackedScene = preload("res://src/world/wall_tv/wall_tv.tscn")
const HUD_SCENE: PackedScene = preload("res://src/ui/hud/match_hud.tscn")

const ROOM_HALF_SIZE: float = 5.0
const CEILING_HEIGHT: float = 3.4
const SEAT_RADIUS: float = 2.1
const TV_POSITION: Vector3 = Vector3(0.0, 2.05, -ROOM_HALF_SIZE + 0.42)
# Off-centre so the lamp shade doesn't hide the TV.
const OVERVIEW_EYE: Vector3 = Vector3(2.7, 2.9, 3.9)
const OVERVIEW_TARGET: Vector3 = Vector3(-0.2, 0.8, -0.9)
const CAMERA_GLIDE_SECONDS: float = 0.9
## Narrow enough that a meme on the wall TV is readable from any seat.
const TV_VIEW_FOV: float = 32.0
const DEMO_STEP_SECONDS: float = 3.0

var _seats: Dictionary = {}  # player id -> Seat
var _local_id: int = 0
var _view: View = View.SEAT
var _spotlight_player: int = 0
var _lamp: OmniLight3D
var _lamp_time: float = 0.0
var _tv: WallTv
var _station: MemeStation
var _presenter: MatchPresenter
var _match_hud: MatchHud
## Whether the local player may open the meme editor now (the presenter allows it during
## creation only; the preview always does).
var _editing_allowed: bool = true
## Set false before adding the room to stop the preview's spotlight demo (staged shots).
var demo_enabled: bool = true
## Fake players for a preview room; -1 means use the --room-preview launch flag.
var preview_players: int = -1

@onready var _camera: CameraRig = %CameraRig
@onready var _spotlight: SpotLight3D = %Spotlight
@onready var _leave_button: Button = %LeaveButton
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	_build_environment()
	_build_shell()
	_build_table()
	_build_lamp()
	_tv = TV_SCENE.instantiate()
	_tv.position = TV_POSITION
	add_child(_tv)

	var players: Array[LobbyPlayer] = _players()
	_build_seats(players)
	_build_station()
	_spotlight.visible = false

	_leave_button.pressed.connect(_on_leave_pressed)
	if _is_preview():
		if demo_enabled:
			_start_demo()
		_set_view(_initial_view(), 0.0)
	else:
		Session.lobby_updated.connect(_on_lobby_updated)
		_set_view(_initial_view(), 0.0)
		_match_hud = HUD_SCENE.instantiate()
		add_child(_match_hud)
		_presenter = MatchPresenter.new()
		add_child(_presenter)
		_presenter.setup(self)
	if _station != null and App.options != null and App.options.room_camera == "editor":
		_station.open(true)


## The local player's editor and CRT zoom. In a real game the presenter sets the prompt
## and the countdown and sends submissions to the server; the preview uses a local prompt
## and only shows a submitted meme on the wall TV.
func _build_station() -> void:
	var seat: Seat = _seats.get(_local_id) as Seat
	if seat == null:
		return
	_station = MemeStation.new()
	add_child(_station)
	_station.setup(_camera, seat)
	_station.open_changed.connect(func(_open: bool) -> void: _update_hint())
	if not _is_preview():
		return
	var file := FileAccess.open("res://data/prompts/default.json", FileAccess.READ)
	var deck: PromptDeck = PromptDeck.from_json(file.get_as_text() if file != null else "")
	_station.editor.set_prompt(deck.draw() if deck != null else tr("Make a meme!"))
	_station.editor.set_time_left(GameConfig.new().create_duration)
	_station.meme_submitted.connect(_on_preview_meme_submitted)


func _on_preview_meme_submitted(spec: MemeSpec) -> void:
	print("[Room] Meme submitted: %s" % spec.to_dict())
	_tv.show_meme(spec)


## Preview only: the spotlight hops between players, who flinch when it lands on them,
## so lighting and animations can be checked without a running game.
func _start_demo() -> void:
	var timer := Timer.new()
	timer.wait_time = DEMO_STEP_SECONDS
	timer.timeout.connect(_demo_step)
	add_child(timer)
	timer.start()
	get_tree().create_timer(0.5).timeout.connect(_demo_step)


func _demo_step() -> void:
	var ids: Array = _seats.keys()
	ids.sort()
	if ids.is_empty():
		return
	var next: int = (ids.find(_spotlight_player) + 1) % ids.size()
	focus_spotlight(ids[next])
	(_seats[ids[next]] as Seat).avatar.flinch()


## Points the spotlight at a player (0 turns it off). Used by the round loop in M5.
func focus_spotlight(player_id: int) -> void:
	_spotlight_player = player_id
	var seat: Seat = _seats.get(player_id) as Seat
	_spotlight.visible = seat != null
	if seat != null:
		_spotlight.look_at(seat.get_spotlight_target(), Vector3.UP)


func get_seat(player_id: int) -> Seat:
	return _seats.get(player_id) as Seat


func get_local_id() -> int:
	return _local_id


## The local player's meme station, or null when they have no seat.
func get_station() -> MemeStation:
	return _station


func get_match_hud() -> MatchHud:
	return _match_hud


## Glides the camera to a view (the presenter's choreography; Tab still overrides it).
func set_view(view: View) -> void:
	if view != _view:
		_set_view(view, CAMERA_GLIDE_SECONDS)


func get_view() -> View:
	return _view


## Allows or forbids opening the meme editor; forbidding closes it if it is open.
func set_editing_allowed(allowed: bool) -> void:
	_editing_allowed = allowed
	if _station != null:
		_station.enabled = allowed and _view == View.SEAT
		if not allowed and _station.is_open():
			_station.close()
	_update_hint()


func get_tv() -> WallTv:
	return _tv


func set_hud_visible(on: bool) -> void:
	%Hud.visible = on


func _process(delta: float) -> void:
	_lamp_time += delta
	# A tired bulb: steady hum with the occasional stutter.
	var stutter: float = 1.0 if fmod(_lamp_time, 7.3) > 0.18 else 0.35 + 0.4 * randf()
	_lamp.light_energy = (1.9 + 0.08 * sin(_lamp_time * 23.0)) * stutter


func _unhandled_input(event: InputEvent) -> void:
	if _station != null and _station.is_open():
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_TAB:
		_set_view(((_view + 1) % View.size()) as View, CAMERA_GLIDE_SECONDS)
		get_viewport().set_input_as_handled()
		return
	# The demo keys would fight the presenter in a real game.
	if not OS.is_debug_build() or not _is_preview():
		return
	match key:
		KEY_F:
			var ids: Array = _seats.keys()
			if not ids.is_empty():
				(_seats[ids.pick_random()] as Seat).avatar.flinch()
		KEY_G:
			var ids: Array = _seats.keys()
			ids.sort()
			var next: int = ids.find(_spotlight_player) + 1
			focus_spotlight(ids[next] if next < ids.size() else 0)
		_:
			return
	get_viewport().set_input_as_handled()


func _set_view(view: View, duration: float) -> void:
	var seat: Seat = _seats.get(_local_id) as Seat
	if seat == null and view != View.OVERVIEW:
		view = View.OVERVIEW
	_view = view
	if seat != null:
		seat.avatar.set_first_person(view != View.OVERVIEW)
	if _station != null:
		_station.enabled = _editing_allowed and view == View.SEAT
	_update_hint()
	match view:
		View.SEAT:
			_camera.move_to(seat.get_eye_pose(), 62.0, duration, true)
		View.TV:
			_camera.move_to(CameraRig.pose_looking_at(seat.get_eye_position(), TV_POSITION), TV_VIEW_FOV, duration, true)
		View.OVERVIEW:
			_camera.move_to(CameraRig.pose_looking_at(OVERVIEW_EYE, OVERVIEW_TARGET), 62.0, duration, false)


func _update_hint() -> void:
	var parts: PackedStringArray = []
	if _station != null and _station.is_open():
		parts.append(tr("Esc: look up"))
	else:
		if _station != null and _editing_allowed and _view == View.SEAT:
			parts.append(tr("E or click your monitor: make a meme"))
		parts.append(tr("Tab: camera"))
		if OS.is_debug_build() and _is_preview():
			parts.append(tr("Dev keys: F flinch · G spotlight"))
	_hint_label.text = "   ·   ".join(parts)


func _initial_view() -> View:
	match App.options.room_camera if App.options != null else "":
		"tv":
			return View.TV
		"overview":
			return View.OVERVIEW
	return View.SEAT


func _is_preview() -> bool:
	return _preview_count() > 0


func _preview_count() -> int:
	if preview_players >= 0:
		return preview_players
	return App.options.room_preview if App.options != null else 0


func _players() -> Array[LobbyPlayer]:
	if _is_preview():
		var fake: Array[LobbyPlayer] = []
		var names: PackedStringArray = ["You", "Bertha", "Gus", "Mildred", "Vlad", "Pickles", "Dot", "Reginald"]
		for i: int in mini(_preview_count(), Protocol.MAX_PLAYERS):
			fake.append(LobbyPlayer.new(i + 1, names[i], i))
		_local_id = 1
		return fake
	_local_id = Session.local_peer_id()
	return Session.lobby.get_players()


func _build_seats(players: Array[LobbyPlayer]) -> void:
	var ordered: Array[LobbyPlayer] = players.duplicate()
	ordered.sort_custom(func(a: LobbyPlayer, b: LobbyPlayer) -> bool: return a.seat < b.seat)
	var transforms: Array[Transform3D] = SeatLayout.seat_transforms(ordered.size(), SEAT_RADIUS)
	var table_height: float = _table_height()
	for i: int in ordered.size():
		var player: LobbyPlayer = ordered[i]
		var seat := Seat.new()
		seat.transform = transforms[i]
		add_child(seat)
		seat.setup(player.id, player.name, player.seat, table_height, SEAT_RADIUS - _table_radius())
		seat.avatar.set_label_visible(player.id != _local_id)
		_seats[player.id] = seat


func _on_lobby_updated(lobby: LobbyState) -> void:
	# Players who walked out stay in their chair, greyed out (M5 adds the proper reactions).
	for id: int in _seats:
		if not lobby.has_player(id):
			(_seats[id] as Seat).avatar.set_spectator(true)


func _on_leave_pressed() -> void:
	if _is_preview():
		get_tree().quit()
	else:
		Session.leave()


func _table_height() -> float:
	# Just under the seated forearms, so hands rest on the keyboard.
	return float(PlayerAvatar.metrics().get("forearm_bottom", 0.72)) - 0.01


func _table_radius() -> float:
	return SEAT_RADIUS - 0.05


# --- Static geometry ---------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.26, 0.24)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.75, 0.7, 0.62)
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _surface(color: Color, roughness: float, noise_scale: float, noise_strength: float) -> StandardMaterial3D:
	# Procedural grime: tinted noise, so the room needs no third-party textures.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.01
	noise.fractal_octaves = 5
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, color.darkened(noise_strength))
	ramp.set_color(1, color.lightened(noise_strength * 0.3))
	texture.color_ramp = ramp
	var bump := NoiseTexture2D.new()
	bump.width = 512
	bump.height = 512
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 4.0
	bump.noise = noise
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.normal_enabled = true
	material.normal_texture = bump
	material.normal_scale = 0.4
	material.roughness = roughness
	material.uv1_scale = Vector3(noise_scale, noise_scale, noise_scale)
	material.uv1_triplanar = true
	return material


func _build_shell() -> void:
	var size: float = ROOM_HALF_SIZE * 2.0
	var floor_material := _surface(Color(0.2, 0.19, 0.17), 0.85, 0.35, 0.6)
	var wall_material := _surface(Color(0.3, 0.33, 0.28), 0.9, 0.3, 0.55)
	var ceiling_material := _surface(Color(0.14, 0.14, 0.13), 0.95, 0.3, 0.4)
	_block(Vector3(size, 0.1, size), floor_material, Vector3(0, -0.05, 0))
	_block(Vector3(size, 0.1, size), ceiling_material, Vector3(0, CEILING_HEIGHT + 0.05, 0))
	for side: float in [-1.0, 1.0]:
		_block(Vector3(0.1, CEILING_HEIGHT, size), wall_material, Vector3(side * (ROOM_HALF_SIZE + 0.05), CEILING_HEIGHT / 2.0, 0))
		_block(Vector3(size, CEILING_HEIGHT, 0.1), wall_material, Vector3(0, CEILING_HEIGHT / 2.0, side * (ROOM_HALF_SIZE + 0.05)))
	# Tile stripe at waist height, a drain, a locked door and some pipes.
	var stripe := _surface(Color(0.42, 0.4, 0.33), 0.5, 1.5, 0.4)
	for side: float in [-1.0, 1.0]:
		_block(Vector3(0.02, 0.12, size), stripe, Vector3(side * (ROOM_HALF_SIZE - 0.01), 1.0, 0))
		_block(Vector3(size, 0.12, 0.02), stripe, Vector3(0, 1.0, side * (ROOM_HALF_SIZE - 0.01)))
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.17, 0.15)
	iron.metallic = 0.8
	iron.roughness = 0.7
	_block(Vector3(0.5, 0.01, 0.5), iron, Vector3(1.2, 0.005, 3.6))
	_block(Vector3(1.0, 2.1, 0.08), iron, Vector3(ROOM_HALF_SIZE - 0.01, 1.05, 1.5)).rotation.y = PI / 2.0
	for i: int in 3:
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.06 + 0.02 * i
		pipe.bottom_radius = pipe.top_radius
		pipe.height = size
		var instance := MeshInstance3D.new()
		instance.mesh = pipe
		instance.material_override = iron
		instance.position = Vector3(-ROOM_HALF_SIZE + 0.25 + 0.22 * i, CEILING_HEIGHT - 0.2 - 0.05 * i, 0)
		instance.rotation.x = PI / 2.0
		add_child(instance)


func _build_table() -> void:
	var top_material := _surface(Color(0.26, 0.18, 0.12), 0.75, 0.8, 0.5)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.16, 0.15)
	metal.metallic = 0.75
	metal.roughness = 0.55
	var height: float = _table_height()
	var top := CylinderMesh.new()
	top.top_radius = _table_radius()
	top.bottom_radius = _table_radius()
	top.height = 0.06
	top.radial_segments = 64
	_add_mesh(top, top_material, Vector3(0, height - 0.03, 0))
	var column := CylinderMesh.new()
	column.top_radius = 0.18
	column.bottom_radius = 0.35
	column.height = height - 0.06
	_add_mesh(column, metal, Vector3(0, (height - 0.06) / 2.0, 0))


func _build_lamp() -> void:
	var shade := CylinderMesh.new()
	shade.top_radius = 0.08
	shade.bottom_radius = 0.38
	shade.height = 0.3
	var shade_material := StandardMaterial3D.new()
	shade_material.albedo_color = Color(0.22, 0.24, 0.2)
	shade_material.metallic = 0.6
	shade_material.roughness = 0.5
	shade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp_height: float = 2.45
	_add_mesh(shade, shade_material, Vector3(0, lamp_height, 0))
	var cord := CylinderMesh.new()
	cord.top_radius = 0.008
	cord.bottom_radius = 0.008
	cord.height = CEILING_HEIGHT - lamp_height
	_add_mesh(cord, shade_material, Vector3(0, (CEILING_HEIGHT + lamp_height) / 2.0, 0))
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	var bulb_material := StandardMaterial3D.new()
	bulb_material.emission_enabled = true
	bulb_material.emission = Color(1.0, 0.78, 0.5)
	bulb_material.emission_energy_multiplier = 6.0
	_add_mesh(bulb, bulb_material, Vector3(0, lamp_height - 0.12, 0))
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.78, 0.52)
	_lamp.omni_range = 7.0
	_lamp.omni_attenuation = 1.2
	_lamp.shadow_enabled = true
	_lamp.light_volumetric_fog_energy = 0.6
	_lamp.position = Vector3(0, lamp_height - 0.16, 0)
	add_child(_lamp)


func _block(size: Vector3, material: Material, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, material, at)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance
