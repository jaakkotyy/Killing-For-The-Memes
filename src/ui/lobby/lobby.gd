extends Control
## Lobby: lists players, lets guests ready up and lets the host pick the database (the
## identity pack) and start.
## Purely a view over Session.lobby; every action goes through Session.
##
## The host's own identity packs ("Our friends") live in IdentityPack.USER_DIR; "Your packs
## folder" opens it (with an example pack to copy the first time), and the list reloads
## when the window gets the focus back.

const _READY_COLOR: Color = Color(0.5, 0.95, 0.75)
const _WAITING_COLOR: Color = Color(0.55, 0.6, 0.7)
const _HOST_COLOR: Color = Color(0.7, 0.88, 1.0)
const _EXAMPLE_PACK: String = "res://data/identity_examples/friends.json"

@onready var _join_info_label: Label = %JoinInfoLabel
@onready var _copy_code_button: Button = %CopyCodeButton
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _status_label: Label = %StatusLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _pack_option: OptionButton = %PackOption
@onready var _mode_label: Label = %ModeLabel
@onready var _packs_button: Button = %PacksButton

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
	_setup_pack_picker()
	_refresh(Session.lobby)


## The host picks from a dropdown; guests only see what was picked.
func _setup_pack_picker() -> void:
	var host: bool = Session.is_host()
	_pack_option.visible = host
	_packs_button.visible = host
	_mode_label.visible = not host
	if not host:
		return
	_reload_packs()
	_pack_option.item_selected.connect(func(_index: int) -> void: _send_pack())
	_packs_button.pressed.connect(_open_packs_folder)


## Fills the pack list; custom packs are marked as yours.
func _reload_packs() -> void:
	_pack_ids = IdentityPack.available_ids()
	_pack_option.clear()
	for pack_id: String in _pack_ids:
		var label: String = IdentityPack.display_name(pack_id)
		if not IdentityPack.is_shipped(pack_id):
			label += "  (yours)"
		_pack_option.add_item(label)
	var index: int = _pack_ids.find(Session.lobby.pack)
	if index >= 0:
		_pack_option.select(index)


## Opens the custom packs folder, putting the example pack there if it has none yet.
func _open_packs_folder() -> void:
	DirAccess.make_dir_recursive_absolute(IdentityPack.USER_DIR)
	if IdentityPack.custom_ids().is_empty():
		var example: String = FileAccess.get_file_as_string(_EXAMPLE_PACK)
		var file := FileAccess.open(IdentityPack.USER_DIR + "example_friends.json", FileAccess.WRITE)
		if file != null and not example.is_empty():
			file.store_string(example)
		file = null
		_reload_packs()
	OS.shell_open(ProjectSettings.globalize_path(IdentityPack.USER_DIR))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready() and Session.is_host():
		_reload_packs()


func _send_pack() -> void:
	if _pack_option.selected >= 0 and _pack_option.selected < _pack_ids.size():
		Session.set_pack(_pack_ids[_pack_option.selected])


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
	_show_pack(lobby)
	_status_label.text = _status_text(lobby)


func _show_pack(lobby: LobbyState) -> void:
	_mode_label.text = IdentityPack.display_name(lobby.pack)
	if Session.is_host():
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
