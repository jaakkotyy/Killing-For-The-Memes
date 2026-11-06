class_name MemeStation
extends Node
## The local player's meme-making setup: the MemeEditor lives in a SubViewport that is the
## picture on their own CRT, and CrtZoom moves the camera into it and back. Open it with E
## or by clicking the monitor from the seat view; Escape returns to the seat.

signal meme_submitted(spec: MemeSpec)
## True after zooming in, false after zooming back out.
signal open_changed(is_open: bool)

const EDITOR_SCENE: PackedScene = preload("res://src/meme/editor/meme_editor.tscn")
const EDITOR_RESOLUTION: Vector2i = Vector2i(800, 600)
const SEAT_FOV: float = 62.0

## Whether E / clicking the monitor opens the editor (only from the seat view).
var enabled: bool = true
var editor: MemeEditor
var zoom: CrtZoom

var _seat: Seat
var _camera: CameraRig
var _viewport: SubViewport


func setup(camera: CameraRig, seat: Seat) -> void:
	_camera = camera
	_seat = seat
	_viewport = SubViewport.new()
	_viewport.size = EDITOR_RESOLUTION
	_viewport.disable_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	editor = EDITOR_SCENE.instantiate()
	_viewport.add_child(editor)
	editor.submitted.connect(meme_submitted.emit)
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


func _on_zoomed_in() -> void:
	editor.focus_first_field()
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
	var screen: Transform3D = _seat.monitor.get_screen_transform()
	var half: Vector2 = _seat.monitor.get_screen_size() / 2.0
	var rect := Rect2(_camera.unproject_position(screen.origin), Vector2.ZERO)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point: Vector3 = screen * Vector3(corner.x * half.x, corner.y * half.y, 0.0)
		if _camera.is_position_behind(point):
			return Rect2()
		rect = rect.expand(_camera.unproject_position(point))
	return rect
