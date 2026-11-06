class_name WallTv
extends Node3D
## The big wall-mounted TV where memes are judged. Its picture is a SubViewport (2D UI), so
## M5 can show the spotlighted meme by putting the meme renderer inside it.
##
## The origin is the centre of the screen; the screen faces +Z.

const SCREEN_SHADER: Shader = preload("res://src/world/crt/crt_screen.gdshader")

@export var screen_size: Vector2 = Vector2(1.6, 1.2)
@export var resolution: Vector2i = Vector2i(800, 600)

var _viewport: SubViewport
var _title: Label
var _subtitle: Label
var _caption_box: Control
var _meme: MemeRenderer


func _ready() -> void:
	_build_picture()
	_build_case()


## The 2D scene shown on the TV. Add Controls here (e.g. a meme renderer).
func get_picture_root() -> SubViewport:
	return _viewport


func show_caption(title: String, subtitle: String = "") -> void:
	_title.text = title
	_subtitle.text = subtitle
	_caption_box.visible = true
	_meme.visible = false


## Shows a meme full screen (the spotlight phase).
func show_meme(spec: MemeSpec) -> void:
	_meme.set_meme(spec)
	_meme.visible = true
	_caption_box.visible = false


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
	background.color = Color(0.05, 0.02, 0.03)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_viewport.add_child(box)
	_title = _label(64, Color(0.95, 0.25, 0.2))
	_subtitle = _label(30, Color(0.85, 0.8, 0.65))
	box.add_child(_title)
	box.add_child(_subtitle)
	_caption_box = box
	_meme = MemeRenderer.new()
	_meme.set_anchors_preset(Control.PRESET_FULL_RECT)
	_meme.visible = false
	_viewport.add_child(_meme)
	show_caption(tr("KILLING FOR\nTHE MEMES"), tr("Please remain seated."))


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_case() -> void:
	var case_material := StandardMaterial3D.new()
	case_material.albedo_color = Color(0.2, 0.15, 0.1)  # fake wood veneer
	case_material.roughness = 0.7
	var body := BoxMesh.new()
	body.size = Vector3(screen_size.x + 0.4, screen_size.y + 0.3, 0.7)
	_add(body, case_material, Vector3(0.0, -0.02, -0.36))
	var speaker := BoxMesh.new()
	speaker.size = Vector3(0.14, screen_size.y * 0.8, 0.02)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.08, 0.07, 0.06)
	cloth.roughness = 1.0
	_add(speaker, cloth, Vector3(screen_size.x / 2.0 + 0.11, -0.02, -0.005))
	_add(speaker, cloth, Vector3(-screen_size.x / 2.0 - 0.11, -0.02, -0.005))

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
	glow.light_color = Color(0.9, 0.5, 0.45)
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
