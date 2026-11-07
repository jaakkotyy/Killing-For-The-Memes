class_name CrtStation
extends Node
## The local player's CRT setup: a 2D screen (a Control) lives in a SubViewport that is the
## picture on their own monitor, and CrtZoom moves the camera into it and back. Open it
## with E or by clicking the monitor from the seat view; Escape returns to the seat.
## MemeStation puts the meme editor on it, SearchStation guess mode's database terminal.

## True after zooming in, false after zooming back out.
signal open_changed(is_open: bool)

const SCREEN_RESOLUTION: Vector2i = Vector2i(800, 600)
const SEAT_FOV: float = 62.0

## Whether E / clicking the monitor opens the screen (only from the seat view).
var enabled: bool = true
var zoom: CrtZoom
## What the monitor shows.
var screen: Control

var _seat: Seat
var _camera: CameraRig
var _viewport: SubViewport


## Puts [param p_screen] on [param seat]'s monitor.
func setup_screen(camera: CameraRig, seat: Seat, p_screen: Control) -> void:
	_camera = camera
	_seat = seat
	screen = p_screen
	_viewport = SubViewport.new()
	_viewport.size = SCREEN_RESOLUTION
	_viewport.disable_3d = true
	_viewport.handle_input_locally = true
	# Tooltips and popups must stay on the CRT, not open as windows of their own.
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(screen)
	seat.monitor.set_picture(_viewport.get_texture())

	zoom = CrtZoom.new()
	add_child(zoom)
	zoom.setup(camera, seat.monitor, _viewport)
	zoom.exit_requested.connect(close)
	zoom.zoomed_in.connect(_on_zoomed_in)
	zoom.zoomed_out.connect(open_changed.emit.bind(false))


func is_open() -> bool:
	return zoom.is_busy()


func open(instant: bool = false) -> void:
	zoom.zoom_in(instant)


func close(instant: bool = false) -> void:
	zoom.zoom_out(_seat.get_eye_pose(), SEAT_FOV, instant)


## Called once the screen fills the view; give the keyboard to its first field.
func _focus_screen() -> void:
	pass


func _on_zoomed_in() -> void:
	_focus_screen()
	open_changed.emit(true)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or zoom.is_busy():
		return
	var wants_open: bool = false
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		wants_open = (event as InputEventKey).keycode == KEY_E
	elif event is InputEventMouseButton and event.is_pressed():
		var click := event as InputEventMouseButton
		wants_open = click.button_index == MOUSE_BUTTON_LEFT and _screen_rect_on_window().has_point(click.position)
	if wants_open:
		get_viewport().set_input_as_handled()
		open()


## The monitor's glass as a window-space rectangle, for click detection without physics.
func _screen_rect_on_window() -> Rect2:
	var glass: Transform3D = _seat.monitor.get_screen_transform()
	var half: Vector2 = _seat.monitor.get_screen_size() / 2.0
	var rect := Rect2(_camera.unproject_position(glass.origin), Vector2.ZERO)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point: Vector3 = glass * Vector3(corner.x * half.x, corner.y * half.y, 0.0)
		if _camera.is_position_behind(point):
			return Rect2()
		rect = rect.expand(_camera.unproject_position(point))
	return rect
