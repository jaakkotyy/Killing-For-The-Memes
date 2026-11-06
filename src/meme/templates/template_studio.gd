extends Node
## Dev tool: stages shots in the game's own room and saves them as meme templates
## (assets/meme_templates/<id>.jpg). Everything in them is original game art, so the
## templates need no third-party licences. Run with tools/capture_templates.ps1; the window
## must be visible (headless has no renderer).

const ROOM_SCENE: PackedScene = preload("res://src/world/room/room.tscn")
const OUTPUT_SIZE: Vector2i = Vector2i(800, 600)
## Frames to let fog, SSAO and animations settle before each capture.
const SETTLE_FRAMES: int = 24
const PLAYERS: int = 6

var _room: Node3D
var _camera: Camera3D


func _ready() -> void:
	_room = ROOM_SCENE.instantiate()
	_room.set("preview_players", PLAYERS)
	_room.set("demo_enabled", false)
	add_child(_room)
	_room.call("set_hud_visible", false)
	_camera = Camera3D.new()
	_camera.near = 0.03
	add_child(_camera)
	_camera.make_current()
	_capture_all.call_deferred()


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MemeTemplateLibrary.IMAGE_DIR))
	for id: String in MemeTemplateLibrary.get_default().ids():
		_reset()
		if not has_method("_shot_" + id):
			push_error("No studio shot for template '%s'" % id)
			continue
		call("_shot_" + id)
		for i: int in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_save(id)
	get_tree().quit()


func _save(id: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	# Centre-crop to 4:3, then scale down (doubles as antialiasing).
	var target_aspect: float = float(OUTPUT_SIZE.x) / float(OUTPUT_SIZE.y)
	var width: int = mini(image.get_width(), roundi(image.get_height() * target_aspect))
	var height: int = roundi(width / target_aspect)
	image = image.get_region(Rect2i((image.get_width() - width) / 2, (image.get_height() - height) / 2, width, height))
	image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path: String = ProjectSettings.globalize_path(MemeTemplateLibrary.image_path(id))
	var error: Error = image.save_jpg(path, 0.9)
	print("TEMPLATE %s -> %s (%s)" % [id, path, error_string(error)])


func _reset() -> void:
	_room.call("focus_spotlight", 0)
	_host().set_expression(&"grin")
	for id: int in range(1, PLAYERS + 1):
		var seat: Seat = _seat(id)
		seat.avatar.visible = true
		seat.monitor.visible = true
		seat.avatar.set_label_visible(false)
		seat.avatar.idle()


func _seat(id: int) -> Seat:
	return _room.call("get_seat", id) as Seat


func _host() -> TheHost:
	return _room.call("get_host") as TheHost


func _look(eye: Vector3, target: Vector3, fov: float) -> void:
	_camera.global_transform = CameraRig.pose_looking_at(eye, target)
	_camera.fov = fov


func _host_forward() -> Vector3:
	return _host().global_basis.z.normalized()


# --- Shots (one per template id in data/meme_templates.json) ----------------------------

func _shot_host_grin() -> void:
	var head: Vector3 = _host().get_head_position() + Vector3.UP * 0.2
	_look(head + _host_forward() * 0.95 + Vector3.UP * 0.05, head, 38.0)


func _shot_host_sinister() -> void:
	_host().set_expression(&"sinister")
	var head: Vector3 = _host().get_head_position() + Vector3.UP * 0.2
	var side: Vector3 = _host_forward().cross(Vector3.UP).normalized()
	_look(head + _host_forward() * 1.1 + side * 0.35 + Vector3.DOWN * 0.75, head, 42.0)


func _shot_host_shocked() -> void:
	_host().set_expression(&"surprised")
	var head: Vector3 = _host().get_head_position() + Vector3.UP * 0.2
	var side: Vector3 = _host_forward().cross(Vector3.UP).normalized()
	_look(head + _host_forward() * 0.8 - side * 0.3, head, 46.0)


func _shot_spotlight_flinch() -> void:
	var seat: Seat = _seat(3)
	_room.call("focus_spotlight", 3)
	seat.avatar.hold_pose(PlayerAvatar.ANIM_FLINCH, 0.25)
	seat.monitor.visible = false  # it would hide the player from this angle
	var chest: Vector3 = seat.to_global(Vector3(0, 1.05, -0.05))
	_look(seat.to_global(Vector3(0.15, 1.2, 1.35)), chest, 40.0)


func _shot_staring_at_tv() -> void:
	var seat: Seat = _seat(4)
	seat.avatar.hold_pose(PlayerAvatar.ANIM_LOOK_UP, 0.4)
	var tv: Vector3 = (_room.call("get_tv") as Node3D).global_position
	_look(seat.to_global(Vector3(0.3, 1.55, -0.75)), tv, 50.0)


func _shot_empty_chair() -> void:
	var seat: Seat = _seat(2)
	seat.avatar.visible = false
	seat.monitor.visible = false
	_room.call("focus_spotlight", 2)
	_look(seat.to_global(Vector3(-0.2, 1.3, 1.6)), seat.to_global(Vector3(0, 0.6, -0.1)), 42.0)


func _shot_crt_static() -> void:
	var seat: Seat = _seat(5)
	_look(seat.to_global(Vector3(0.0, 1.38, -0.12)), seat.to_global(Vector3(0, 0.85, 0.9)), 52.0)


func _shot_whole_table() -> void:
	_look(Vector3(0.0, 3.1, 3.4), Vector3(0.0, 0.6, -0.4), 58.0)
