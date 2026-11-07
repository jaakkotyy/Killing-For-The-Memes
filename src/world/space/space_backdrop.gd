class_name SpaceBackdrop
extends Node3D
## Deep space around whatever scene adds it: the starfield sky (space_sky.gdshader), a
## distant sun (a directional light whose glow is drawn in the sky), and the artist's two
## planets from planets.blend (assets/models/planets/, built by tools/build_models.ps1),
## turning slowly. The room, the title screen and the lobby all use it, so the game
## looks like one place.
##
## Planet sizes and places are in metres from the origin. They are far enough away that
## the camera's small moves around the table don't make them shift (no visible parallax).

const SKY_SHADER: Shader = preload("res://src/world/space/space_sky.gdshader")
const PLANET_SHADER: Shader = preload("res://src/world/space/planet.gdshader")
const PLANET_INFO_PATH: String = "res://assets/models/planets/planets.json"
## Where the sun is (towards it); planets' lit sides and the sky's sun glow agree on it.
const SUN_DIRECTION: Vector3 = Vector3(0.62, 0.38, 0.69)
const SUN_COLOR: Color = Color(1.0, 0.88, 0.76)
## Blender's rim emission strength in the source materials.
const RIM_ENERGY: float = 5.0

## name -> {scene, texture, position, radius, spin (radians per second), tilt}
const PLANETS: Dictionary = {
	"planet_red": {
		"scene": preload("res://assets/models/planets/planet_red.glb"),
		"texture": preload("res://assets/models/planets/planet_red_albedo.png"),
		"position": Vector3(-95.0, 34.0, -230.0),
		"radius": 62.0,
		"spin": 0.004,
		"tilt": 0.35,
	},
	"planet_moon": {
		"scene": preload("res://assets/models/planets/planet_moon.glb"),
		"texture": preload("res://assets/models/planets/planet_moon_albedo.png"),
		"position": Vector3(70.0, 22.0, -120.0),
		"radius": 9.0,
		"spin": 0.012,
		"tilt": -0.2,
	},
}

## Sun light strength; the room turns it down a little so the table lamp still matters.
@export var sun_energy: float = 1.1
## Set before adding it: whether to add the WorldEnvironment (the room adds its own
## effects on top, so it asks for a copy with environment()).
@export var add_environment: bool = true

var _planets: Dictionary = {}  # name -> Node3D
var _sun: DirectionalLight3D


func _ready() -> void:
	if add_environment:
		var world := WorldEnvironment.new()
		world.environment = environment()
		add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = SUN_COLOR
	_sun.light_energy = sun_energy
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 30.0
	add_child(_sun)
	# A directional light shines along its -Z; point that away from the sun.
	_sun.look_at_from_position(Vector3.ZERO, -SUN_DIRECTION, Vector3.UP)
	var rims: Dictionary = _rim_colors()
	for planet_name: String in PLANETS:
		_planets[planet_name] = _add_planet(planet_name, PLANETS[planet_name], rims.get(planet_name, Color.WHITE))


func _process(delta: float) -> void:
	for planet_name: String in _planets:
		(_planets[planet_name] as Node3D).rotate_object_local(Vector3.UP, float(PLANETS[planet_name]["spin"]) * delta)


## The planet node [param planet_name] ("planet_red" or "planet_moon"), for tests and framing.
func get_planet(planet_name: String) -> Node3D:
	return _planets.get(planet_name) as Node3D


func get_sun() -> DirectionalLight3D:
	return _sun


## A fresh space environment: the starfield sky, cool dim ambient light from it, filmic
## tone mapping and a soft glow so the planets' rims and the screens bloom.
static func environment() -> Environment:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("sun_direction", SUN_DIRECTION)
	sky_material.set_shader_parameter("sun_color", SUN_COLOR)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.6)
	env.ambient_light_energy = 0.28
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.06
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.06
	return env


func _add_planet(planet_name: String, info: Dictionary, rim: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = planet_name
	pivot.position = info["position"]
	pivot.rotation = Vector3(float(info["tilt"]), 0.0, float(info["tilt"]) * 0.5)
	var radius: float = info["radius"]
	pivot.scale = Vector3.ONE * radius
	add_child(pivot)
	var model: Node3D = (info["scene"] as PackedScene).instantiate()
	pivot.add_child(model)
	var material := ShaderMaterial.new()
	material.shader = PLANET_SHADER
	material.set_shader_parameter("albedo_texture", info["texture"])
	material.set_shader_parameter("rim_color", rim)
	material.set_shader_parameter("rim_energy", RIM_ENERGY)
	material.set_shader_parameter("sun_direction", SUN_DIRECTION)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		# Far away and huge: their shadows would only cost time.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pivot


## The rim colours build_planets.py read from the source materials.
static func _rim_colors() -> Dictionary:
	var colors: Dictionary = {}
	var file := FileAccess.open(PLANET_INFO_PATH, FileAccess.READ)
	if file == null:
		return colors
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return colors
	var rims: Variant = (json.data as Dictionary).get("rim", {})
	if rims is Dictionary:
		for key: Variant in rims:
			var value: Variant = rims[key]
			if value is Array and (value as Array).size() >= 3:
				colors[str(key)] = Color(float(value[0]), float(value[1]), float(value[2]))
	return colors
