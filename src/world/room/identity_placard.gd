class_name IdentityPlacard
extends Node3D
## Guess mode's sign over a player's head, hanging from two chains: everyone else's shows
## their secret identity, your own shows "???" until you solve it. It turns to face the
## camera around its chains, so everyone at the table can read it.
##
## Placed by Seat (seat space, above the name label).

enum State { HIDDEN, KNOWN, SOLVED }

const BOARD_SIZE: Vector2 = Vector2(0.78, 0.3)
const PIXEL_SIZE: float = 0.0022
const CHAIN_LENGTH: float = 1.4
const KNOWN_COLOR: Color = Color(0.95, 0.9, 0.78)
const HIDDEN_COLOR: Color = Color(0.85, 0.3, 0.25)
const SOLVED_COLOR: Color = Color(0.45, 1.0, 0.62)

var state: State = State.HIDDEN
var text: String = ""

var _label: Label3D
var _board: MeshInstance3D
var _board_material: StandardMaterial3D


func _ready() -> void:
	_board_material = StandardMaterial3D.new()
	_board_material.albedo_color = Color(0.12, 0.1, 0.08)
	_board_material.roughness = 0.9
	var board := BoxMesh.new()
	board.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.015)
	_board = MeshInstance3D.new()
	_board.mesh = board
	_board.material_override = _board_material
	_board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_board)

	_label = Label3D.new()
	_label.pixel_size = PIXEL_SIZE
	_label.font_size = 40
	_label.outline_size = 0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = (BOARD_SIZE.x - 0.06) / PIXEL_SIZE
	_label.position = Vector3(0, 0, 0.01)
	_label.shaded = false
	add_child(_label)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.34, 0.32)
	steel.metallic = 0.9
	steel.roughness = 0.5
	var link := CylinderMesh.new()
	link.top_radius = 0.004
	link.bottom_radius = 0.004
	link.height = CHAIN_LENGTH
	for x: float in [-BOARD_SIZE.x * 0.4, BOARD_SIZE.x * 0.4]:
		var chain := MeshInstance3D.new()
		chain.mesh = link
		chain.material_override = steel
		chain.position = Vector3(x, BOARD_SIZE.y / 2.0 + CHAIN_LENGTH / 2.0, 0)
		add_child(chain)
	show_identity(text, state)


## What the sign says. HIDDEN shows "???" whatever [param p_text] is.
func show_identity(p_text: String, p_state: State) -> void:
	text = p_text
	state = p_state
	if _label == null:
		return
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
	_board_material.albedo_color = Color(0.06, 0.16, 0.09) if state == State.SOLVED else Color(0.12, 0.1, 0.08)


func get_label_text() -> String:
	return _label.text if _label != null else ""


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Turn about the chains (Y) only, so the sign keeps hanging straight.
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() > 0.0001:
		global_rotation.y = atan2(to_camera.x, to_camera.z)
