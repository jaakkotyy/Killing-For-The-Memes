class_name MemeStation
extends CrtStation
## The meme game's CRT: the MemeEditor on the local player's monitor.

signal meme_submitted(spec: MemeSpec)

const EDITOR_SCENE: PackedScene = preload("res://src/meme/editor/meme_editor.tscn")

var editor: MemeEditor


func setup(camera: CameraRig, seat: Seat) -> void:
	editor = EDITOR_SCENE.instantiate()
	editor.submitted.connect(meme_submitted.emit)
	setup_screen(camera, seat, editor)


func _focus_screen() -> void:
	editor.focus_first_field()
