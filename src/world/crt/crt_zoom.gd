class_name CrtZoom
extends CanvasLayer
## The signature 2D/3D transition: the camera glides in until a CRT's screen fills the view,
## then the screen's SubViewport is shown fullscreen (with the same CRT curve) and receives
## real input. Zooming out reverses it. The picture is the same texture throughout, so
## nothing pops.
##
## While zoomed in, every input event except Escape is forwarded to the SubViewport.

signal zoomed_in
signal zoomed_out
## Escape was pressed while zoomed in; the owner decides where the camera goes.
signal exit_requested

enum State { OUT, ZOOMING_IN, IN, ZOOMING_OUT }

## How much of the window's height (or width) the screen fills at the end of the zoom.
const FILL: float = 0.92
const ZOOM_FOV: float = 50.0
const ZOOM_SECONDS: float = 0.75
const FADE_SECONDS: float = 0.12
const SCREEN_ASPECT: float = 4.0 / 3.0
const OVERLAY_SHADER: Shader = preload("res://src/world/crt/crt_overlay.gdshader")

var state: State = State.OUT

var _camera: CameraRig
var _monitor: CrtMonitor
var _viewport: SubViewport
var _overlay: TextureRect


func setup(camera: CameraRig, monitor: CrtMonitor, viewport: SubViewport) -> void:
	_camera = camera
	_monitor = monitor
	_viewport = viewport
	layer = 5
	_overlay = TextureRect.new()
	_overlay.texture = viewport.get_texture()
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	var material := ShaderMaterial.new()
	material.shader = OVERLAY_SHADER
	material.set_shader_parameter("curvature", CrtMonitor.CURVATURE)
	_overlay.material = material
	add_child(_overlay)
	get_viewport().size_changed.connect(_layout_overlay)
	_layout_overlay()


func is_zoomed_in() -> bool:
	return state == State.IN


func is_busy() -> bool:
	return state != State.OUT


func zoom_in(instant: bool = false) -> void:
	if state == State.IN or state == State.ZOOMING_IN:
		return
	state = State.ZOOMING_IN
	var duration: float = 0.0 if instant else ZOOM_SECONDS
	_camera.move_to(zoom_pose(), ZOOM_FOV, duration, false)
	_after(duration, _finish_zoom_in)


## Glides back to `pose` (usually the seat view).
func zoom_out(pose: Transform3D, field_of_view: float, instant: bool = false) -> void:
	if state == State.OUT or state == State.ZOOMING_OUT:
		return
	state = State.ZOOMING_OUT
	_overlay.visible = false
	_viewport.gui_release_focus()
	_viewport.notification(Node.NOTIFICATION_VP_MOUSE_EXIT)
	var duration: float = 0.0 if instant else ZOOM_SECONDS
	_camera.move_to(pose, field_of_view, duration, true)
	_after(duration, _finish_zoom_out)


## Camera pose straight in front of the screen at the distance where it fills FILL of the
## view, matching the overlay rect exactly.
func zoom_pose() -> Transform3D:
	var screen: Transform3D = _monitor.get_screen_transform()
	var normal: Vector3 = screen.basis.z.normalized()
	var screen_size: Vector2 = _monitor.get_screen_size()
	var window: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = window.x / maxf(window.y, 1.0)
	var tan_half: float = tan(deg_to_rad(ZOOM_FOV) / 2.0)
	var distance: float
	if aspect >= SCREEN_ASPECT:
		distance = (screen_size.y / 2.0) / (FILL * tan_half)
	else:
		distance = (screen_size.x / 2.0) / (FILL * tan_half * aspect)
	return CameraRig.pose_looking_at(screen.origin + normal * distance, screen.origin)


## The overlay's rect in window pixels (centred 4:3, FILL of the limiting dimension).
func overlay_rect() -> Rect2:
	var window: Vector2 = get_viewport().get_visible_rect().size
	var height: float = minf(window.y, window.x / SCREEN_ASPECT) * FILL
	var picture := Vector2(height * SCREEN_ASPECT, height)
	return Rect2((window - picture) / 2.0, picture)


## Window position -> SubViewport position through the CRT curve; null when off the picture.
func window_to_screen(position: Vector2) -> Variant:
	var rect: Rect2 = overlay_rect()
	var uv: Vector2 = CrtMonitor.curve_uv((position - rect.position) / rect.size)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return null
	return uv * Vector2(_viewport.size)


func _input(event: InputEvent) -> void:
	if state == State.ZOOMING_IN or state == State.ZOOMING_OUT:
		get_viewport().set_input_as_handled()  # nothing leaks into the room mid-zoom
		return
	if state != State.IN:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		exit_requested.emit()
		return
	if event is InputEventMouse:
		var mouse := event.duplicate() as InputEventMouse
		var mapped: Variant = window_to_screen(mouse.position)
		if mapped == null:
			return
		mouse.position = mapped
		mouse.global_position = mapped
		_viewport.push_input(mouse, true)
	else:
		_viewport.push_input(event, true)


func _finish_zoom_in() -> void:
	if state != State.ZOOMING_IN:
		return
	state = State.IN
	# A SubViewport outside a SubViewportContainer ignores mouse input until told the
	# mouse is over it (the container normally sends this).
	_viewport.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	_layout_overlay()
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, FADE_SECONDS)
	zoomed_in.emit()


func _finish_zoom_out() -> void:
	if state != State.ZOOMING_OUT:
		return
	state = State.OUT
	zoomed_out.emit()


func _layout_overlay() -> void:
	if _overlay == null:
		return
	var rect: Rect2 = overlay_rect()
	_overlay.position = rect.position
	_overlay.size = rect.size
	if state == State.IN:
		# The window changed shape: keep the 3D screen behind the overlay lined up.
		_camera.move_to(zoom_pose(), ZOOM_FOV, 0.0, false)


func _after(seconds: float, callback: Callable) -> void:
	if seconds <= 0.0:
		callback.call()
		return
	get_tree().create_timer(seconds).timeout.connect(callback)
