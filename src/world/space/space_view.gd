class_name SpaceView
extends Node3D
## A slow look into deep space for the 2D screens (title screen and lobby): the
## SpaceBackdrop and a camera that drifts very slowly between the two planets. Add it under
## a Control; the 3D world draws behind the UI.

## Where the camera starts looking (between the red planet and its moon).
const LOOK_AT: Vector3 = Vector3(14.0, 20.0, -200.0)
## How far the drift sways, in radians, and how long one sway takes.
const SWAY: Vector2 = Vector2(0.09, 0.035)
const SWAY_SECONDS: float = 70.0

var _camera: Camera3D
var _backdrop: SpaceBackdrop
var _time: float = 0.0
var _base: Basis


func _ready() -> void:
	_backdrop = SpaceBackdrop.new()
	_backdrop.name = "SpaceBackdrop"
	add_child(_backdrop)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.far = 1000.0
	add_child(_camera)
	_camera.look_at_from_position(Vector3.ZERO, LOOK_AT, Vector3.UP)
	_base = _camera.basis
	_camera.make_current()


func _process(delta: float) -> void:
	_time += delta
	var phase: float = TAU * _time / SWAY_SECONDS
	# A lazy figure of eight, like something turning on its own in zero gravity.
	_camera.basis = _base * Basis.from_euler(Vector3(sin(phase * 2.0) * SWAY.y, sin(phase) * SWAY.x, sin(phase * 0.5) * 0.02))


func get_backdrop() -> SpaceBackdrop:
	return _backdrop


func get_camera() -> Camera3D:
	return _camera
