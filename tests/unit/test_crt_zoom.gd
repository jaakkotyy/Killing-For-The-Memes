extends GutTest
## The CRT curve shared by the screen shaders and the mouse mapping, and the zoom + input
## hand-off running inside a real preview room (the search terminal on your CRT).

const ROOM_SCENE: PackedScene = preload("res://src/world/room/room.tscn")


func test_curve_keeps_the_centre() -> void:
	assert_eq(CrtMonitor.curve_uv(Vector2(0.5, 0.5)), Vector2(0.5, 0.5))


func test_curve_pushes_edges_outward() -> void:
	var edge: Vector2 = CrtMonitor.curve_uv(Vector2(1.0, 0.5))
	assert_gt(edge.x, 1.0, "the very edge of the glass is the black rim")
	assert_almost_eq(edge.y, 0.5, 0.0001)
	var inner: Vector2 = CrtMonitor.curve_uv(Vector2(0.75, 0.75))
	assert_gt(inner.x, 0.75)
	assert_lt(inner.x, 1.0, "points well inside stay on the picture")


func test_curve_is_monotonic_across_the_screen() -> void:
	var previous: float = -INF
	for i: int in 21:
		var x: float = CrtMonitor.curve_uv(Vector2(i / 20.0, 0.3)).x
		assert_gt(x, previous)
		previous = x


func test_zooming_in_hands_keyboard_and_mouse_to_the_terminal() -> void:
	PortraitCache.offline = true
	var room: GameRoom = ROOM_SCENE.instantiate()
	room.preview_players = 3
	add_child_autofree(room)
	await wait_physics_frames(2)
	var station: SearchStation = room.get_search_station()
	assert_not_null(station, "the local player gets the search terminal")

	station.open(true)
	await wait_physics_frames(2)
	assert_true(station.zoom.is_zoomed_in())

	for letter: String in "AB":
		_press(KEY_A + (letter.unicode_at(0) - "A".unicode_at(0)), letter.unicode_at(0) + 32)
	# The search box, or the question box when it is your turn to ask.
	var focused: LineEdit = station.terminal.get_viewport().gui_get_focus_owner() as LineEdit
	assert_not_null(focused, "zooming in focuses a text field")
	if focused != null:
		assert_eq(focused.text, "ab", "typing reaches the focused field")

	var guess: Button = station.terminal.find_child("GuessButton", true, false) as Button
	var target: Vector2 = guess.get_global_rect().get_center()
	assert_not_null(_window_point_for(station.zoom, target), "the GUESS button is reachable through the curve")

	_press(KEY_ESCAPE, 0)
	assert_eq(station.zoom.state, CrtZoom.State.ZOOMING_OUT, "Escape zooms back out")
	PortraitCache.offline = false


func _press(keycode: Key, unicode: int) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.unicode = unicode if pressed else 0
		key.pressed = pressed
		get_tree().root.push_input(key)


func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		# Already in root-viewport coordinates (what _input sees after stretching).
		get_tree().root.push_input(click, true)


## Searches the window for a point that the CRT curve maps onto `target` (editor pixels).
func _window_point_for(zoom: CrtZoom, target: Vector2) -> Variant:
	var rect: Rect2 = zoom.overlay_rect()
	var best: Variant = null
	var best_distance: float = 4.0
	for ix: int in 200:
		for iy: int in 150:
			var point: Vector2 = rect.position + rect.size * Vector2(ix / 199.0, iy / 149.0)
			var mapped: Variant = zoom.window_to_screen(point)
			if mapped != null and (mapped as Vector2).distance_to(target) < best_distance:
				best_distance = (mapped as Vector2).distance_to(target)
				best = point
	return best
