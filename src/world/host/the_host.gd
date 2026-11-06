class_name TheHost
extends Node3D
## The game's host (greybox): a lanky game-show mannequin in a stained tuxedo whose head is a
## cracked CRT showing a pixel-art face. Original character, see docs/GAME_DESIGN.md.
##
## Built from primitives until the real model exists. The origin is on the floor; faces +Z.

const SCREEN_SHADER: Shader = preload("res://src/world/crt/crt_screen.gdshader")

## 16x12 pixel faces: '#' lit, '.' dark. Drawn for this game.
const FACES: Dictionary = {
	&"grin": [
		"................",
		"..###......###..",
		".#...#....#...#.",
		".#.#.#....#.#.#.",
		"..###......###..",
		"................",
		"#..............#",
		"##............##",
		".##############.",
		"..#.#.#.#.#.#.#.",
		"...##########...",
		"................",
	],
	&"surprised": [
		"................",
		"..###......###..",
		".#...#....#...#.",
		".#.#.#....#.#.#.",
		"..###......###..",
		"................",
		"......####......",
		".....#....#.....",
		".....#....#.....",
		".....#....#.....",
		"......####......",
		"................",
	],
	&"sinister": [
		"................",
		".#####....#####.",
		"..#.#......#.#..",
		"...##......##...",
		"................",
		"................",
		"................",
		"#..............#",
		".#............#.",
		"..############..",
		"................",
		"................",
	],
}
## A crack across the glass, as pixel coordinates on the face grid.
const CRACK: Array[Vector2i] = [
	Vector2i(11, 0), Vector2i(11, 1), Vector2i(12, 2), Vector2i(12, 3), Vector2i(13, 4),
	Vector2i(14, 4), Vector2i(15, 5), Vector2i(12, 4), Vector2i(11, 5),
]
const FACE_SCALE: int = 16

@export var face_color: Color = Color(0.45, 1.0, 0.55)

var _face_material: ShaderMaterial
var _faces: Dictionary = {}
var _head: Node3D
var _torso: Node3D
var _time: float = 0.0


func _ready() -> void:
	_build()
	set_expression(&"grin")


func set_expression(expression: StringName) -> void:
	if not _faces.has(expression):
		_faces[expression] = _make_face(expression)
	_face_material.set_shader_parameter("screen_texture", _faces[expression])
	_face_material.set_shader_parameter("has_picture", true)


## World position of the face, for cameras and spotlights.
func get_head_position() -> Vector3:
	return _head.global_position


func _process(delta: float) -> void:
	_time += delta
	# Unsettling, slightly too smooth sway.
	_torso.rotation.z = sin(_time * 0.8) * 0.035
	_head.rotation = Vector3(sin(_time * 0.53) * 0.05, sin(_time * 0.37) * 0.12, sin(_time * 1.1) * 0.04)


func _make_face(expression: StringName) -> ImageTexture:
	var rows: Array = FACES.get(expression, FACES[&"grin"])
	var image := Image.create(16, 12, false, Image.FORMAT_RGB8)
	image.fill(Color(0.02, 0.05, 0.03))
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			if row[x] == "#":
				image.set_pixel(x, y, face_color)
	for pixel: Vector2i in CRACK:
		image.set_pixel(pixel.x, pixel.y, Color(0.75, 0.8, 0.78))
	# Upscale with nearest so the pixels stay crisp through linear filtering.
	image.resize(16 * FACE_SCALE, 12 * FACE_SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func _build() -> void:
	var suit := _material(Color(0.07, 0.065, 0.075), 0.55)
	var shirt := _material(Color(0.72, 0.68, 0.58), 0.8)
	var red := _material(Color(0.55, 0.05, 0.06), 0.5)
	var skin := _material(Color(0.82, 0.78, 0.72), 0.35)  # glossy mannequin plastic
	var case_material := _material(Color(0.33, 0.31, 0.28), 0.6)

	# Legs: far too long.
	for side: float in [-1.0, 1.0]:
		_add(_cylinder(0.055, 1.15), suit, Vector3(side * 0.11, 0.575, 0.0))
		_add(_box(Vector3(0.12, 0.06, 0.26)), suit, Vector3(side * 0.11, 0.03, 0.05))

	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.15, 0)
	add_child(_torso)
	_add(_box(Vector3(0.42, 0.72, 0.22)), suit, Vector3(0, 0.36, 0), _torso)
	_add(_box(Vector3(0.14, 0.5, 0.01)), shirt, Vector3(0, 0.42, 0.112), _torso)
	_add(_box(Vector3(0.14, 0.05, 0.03)), red, Vector3(0, 0.64, 0.125), _torso)
	_add(_box(Vector3(0.05, 0.06, 0.035)), red, Vector3(0, 0.64, 0.13), _torso)
	_add(_cylinder(0.035, 0.12), skin, Vector3(0, 0.76, 0), _torso)
	# Arms hang to the knees, one hand raised as if presenting the TV.
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.25, 0.66, 0)
		arm.rotation = Vector3(-1.2 if side > 0 else 0.0, 0.0, side * (0.55 if side > 0 else 0.08))
		_torso.add_child(arm)
		_add(_cylinder(0.045, 0.9), suit, Vector3(0, -0.45, 0), arm)
		_add(_box(Vector3(0.07, 0.16, 0.035)), skin, Vector3(0, -0.98, 0), arm)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.82, 0)
	_torso.add_child(_head)
	_add(_box(Vector3(0.5, 0.4, 0.4)), case_material, Vector3(0, 0.2, 0), _head)
	_add(_box(Vector3(0.36, 0.3, 0.2)), case_material, Vector3(0, 0.2, -0.27), _head)
	_face_material = ShaderMaterial.new()
	_face_material.shader = SCREEN_SHADER
	_face_material.set_shader_parameter("brightness", 2.6)
	_face_material.set_shader_parameter("curvature", 0.1)
	_face_material.set_shader_parameter("scanlines", 96.0)
	var glass := QuadMesh.new()
	glass.size = Vector2(0.42, 0.315)
	_add(glass, _face_material, Vector3(0, 0.2, 0.202), _head)
	# Antenna, slightly bent.
	_add(_cylinder(0.006, 0.35), case_material, Vector3(0.08, 0.55, -0.05), _head).rotation = Vector3(0, 0, -0.3)
	var glow := OmniLight3D.new()
	glow.light_color = face_color
	glow.light_energy = 0.6
	glow.omni_range = 1.6
	glow.light_specular = 0.0
	glow.position = Vector3(0, 0.2, 0.45)
	_head.add_child(glow)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	return mesh


func _add(mesh: Mesh, material: Material, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance
