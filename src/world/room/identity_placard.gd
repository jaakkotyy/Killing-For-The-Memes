class_name IdentityPlacard
extends Node3D
## The sign floating over a player's head, a dark panel with a glowing edge that bobs
## gently in zero gravity: everyone else's shows their secret identity, your own shows
## "???" until you solve it. It turns to face the camera (about Y only, so it stays
## upright), so everyone at the table can read it. With a portrait URL
## (Portrait.url_for) the picture hangs above the name once it has downloaded.
##
## Placed by Seat (seat space, above the name label).

enum State { HIDDEN, KNOWN, SOLVED }

const BOARD_SIZE: Vector2 = Vector2(0.78, 0.3)
const PIXEL_SIZE: float = 0.0022
## The bob: how far (metres) and how long one bob takes (seconds).
const BOB_HEIGHT: float = 0.035
const BOB_SECONDS: float = 4.0
const EDGE_COLOR: Color = Color(0.35, 0.75, 1.0)
const KNOWN_COLOR: Color = Color(0.95, 0.9, 0.78)
const HIDDEN_COLOR: Color = Color(0.85, 0.3, 0.25)
const SOLVED_COLOR: Color = Color(0.45, 1.0, 0.62)
const PICTURE_HEIGHT: float = 0.32

var state: State = State.HIDDEN
var text: String = ""
var image_url: String = ""

var _label: Label3D
var _board: MeshInstance3D
var _board_material: StandardMaterial3D
var _picture: Sprite3D
var _edge_material: StandardMaterial3D
## Everything that bobs; the node itself stays where Seat put it.
var _float: Node3D
var _time: float = 0.0


func _ready() -> void:
	_float = Node3D.new()
	add_child(_float)
	# Each sign bobs out of step with the others.
	_time = randf() * BOB_SECONDS
	_board_material = StandardMaterial3D.new()
	_board_material.albedo_color = Color(0.04, 0.06, 0.1)
	_board_material.roughness = 0.6
	var board := BoxMesh.new()
	board.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.015)
	_board = MeshInstance3D.new()
	_board.mesh = board
	_board.material_override = _board_material
	_board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(_board)

	_label = Label3D.new()
	_label.pixel_size = PIXEL_SIZE
	_label.font_size = 40
	_label.outline_size = 0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = (BOARD_SIZE.x - 0.06) / PIXEL_SIZE
	_label.position = Vector3(0, 0, 0.01)
	_label.shaded = false
	_float.add_child(_label)

	# A thin glowing frame around the panel.
	_edge_material = StandardMaterial3D.new()
	_edge_material.albedo_color = Color(0.02, 0.04, 0.06)
	_edge_material.emission_enabled = true
	_edge_material.emission = EDGE_COLOR
	_edge_material.emission_energy_multiplier = 1.4
	for side: float in [-1.0, 1.0]:
		var horizontal := BoxMesh.new()
		horizontal.size = Vector3(BOARD_SIZE.x + 0.02, 0.01, 0.02)
		_add_edge(horizontal, Vector3(0, side * (BOARD_SIZE.y / 2.0 + 0.005), 0))
		var vertical := BoxMesh.new()
		vertical.size = Vector3(0.01, BOARD_SIZE.y + 0.02, 0.02)
		_add_edge(vertical, Vector3(side * (BOARD_SIZE.x / 2.0 + 0.005), 0, 0))
	_picture = Sprite3D.new()
	_picture.position = Vector3(0, BOARD_SIZE.y / 2.0 + PICTURE_HEIGHT / 2.0 + 0.02, 0.005)
	_picture.visible = false
	_float.add_child(_picture)
	show_identity(text, state, image_url)


## What the sign says. HIDDEN shows "???" whatever [param p_text] is, and no picture.
func show_identity(p_text: String, p_state: State, p_image_url: String = "") -> void:
	text = p_text
	state = p_state
	image_url = p_image_url if p_state != State.HIDDEN else ""
	if _label == null:
		return
	_update_picture()
	match state:
		State.HIDDEN:
			_label.text = "???"
			_label.modulate = HIDDEN_COLOR
			_label.font_size = 64
		State.KNOWN, State.SOLVED:
			_label.text = text
			_label.modulate = SOLVED_COLOR if state == State.SOLVED else KNOWN_COLOR
			# Long titles get a smaller font so they fit in two or three lines.
			_label.font_size = 40 if text.length() <= 24 else (32 if text.length() <= 48 else 26)
	_board_material.albedo_color = Color(0.06, 0.16, 0.09) if state == State.SOLVED else Color(0.04, 0.06, 0.1)
	_edge_material.emission = SOLVED_COLOR if state == State.SOLVED else (HIDDEN_COLOR if state == State.HIDDEN else EDGE_COLOR)


func has_picture() -> bool:
	return _picture != null and _picture.visible


func _update_picture() -> void:
	_picture.visible = false
	if image_url.is_empty():
		return
	var cache: PortraitCache = PortraitCache.get_instance()
	if not cache.loaded.is_connected(_on_image_loaded):
		cache.loaded.connect(_on_image_loaded)
	var texture: Texture2D = cache.get_texture(image_url)
	if texture != null:
		_on_image_loaded(image_url, texture)


func _on_image_loaded(url: String, texture: Texture2D) -> void:
	if url != image_url or texture.get_height() <= 0:
		return
	_picture.texture = texture
	_picture.pixel_size = PICTURE_HEIGHT / texture.get_height()
	_picture.visible = true


func get_label_text() -> String:
	return _label.text if _label != null else ""


func _add_edge(mesh: Mesh, at: Vector3) -> void:
	var edge := MeshInstance3D.new()
	edge.mesh = mesh
	edge.material_override = _edge_material
	edge.position = at
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(edge)


func _process(delta: float) -> void:
	_time += delta
	_float.position.y = sin(TAU * _time / BOB_SECONDS) * BOB_HEIGHT
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Turn about Y only, so the sign stays upright.
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() > 0.0001:
		global_rotation.y = atan2(to_camera.x, to_camera.z)
