extends GutTest


func test_defaults() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray())
	assert_false(options.host)
	assert_eq(options.join_target, "")
	assert_eq(options.port, Protocol.DEFAULT_PORT)
	assert_eq(options.min_players, 0)


func test_parses_all_flags() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray([
		"--host", "--join=127.0.0.1:9000", "--name=Alice Smith", "--port=9000",
		"--auto-ready", "--auto-start", "--min-players=2", "--smoke-test",
	]))
	assert_true(options.host)
	assert_eq(options.join_target, "127.0.0.1:9000")
	assert_eq(options.player_name, "Alice Smith")
	assert_eq(options.port, 9000)
	assert_true(options.auto_ready)
	assert_true(options.auto_start)
	assert_eq(options.min_players, 2)
	assert_true(options.smoke_test)


func test_ignores_unknown_and_invalid_values() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray([
		"--position", "0,0", "--port=abc", "--min-players=99", "res://scene.tscn",
	]))
	assert_eq(options.port, Protocol.DEFAULT_PORT)
	assert_eq(options.min_players, Protocol.MAX_PLAYERS, "clamped to the maximum")


func test_room_preview_flags() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--room-preview=6", "--room-camera=tv"]))
	assert_eq(options.room_preview, 6)
	assert_eq(options.room_camera, "tv")


func test_room_preview_flags_are_validated() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--room-preview=40", "--room-camera=ceiling"]))
	assert_eq(options.room_preview, Protocol.MAX_PLAYERS, "clamped to the maximum")
	assert_eq(options.room_camera, "", "unknown views are ignored")
