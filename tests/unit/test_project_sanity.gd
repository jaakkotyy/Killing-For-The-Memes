extends GutTest
## Smoke tests proving the test runner and project configuration work.


func test_project_has_version() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	assert_ne(version, "", "application/config/version must be set")


func test_main_scene_exists() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_true(ResourceLoader.exists(main_scene), "main scene should exist: %s" % main_scene)
