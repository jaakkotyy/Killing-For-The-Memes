class_name GameRoom
extends Node3D
## The scene of the game: a round platform floating in deep space (SpaceBackdrop: stars,
## a sun, the artist's two planets), with a round table and one seat per player, the big
## screen on its pylon at the open side, and a softly glowing orb hovering over the table.
## Reads players from the Session mirror and never changes game state itself. A
## GuessPresenter drives it from match snapshots (screen, spotlight, camera, placards),
## a GuessHud shows timers, answers and standings, and the local player's SearchStation
## puts the identity database on their CRT.
##
## `--room-preview=<n> [--pack=<id>]` opens this scene directly with n fake players and a
## local game (PreviewGuessGame), no network.

enum View { SEAT, TV, OVERVIEW }

const TV_SCENE: PackedScene = preload("res://src/world/wall_tv/wall_tv.tscn")

## The platform's deck: the table and seats in the middle, space all around.
const PLATFORM_RADIUS: float = 5.2
const PLATFORM_THICKNESS: float = 0.32
const SEAT_RADIUS: float = 2.1
const TV_POSITION: Vector3 = Vector3(0.0, 2.05, -4.58)
const ORB_HEIGHT: float = 2.45
# Off-centre so the orb doesn't hide the screen.
const OVERVIEW_EYE: Vector3 = Vector3(2.7, 2.9, 3.9)
const OVERVIEW_TARGET: Vector3 = Vector3(-0.2, 0.8, -0.9)
const CAMERA_GLIDE_SECONDS: float = 0.9
## Narrow enough that the screen is readable from any seat.
const TV_VIEW_FOV: float = 32.0

var _seats: Dictionary = {}  # player id -> Seat
var _local_id: int = 0
var _view: View = View.SEAT
var _spotlight_player: int = 0
var _orb: Node3D
var _orb_light: OmniLight3D
var _time: float = 0.0
var _tv: WallTv
var _backdrop: SpaceBackdrop
var _station: SearchStation
var _presenter: GuessPresenter
var _guess_hud: GuessHud
var _preview_game: PreviewGuessGame
## Whether the local player may open the terminal now (the presenter decides).
var _editing_allowed: bool = true
## Fake players for a preview room; -1 means use the --room-preview launch flag.
var preview_players: int = -1

@onready var _camera: CameraRig = %CameraRig
@onready var _spotlight: SpotLight3D = %Spotlight
@onready var _leave_button: Button = %LeaveButton
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	_build_space()
	_build_platform()
	_build_table()
	_build_orb()
	_tv = TV_SCENE.instantiate()
	_tv.position = TV_POSITION
	_tv.pylon_height = TV_POSITION.y
	add_child(_tv)

	var players: Array[LobbyPlayer] = _players()
	_build_seats(players)
	_build_station()
	_spotlight.visible = false

	_leave_button.pressed.connect(_on_leave_pressed)
	if _is_preview():
		_start_preview(players)
	else:
		Session.lobby_updated.connect(_on_lobby_updated)
		_build_presentation(Session)
	_set_view(_initial_view(), 0.0)
	if _station != null and App.options != null and App.options.room_camera == "editor":
		_station.open(true)


## The local player's terminal and CRT zoom.
func _build_station() -> void:
	var seat: Seat = _seats.get(_local_id) as Seat
	if seat == null:
		return
	_station = SearchStation.new()
	add_child(_station)
	_station.setup(_camera, seat, _pack())
	_station.open_changed.connect(func(_open: bool) -> void: _update_hint())


## The presenter and HUD, fed by [param source] (Session or the preview game).
func _build_presentation(source: Object) -> void:
	_guess_hud = GuessHud.new(source)
	add_child(_guess_hud)
	_presenter = GuessPresenter.new()
	add_child(_presenter)
	_presenter.setup(self, source)


