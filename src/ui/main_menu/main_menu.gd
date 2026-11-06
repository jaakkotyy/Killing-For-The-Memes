extends Control
## Main menu: choose a name, then host a game or join one by IP / join code.
## Hands off to Session; App switches to the lobby once we are in.

const _ERROR_COLOR: Color = Color(0.95, 0.4, 0.35)
const _INFO_COLOR: Color = Color(0.75, 0.7, 0.62)

@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_button: Button = %HostButton
@onready var _port_spin: SpinBox = %PortSpin
@onready var _join_edit: LineEdit = %JoinEdit
@onready var _join_button: Button = %JoinButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	_name_edit.max_length = LobbyState.NAME_MAX_LENGTH
	_name_edit.text = Settings.player_name if not Settings.player_name.is_empty() else Platform.service.get_player_name()
	_port_spin.value = Settings.host_port
	_join_edit.text = Settings.last_join_target

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_join_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_quit_button.pressed.connect(func() -> void: get_tree().quit())

	var message: String = App.consume_message()
	_show_status(message, _ERROR_COLOR)
	_host_button.grab_focus()


func _on_host_pressed() -> void:
	var player_name: String = _commit_name()
	Settings.host_port = int(_port_spin.value)
	Settings.save_settings()
	_set_busy("Opening the room on port %d..." % Settings.host_port)
	Session.host_game(player_name, Settings.host_port)


func _on_join_pressed() -> void:
	var target: String = _join_edit.text.strip_edges()
	if JoinCode.parse_target(target).is_empty():
		_show_status("Enter the host's IP address, IP:port or join code.", _ERROR_COLOR)
		return
	var player_name: String = _commit_name()
	Settings.last_join_target = target
	Settings.save_settings()
	_set_busy("Connecting to %s..." % target)
	Session.join_game(target, player_name)


## Sanitizes and saves the typed name, and returns it.
func _commit_name() -> String:
	var player_name: String = LobbyState.sanitize_name(_name_edit.text)
	_name_edit.text = player_name
	Settings.player_name = player_name
	return player_name


func _set_busy(text: String) -> void:
	for button: Button in [_host_button, _join_button]:
		button.disabled = true
	_show_status(text, _INFO_COLOR)


func _show_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
