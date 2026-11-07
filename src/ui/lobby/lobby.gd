extends Control
## Lobby: lists players, lets guests ready up and lets the host pick the game (mode and,
## for guess mode, the identity pack) and start.
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
@onready var _mode_option: OptionButton = %ModeOption
@onready var _pack_option: OptionButton = %PackOption
@onready var _mode_label: Label = %ModeLabel

var _join_code: String = ""
var _pack_ids: PackedStringArray = []


func _ready() -> void:
	Session.lobby_updated.connect(_refresh)
	_ready_button.toggled.connect(Session.set_ready)
	_start_button.pressed.connect(Session.request_start)
	_leave_button.pressed.connect(Session.leave)
	_copy_code_button.pressed.connect(_on_copy_code_pressed)

	_ready_button.visible = not Session.is_host()
	_start_button.visible = Session.is_host()
	_setup_join_info()
	_setup_mode_picker()
	_refresh(Session.lobby)


## The host picks with two dropdowns; guests only see what was picked.
func _setup_mode_picker() -> void:
	var host: bool = Session.is_host()
	_mode_option.visible = host
	_pack_option.visible = host
	_mode_label.visible = not host
	if not host:
		return
	for mode: String in GameMode.ALL:
		_mode_option.add_item(GameMode.label(mode))
	_pack_ids = IdentityPack.available_ids()
	for pack_id: String in _pack_ids:
		_pack_option.add_item(IdentityPack.display_name(pack_id))
	_mode_option.item_selected.connect(func(_index: int) -> void: _send_mode())
	_pack_option.item_selected.connect(func(_index: int) -> void: _send_mode())


func _send_mode() -> void:
	var mode: String = GameMode.ALL[maxi(0, _mode_option.selected)]
	var pack: String = _pack_ids[_pack_option.selected] if _pack_option.selected >= 0 and not _pack_ids.is_empty() else Session.lobby.pack
	Session.set_game_mode(mode, pack)


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
	_show_mode(lobby)
	_status_label.text = _status_text(lobby)


func _show_mode(lobby: LobbyState) -> void:
	var guess: bool = lobby.mode == GameMode.GUESS
	_mode_label.text = GameMode.label(lobby.mode) + ("  —  " + IdentityPack.display_name(lobby.pack) if guess else "")
	if Session.is_host():
		_mode_option.select(maxi(0, GameMode.ALL.find(lobby.mode)))
		_pack_option.visible = guess
		var pack_index: int = _pack_ids.find(lobby.pack)
		if pack_index >= 0:
			_pack_option.select(pack_index)


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