## Preview only: a local game where the fake players ask stock questions and answer them.
func _start_preview(players: Array[LobbyPlayer]) -> void:
	_preview_game = PreviewGuessGame.new()
	add_child(_preview_game)
	var fast: bool = App.options != null and App.options.fast_rounds
	_preview_game.setup(players, _pack(), App.fast_config() if fast else null)
	_build_presentation(_preview_game)


func _pack() -> IdentityPack:
	if not _is_preview():
		return Session.guess_pack()
	var pack_id: String = App.options.pack if App.options != null and not App.options.pack.is_empty() else "musicians"
	var pack: IdentityPack = IdentityPack.load_pack(pack_id)
	return pack if pack != null else IdentityPack.load_pack("musicians")


## Points the spotlight at a player (0 turns it off).
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


## The local player's terminal, or null when they have no seat.
func get_search_station() -> SearchStation:
	return _station


func get_guess_hud() -> GuessHud:
	return _guess_hud


## The local game of `--room-preview`, or null.
func get_preview_game() -> PreviewGuessGame:
	return _preview_game


func get_backdrop() -> SpaceBackdrop:
	return _backdrop


## Glides the camera to a view (the presenter's choreography; Tab still overrides it).
func set_view(view: View) -> void:
	if view != _view:
		_set_view(view, CAMERA_GLIDE_SECONDS)


func get_view() -> View:
	return _view


## Allows or forbids opening the CRT's terminal; forbidding closes it if it is open.
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
	_time += delta
	# The orb drifts up and down a little and its light breathes slowly.
	_orb.position.y = ORB_HEIGHT + 0.04 * sin(_time * 0.7)
	_orb_light.light_energy = 1.7 + 0.12 * sin(_time * 1.3)


func _unhandled_input(event: InputEvent) -> void:
	if _station != null and _station.is_open():
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_TAB:
		_set_view(((_view + 1) % View.size()) as View, CAMERA_GLIDE_SECONDS)
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
			parts.append(tr("E or click your monitor: search the database"))
		parts.append(tr("Tab: camera"))
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
	# Players who walked out stay in their chair, greyed out.
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

