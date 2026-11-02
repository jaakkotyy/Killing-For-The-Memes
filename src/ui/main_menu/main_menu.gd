extends Control
## Main menu. M0 placeholder: shows the title and version and lets you quit.
## Host / Join flows are wired up in M1 (networking skeleton).

@onready var _version_label: Label = %VersionLabel
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_quit_pressed() -> void:
	get_tree().quit()
