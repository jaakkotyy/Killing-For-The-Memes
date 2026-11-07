extends GutTest
## The space scenery: SpaceBackdrop's planets, sun and sky, and the drifting SpaceView
## behind the title screen and the lobby.


func test_backdrop_has_both_planets_and_a_sun() -> void:
	var backdrop := SpaceBackdrop.new()
	add_child_autofree(backdrop)
	for planet_name: String in ["planet_red", "planet_moon"]:
		var planet: Node3D = backdrop.get_planet(planet_name)
		assert_not_null(planet, planet_name)
		assert_false(planet.find_children("*", "MeshInstance3D", true, false).is_empty(), "%s has its mesh" % planet_name)
	assert_not_null(backdrop.get_sun())
	assert_true(backdrop.get_sun().shadow_enabled)


func test_planets_turn_slowly() -> void:
	var backdrop := SpaceBackdrop.new()
	add_child_autofree(backdrop)
	var planet: Node3D = backdrop.get_planet("planet_red")
	var before: Basis = planet.basis
	await wait_physics_frames(3)
	assert_ne(planet.basis, before)


func test_rim_colours_come_from_the_blender_export() -> void:
	var rims: Dictionary = SpaceBackdrop._rim_colors()
	assert_true(rims.has("planet_red"))
	assert_true(rims.has("planet_moon"))
	assert_gt((rims["planet_red"] as Color).r, (rims["planet_red"] as Color).b, "the red planet glows red")


func test_environment_is_a_starfield_sky() -> void:
	var env: Environment = SpaceBackdrop.environment()
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.sky.sky_material is ShaderMaterial)
	assert_true(env.glow_enabled)


func test_space_view_owns_the_camera_and_drifts() -> void:
	var view := SpaceView.new()
	add_child_autofree(view)
	await wait_physics_frames(1)
	assert_true(view.get_camera().current)
	var before: Basis = view.get_camera().basis
	await wait_seconds(0.3)
	assert_ne(view.get_camera().basis, before)
	assert_not_null(view.get_backdrop())
