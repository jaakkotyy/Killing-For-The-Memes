class_name CameraRig
extends Camera3D
## The room camera. Glides between poses (your seat, the wall TV, an overview) and, where
## allowed, lets the view drift toward the mouse so you can glance around without capturing
## the cursor. M4 adds the zoom into the CRT on top of `move_to()`.

## How far the view can drift toward the screen edges, in degrees.
@export var look_yaw_degrees: float = 32.0
@export var look_pitch_degrees: float = 18.0
## Higher is snappier.
@export var look_smoothing: float = 5.0

var _base: Transform3D
var _from: Transform3D
var _to: Transform3D
var _from_fov: float = 70.0
var _to_fov: float = 70.0
var _progress: float = 1.0
var _duration: float = 0.0
var _allow_look: bool = false
var _look: Vector2 = Vector2.ZERO


func _ready() -> void:
	_base = global_transform
	_to = _base
	_to_fov = fov


## Glides to `pose` (a camera transform looking down its -Z) over `duration` seconds.
func move_to(pose: Transform3D, field_of_view: float, duration: float, allow_look: bool) -> void:
	_from = _base
	_to = pose.orthonormalized()
	_from_fov = fov
	_to_fov = field_of_view
	_duration = maxf(duration, 0.0)
	_progress = 0.0 if _duration > 0.0 else 1.0
	_allow_look = allow_look
	if _progress >= 1.0:
		_base = _to
		fov = _to_fov


func is_moving() -> bool:
	return _progress < 1.0


## Only follow the mouse in a focused, interactive window: not while recording a movie
## (screenshots) and not when the cursor is resting over another window.
func _mouse_look_available() -> bool:
	return Engine.get_write_movie_path().is_empty() and DisplayServer.window_is_focused()


## Camera pose at `eye` looking at `target`.
static func pose_looking_at(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)


func _process(delta: float) -> void:
	if _progress < 1.0:
		_progress = minf(_progress + delta / _duration, 1.0)
		var t: float = ease(_progress, -2.2)  # ease in-out
		_base = _from.interpolate_with(_to, t)
		fov = lerpf(_from_fov, _to_fov, t)

	var target_look := Vector2.ZERO
	if _allow_look and _mouse_look_available():
		var viewport := get_viewport()
		var rect: Rect2 = viewport.get_visible_rect()
		var mouse: Vector2 = viewport.get_mouse_position()
		if rect.has_point(mouse):
			var centred: Vector2 = mouse / rect.size - Vector2(0.5, 0.5)
			target_look = centred * 2.0
	_look = _look.lerp(target_look, clampf(delta * look_smoothing, 0.0, 1.0))
	var yaw: float = -deg_to_rad(look_yaw_degrees) * _look.x
	var pitch: float = -deg_to_rad(look_pitch_degrees) * _look.y
	var turned: Basis = Basis(Vector3.UP, yaw) * _base.basis * Basis(Vector3.RIGHT, pitch)
	global_transform = Transform3D(turned, _base.origin)