## Stars, sun and planets all around; the room's own effects (ambient occlusion) on top.
func _build_space() -> void:
	_backdrop = SpaceBackdrop.new()
	_backdrop.name = "Space"
	_backdrop.add_environment = false
	_backdrop.sun_energy = 0.9
	add_child(_backdrop)
	var env: Environment = SpaceBackdrop.environment()
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _surface(color: Color, roughness: float, metallic: float, noise_scale: float, noise_strength: float) -> StandardMaterial3D:
	# Procedural wear: tinted noise, so the platform needs no third-party textures.
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
	bump.bump_strength = 3.0
	bump.noise = noise
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.normal_enabled = true
	material.normal_texture = bump
	material.normal_scale = 0.3
	material.roughness = roughness
	material.metallic = metallic
	material.uv1_scale = Vector3(noise_scale, noise_scale, noise_scale)
	material.uv1_triplanar = true
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.7)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## A round deck with panel rings and a glowing edge, and a tapered underside, so it
## reads as something built, hanging in the void.
func _build_platform() -> void:
	var deck_material := _surface(Color(0.2, 0.21, 0.24), 0.55, 0.6, 0.35, 0.45)
	var hull_material := _surface(Color(0.12, 0.13, 0.15), 0.6, 0.7, 0.25, 0.4)
	var deck := CylinderMesh.new()
	deck.top_radius = PLATFORM_RADIUS
	deck.bottom_radius = PLATFORM_RADIUS
	deck.height = PLATFORM_THICKNESS
	deck.radial_segments = 96
	_add_mesh(deck, deck_material, Vector3(0, -PLATFORM_THICKNESS / 2.0, 0))
	var underside := CylinderMesh.new()
	underside.top_radius = PLATFORM_RADIUS - 0.1
	underside.bottom_radius = 1.2
	underside.height = 1.6
	underside.radial_segments = 64
	_add_mesh(underside, hull_material, Vector3(0, -PLATFORM_THICKNESS - 0.8, 0))
	var core := SphereMesh.new()
	core.radius = 0.5
	core.height = 0.6
	_add_mesh(core, _glow(Color(0.35, 0.7, 1.0), 2.5), Vector3(0, -PLATFORM_THICKNESS - 1.65, 0))

	var edge_glow := _glow(Color(0.35, 0.75, 1.0), 2.2)
	var faint_glow := _glow(Color(0.3, 0.6, 0.9), 0.7)
	var edge := TorusMesh.new()
	edge.inner_radius = PLATFORM_RADIUS - 0.04
	edge.outer_radius = PLATFORM_RADIUS + 0.04
	edge.rings = 96
	_add_mesh(edge, edge_glow, Vector3(0, -0.02, 0))
	# Panel seams: thin dim rings set into the deck.
	for radius: float in [3.2, 4.4]:
		var seam := TorusMesh.new()
		seam.inner_radius = radius - 0.012
		seam.outer_radius = radius + 0.012
		seam.rings = 96
		var ring := _add_mesh(seam, faint_glow, Vector3(0, 0.0, 0))
		ring.scale = Vector3(1.0, 0.2, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A low light under the deck lights the hull from below, so it isn't a black hole.
	var under_light := OmniLight3D.new()
	under_light.light_color = Color(0.35, 0.7, 1.0)
	under_light.light_energy = 1.2
	under_light.omni_range = 5.0
	under_light.position = Vector3(0, -PLATFORM_THICKNESS - 2.2, 0)
	add_child(under_light)


func _build_table() -> void:
	var top_material := _surface(Color(0.14, 0.15, 0.18), 0.45, 0.5, 0.8, 0.4)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.2)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var height: float = _table_height()
	var top := CylinderMesh.new()
	top.top_radius = _table_radius()
	top.bottom_radius = _table_radius()
	top.height = 0.06
	top.radial_segments = 64
	_add_mesh(top, top_material, Vector3(0, height - 0.03, 0))
	var trim := TorusMesh.new()
	trim.inner_radius = _table_radius() - 0.01
	trim.outer_radius = _table_radius() + 0.012
	trim.rings = 96
	var trim_ring := _add_mesh(trim, _glow(Color(0.35, 0.75, 1.0), 0.9), Vector3(0, height - 0.045, 0))
	trim_ring.scale = Vector3(1.0, 0.35, 1.0)
	var column := CylinderMesh.new()
	column.top_radius = 0.18
	column.bottom_radius = 0.35
	column.height = height - 0.06
	_add_mesh(column, metal, Vector3(0, (height - 0.06) / 2.0, 0))


## A pale orb hovering over the table: the room's main light.
func _build_orb() -> void:
	_orb = Node3D.new()
	_orb.name = "Orb"
	_orb.position = Vector3(0, ORB_HEIGHT, 0)
	add_child(_orb)
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	var orb_mesh := MeshInstance3D.new()
	orb_mesh.mesh = sphere
	orb_mesh.material_override = _glow(Color(1.0, 0.9, 0.78), 5.0)
	orb_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(orb_mesh)
	var halo := TorusMesh.new()
	halo.inner_radius = 0.2
	halo.outer_radius = 0.215
	var halo_mesh := MeshInstance3D.new()
	halo_mesh.mesh = halo
	halo_mesh.material_override = _glow(Color(0.55, 0.85, 1.0), 2.0)
	halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_mesh.rotation.x = 0.35
	_orb.add_child(halo_mesh)
	_orb_light = OmniLight3D.new()
	_orb_light.light_color = Color(1.0, 0.9, 0.8)
	_orb_light.light_energy = 1.7
	_orb_light.omni_range = 7.0
	_orb_light.omni_attenuation = 1.2
	_orb_light.shadow_enabled = true
	_orb_light.position = Vector3(0, -0.05, 0)
	_orb.add_child(_orb_light)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance
