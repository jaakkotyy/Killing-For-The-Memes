class_name CrtMonitor
extends Node3D
## A chunky old CRT monitor (greybox). Its screen is a quad with `crt_screen.gdshader`;
## M4 feeds the meme editor's SubViewport into it with `set_picture()`.
##
## The origin is the bottom centre of the case; the screen faces +Z.

const SCREEN_SHADER: Shader = preload("res://src/world/crt/crt_screen.gdshader")
## Barrel distortion of the glass; shared by the 3D screen, the zoom overlay and the
## mouse mapping, so all three agree on where a pixel is.
const CURVATURE: float = 0.18

@export var case_size: Vector3 = Vector3(0.46, 0.40, 0.42)
@export var screen_size: Vector2 = Vector2(0.36, 0.27)
@export var case_color: Color = Color(0.55, 0.52, 0.45)
@export var glow_color: Color = Color(0.35, 0.95, 0.7)
## Casts a little light on whoever sits in front of it. Off for distant screens.
@export var cast_glow: bool = true

var _screen_material: ShaderMaterial


func _ready() -> void:
	_build()


## Shows a texture (e.g. a SubViewport's) on the screen, or idle static when null.
func set_picture(texture: Texture2D) -> void:
	_screen_material.set_shader_parameter("screen_texture", texture)
	_screen_material.set_shader_parameter("has_picture", texture != null)


## World-space centre of the glass, for camera poses that look at the screen.
func get_screen_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, _screen_center())


func get_screen_size() -> Vector2:
	return screen_size


## Where a point on the glass (0..1, top-left origin) samples the picture: the same barrel
## curve as the shaders. Results outside 0..1 are off the picture (the black rim).
static func curve_uv(uv: Vector2, curvature: float = CURVATURE) -> Vector2:
	var centred: Vector2 = uv * 2.0 - Vector2.ONE
	centred *= 1.0 + curvature * centred.length_squared() * 0.25
	return centred * 0.5 + Vector2(0.5, 0.5)


func _screen_center() -> Vector3:
	return Vector3(0.0, case_size.y * 0.55, case_size.z / 2.0 + 0.003)


func _build() -> void:
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = case_color
	plastic.roughness = 0.65

	# Case: a front box plus a tapered back (the tube), like real CRTs.
	var front := BoxMesh.new()
	front.size = Vector3(case_size.x, case_size.y, case_size.z * 0.45)
	_add_mesh(front, plastic, Vector3(0.0, case_size.y / 2.0, case_size.z * 0.275))
	var back := BoxMesh.new()
	back.size = Vector3(case_size.x * 0.72, case_size.y * 0.78, case_size.z * 0.55)
	_add_mesh(back, plastic, Vector3(0.0, case_size.y * 0.45, -case_size.z * 0.2))

	var bezel_material := StandardMaterial3D.new()
	bezel_material.albedo_color = case_color.darkened(0.55)
	bezel_material.roughness = 0.8
	var bezel := BoxMesh.new()
	bezel.size = Vector3(screen_size.x + 0.03, screen_size.y + 0.03, 0.01)
	_add_mesh(bezel, bezel_material, _screen_center() - Vector3(0, 0, 0.009))

	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	_screen_material.set_shader_parameter("idle_tint", glow_color)
	_screen_material.set_shader_parameter("seed", randf() * 100.0)
	_screen_material.set_shader_parameter("curvature", CURVATURE)
	var glass := QuadMesh.new()
	glass.size = screen_size
	_add_mesh(glass, _screen_material, _screen_center())

	if cast_glow:
		var light := OmniLight3D.new()
		light.light_color = glow_color
		light.light_energy = 0.35
		light.omni_range = 1.1
		light.shadow_enabled = false
		light.light_specular = 0.0  # no hot spot reflected in our own glass
		light.position = _screen_center() + Vector3(0, 0, 0.25)
		add_child(light)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance
