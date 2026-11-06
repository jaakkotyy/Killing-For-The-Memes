extends GutTest
## The CRT curve shared by the screen shaders and the mouse mapping, and the zoom + input
## hand-off running inside a real preview room.

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


func test_zooming_in_hands_keyboard_and_mouse_to_the_editor() -> void:
	var room: Node3D = ROOM_SCENE.instantiate()
	room.set("preview_players", 3)
	room.set("demo_enabled", false)
	add_child_autofree(room)
	await wait_physics_frames(2)
	var station: MemeStation = _find_station(room)
	assert_not_null(station, "the local player gets a meme station")

	station.open(true)
	await wait_physics_frames(2)
	assert_true(station.zoom.is_zoomed_in())

	for letter: String in "HELLO":
		_press(KEY_A + (letter.unicode_at(0) - "A".unicode_at(0)), letter.unicode_at(0))
	assert_eq(station.editor.get_draft().top_text, "HELLO", "typing reaches the focused caption")

	watch_signals(station.editor)
	var done: Button = station.editor.find_child("DoneButton", true, false) as Button
	var target: Vector2 = done.get_global_rect().get_center()
	var window_point: Variant = _window_point_for(station.zoom, target)
	assert_not_null(window_point, "the Done button is reachable through the curve")
	_click(window_point)
	assert_signal_emitted(station.editor, "submitted", "clicking Done through the overlay submits")

	_press(KEY_ESCAPE, 0)
	assert_eq(station.zoom.state, CrtZoom.State.ZOOMING_OUT, "Escape zooms back out")


func _find_station(room: Node) -> MemeStation:
	for child: Node in room.get_children():
		if child is MemeStation:
			return child
	return null


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
