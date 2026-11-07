class_name WallTv
extends Node3D
## The big screen at the open side of the table: a floating panel on a slim pylon that
## rises from the edge of the platform. It shows the category, whose turn it is, the
## question, the answer and the reveal. Its picture is a SubViewport (2D UI) seen through
## the same CRT shader as the players' monitors.
##
## The origin is the centre of the screen; the screen faces +Z. [member pylon_height] is
## how far the pylon reaches down to the floor.

const SCREEN_SHADER: Shader = preload("res://src/world/crt/crt_screen.gdshader")
const TITLE_COLOR: Color = Color(0.55, 0.92, 1.0)
const SUBTITLE_COLOR: Color = Color(0.78, 0.8, 0.92)
const FRAME_GLOW: Color = Color(0.35, 0.75, 1.0)

@export var screen_size: Vector2 = Vector2(1.6, 1.2)
@export var resolution: Vector2i = Vector2i(800, 600)
## From the screen's centre down to the platform floor.
@export var pylon_height: float = 2.05

var _viewport: SubViewport
var _title: Label
var _subtitle: Label
var _time: float = 0.0
var _rim: StandardMaterial3D


func _ready() -> void:
	_build_picture()
	_build_frame()


func _process(delta: float) -> void:
	_time += delta
	# The frame's light breathes slowly, like something asleep.
	_rim.emission_energy_multiplier = 1.4 + 0.5 * sin(_time * 0.9)


## The 2D scene shown on the screen.
func get_picture_root() -> SubViewport:
	return _viewport


func show_caption(title: String, subtitle: String = "") -> void:
	_title.text = title
	_subtitle.text = subtitle
	# Questions and reveal lists can be long: smaller type instead of running off the screen.
	var longest_line: int = 0
	for line: String in title.split("\n"):
		longest_line = maxi(longest_line, line.length())
	_title.add_theme_font_size_override("font_size", 64 if longest_line <= 16 else (48 if longest_line <= 28 else 38))
	var lines: int = subtitle.count("\n") + 1
	_subtitle.add_theme_font_size_override("font_size", 30 if lines <= 3 and subtitle.length() <= 60 else 24)


## The caption's title and subtitle.
func get_caption() -> PackedStringArray:
	return PackedStringArray([_title.text, _subtitle.text])


func get_screen_size() -> Vector2:
	return screen_size


func _build_picture() -> void:
	_viewport = SubViewport.new()
	_viewport.size = resolution
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var background := ColorRect.new()
	background.color = Color(0.01, 0.025, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset from the curved edges of the glass.
	box.offset_left = 40
	box.offset_right = -40
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_viewport.add_child(box)
	_title = _label(64, TITLE_COLOR)
	_subtitle = _label(30, SUBTITLE_COLOR)
	box.add_child(_title)
	box.add_child(_subtitle)
	show_caption(tr("ADRIFT"), tr("Who are you?"))


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_frame() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.16, 0.17, 0.2)
	hull.metallic = 0.85
	hull.roughness = 0.35
	_rim = StandardMaterial3D.new()
	_rim.albedo_color = Color(0.02, 0.04, 0.06)
	_rim.emission_enabled = true
	_rim.emission = FRAME_GLOW
	_rim.emission_energy_multiplier = 1.6

	# A thin back panel and a glowing edge around the glass.
	var back := BoxMesh.new()
	back.size = Vector3(screen_size.x + 0.16, screen_size.y + 0.16, 0.08)
	_add(back, hull, Vector3(0.0, 0.0, -0.06))
	for side: float in [-1.0, 1.0]:
		var vertical := BoxMesh.new()
		vertical.size = Vector3(0.025, screen_size.y + 0.12, 0.03)
		_add(vertical, _rim, Vector3(side * (screen_size.x / 2.0 + 0.05), 0.0, -0.005))
		var horizontal := BoxMesh.new()
		horizontal.size = Vector3(screen_size.x + 0.12, 0.025, 0.03)
		_add(horizontal, _rim, Vector3(0.0, side * (screen_size.y / 2.0 + 0.05), -0.005))

	# The pylon: a slim column from the back of the screen down to a round foot.
	var column := CylinderMesh.new()
	column.top_radius = 0.06
	column.bottom_radius = 0.1
	column.height = pylon_height
	_add(column, hull, Vector3(0.0, -pylon_height / 2.0, -0.14))
	var foot := CylinderMesh.new()
	foot.top_radius = 0.28
	foot.bottom_radius = 0.34
	foot.height = 0.06
	_add(foot, hull, Vector3(0.0, -pylon_height + 0.03, -0.14))
	var foot_light := TorusMesh.new()
	foot_light.inner_radius = 0.3
	foot_light.outer_radius = 0.33
	_add(foot_light, _rim, Vector3(0.0, -pylon_height + 0.065, -0.14))

	var material := ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.set_shader_parameter("screen_texture", _viewport.get_texture())
	material.set_shader_parameter("has_picture", true)
	material.set_shader_parameter("brightness", 1.4)
	material.set_shader_parameter("scanlines", 300.0)
	var glass := QuadMesh.new()
	glass.size = screen_size
	_add(glass, material, Vector3.ZERO)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.75, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 3.5
	glow.light_specular = 0.0
	glow.position = Vector3(0, 0, 0.6)
	add_child(glow)


func _add(mesh: Mesh, material: Material, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
