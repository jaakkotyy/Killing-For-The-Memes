extends Node
## Top-level application flow (autoload "App").
##
## Applies launch options and switches between the top-level scenes
## (main menu → lobby → room → main menu) in response to Session events, so the scenes
## themselves stay unaware of each other.

const MAIN_MENU_SCENE: String = "res://src/ui/main_menu/main_menu.tscn"
const LOBBY_SCENE: String = "res://src/ui/lobby/lobby.tscn"
const ROOM_SCENE: String = "res://src/world/room/room.tscn"

const _SMOKE_TEST_TIMEOUT: float = 30.0
## Linger after the game starts so every instance in a smoke test sees the start.
const _SMOKE_TEST_LINGER: float = 1.0

var options: LaunchOptions

## Message for the main menu (e.g. why we were disconnected), consumed when read.
var _pending_message: String = ""
var _smoke_game_started: bool = false
var _smoke_finished: bool = false


func _ready() -> void:
	options = LaunchOptions.parse(OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if options.min_players > 0 and OS.is_debug_build():
		Session.min_players = options.min_players
	Session.auto_start = options.auto_start

	Session.lobby_entered.connect(_on_lobby_entered)
	Session.game_started.connect(_on_game_started)
	Session.session_ended.connect(_on_session_ended)

	if options.smoke_test:
		get_tree().create_timer(_SMOKE_TEST_TIMEOUT).timeout.connect(_finish_smoke_test.bind(2, "timed out"))
	_run_launch_action.call_deferred()


func consume_message() -> String:
	var message: String = _pending_message
	_pending_message = ""
	return message


func _run_launch_action() -> void:
	var player_name: String = options.player_name if not options.player_name.is_empty() else Settings.player_name
	if options.host:
		Session.host_game(player_name, options.port)
	elif not options.join_target.is_empty():
		Session.join_game(options.join_target, player_name)


func _on_lobby_entered() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
	if options.auto_ready and not Session.is_host():
		Session.set_ready(true)


func _on_game_started() -> void:
	get_tree().change_scene_to_file(ROOM_SCENE)
	if options.smoke_test:
		_smoke_game_started = true
		get_tree().create_timer(_SMOKE_TEST_LINGER).timeout.connect(_finish_smoke_test.bind(0, "game started"))


func _on_session_ended(reason: String) -> void:
	if options.smoke_test:
		# Once the game has started, peers quitting is expected.
		if not _smoke_game_started:
			_finish_smoke_test(1, "session ended before the game started: %s" % reason)
		return
	_pending_message = reason
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _finish_smoke_test(exit_code: int, detail: String) -> void:
	if _smoke_finished:
		return
	_smoke_finished = true
	print("SMOKE_TEST %s: %s" % ["PASS" if exit_code == 0 else "FAIL", detail])
	get_tree().quit(exit_code)
