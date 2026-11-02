extends Control
## Lobby: lists players, lets guests ready up and lets the host start.
## Purely a view over Session.lobby; every action goes through Session.

const _READY_COLOR: Color = Color(0.45, 0.85, 0.45)
const _WAITING_COLOR: Color = Color(0.65, 0.6, 0.55)
const _HOST_COLOR: Color = Color(0.95, 0.75, 0.35)

@onready var _join_info_label: Label = %JoinInfoLabel
@onready var _copy_code_button: Button = %CopyCodeButton
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _status_label: Label = %StatusLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton

var _join_code: String = ""


func _ready() -> void:
	Session.lobby_updated.connect(_refresh)
	_ready_button.toggled.connect(Session.set_ready)
	_start_button.pressed.connect(Session.request_start)
	_leave_button.pressed.connect(Session.leave)
	_copy_code_button.pressed.connect(_on_copy_code_pressed)

	_ready_button.visible = not Session.is_host()
	_start_button.visible = Session.is_host()
	_setup_join_info()
	_refresh(Session.lobby)


func _setup_join_info() -> void:
	_copy_code_button.visible = false
	if not Session.is_host():
		_join_info_label.text = "The host starts the game once everyone is ready."
		return

	var info: Dictionary = Net.transport.get_join_info()
	var port: int = int(info.get("port", Protocol.DEFAULT_PORT))
	var addresses: Array = info.get("addresses", [])
	if addresses.is_empty():
		_join_info_label.text = "No network address found. Friends can join with your public IP if UDP port %d is forwarded." % port
		return

	var lines: PackedStringArray = ["Friends join with one of these (UDP port %d):" % port]
	for entry: Dictionary in addresses:
		lines.append("    %s    code  %s" % [entry["address"], entry["code"]])
	_join_info_label.text = "\n".join(lines)
	_join_code = str(addresses[0]["code"])
	_copy_code_button.text = "Copy code %s" % _join_code
	_copy_code_button.visible = true


func _refresh(lobby: LobbyState) -> void:
	for child: Node in _player_list.get_children():
		child.queue_free()
	for player: LobbyPlayer in lobby.get_players():
		_player_list.add_child(_make_player_row(player))

	var local: LobbyPlayer = Session.get_local_player()
	if local != null:
		_ready_button.set_pressed_no_signal(local.ready)
		_ready_button.text = "Ready!" if local.ready else "Ready up"

	_start_button.disabled = not lobby.can_start(Session.min_players)
	_status_label.text = _status_text(lobby)


func _make_player_row(player: LobbyPlayer) -> Label:
	var row := Label.new()
	var is_host: bool = player.id == LobbyState.HOST_ID
	var tags: PackedStringArray = []
	if is_host:
		tags.append("host")
	if player.id == Session.local_peer_id():
		tags.append("you")
	var suffix: String = "  (%s)" % ", ".join(tags) if not tags.is_empty() else ""
	var state: String = "HOST" if is_host else ("READY" if player.ready else "not ready")
	row.text = "Seat %d   %s%s   —   %s" % [player.seat + 1, player.name, suffix, state]
	var color: Color = _HOST_COLOR if is_host else (_READY_COLOR if player.ready else _WAITING_COLOR)
	row.add_theme_color_override("font_color", color)
	return row


func _status_text(lobby: LobbyState) -> String:
	if lobby.player_count() < Session.min_players:
		return "Waiting for players... (%d / %d minimum, %d max)" % [lobby.player_count(), Session.min_players, lobby.max_players]
	if not lobby.all_guests_ready():
		return "Waiting for everyone to ready up..."
	return "Everyone is ready. Start when you like!" if Session.is_host() else "Everyone is ready. Waiting for the host..."


func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(_join_code)
	_copy_code_button.text = "Copied!"
