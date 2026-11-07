extends Node
## Top-level application flow (autoload "App").
##
## Applies launch options and switches between the top-level scenes
## (main menu → lobby → room → main menu) in response to Session events, so the scenes
## themselves stay unaware of each other. Owns the background music, so it plays on
## across every scene change.

const MAIN_MENU_SCENE: String = "res://src/ui/main_menu/main_menu.tscn"
const LOBBY_SCENE: String = "res://src/ui/lobby/lobby.tscn"
const ROOM_SCENE: String = "res://src/world/room/room.tscn"
const AUTO_PLAYER_SCRIPT: GDScript = preload("res://src/util/guess_auto_player.gd")

const _SMOKE_TEST_TIMEOUT: float = 30.0
## A whole fast game with up to 8 players takes well under a minute.
const _SMOKE_TEST_GAME_TIMEOUT: float = 120.0
## Linger after the game starts so every instance in a smoke test sees the start.
const _SMOKE_TEST_LINGER: float = 1.0

var options: LaunchOptions

## Message for the main menu (e.g. why we were disconnected), consumed when read.
var _pending_message: String = ""
var _smoke_game_started: bool = false
var _smoke_game_over: String = ""
var _smoke_finished: bool = false


func _ready() -> void:
	options = LaunchOptions.parse(OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if options.min_players > 0 and OS.is_debug_build():
		Session.min_players = options.min_players
	Session.auto_start = options.auto_start
	if options.fast_rounds and OS.is_debug_build():
		Session.host_config = fast_config()
	if options.seed_value != 0:
		Session.host_seed = options.seed_value
	if not options.pack.is_empty():
		Session.host_pack = options.pack

	Session.lobby_entered.connect(_on_lobby_entered)
	Session.game_started.connect(_on_game_started)
	Session.returned_to_lobby.connect(_on_returned_to_lobby)
	Session.session_ended.connect(_on_session_ended)
	Session.guess_updated.connect(_on_guess_updated)
	if options.auto_play:
		var bot: Node = AUTO_PLAYER_SCRIPT.new()
		bot.name = "AutoPlayer"
		add_child(bot)

	if not options.no_music and DisplayServer.get_name() != "headless":
		var music := Music.new()
		music.name = "Music"
		add_child(music)

	if options.smoke_test:
		var timeout: float = _SMOKE_TEST_GAME_TIMEOUT if options.smoke_test_full_game else _SMOKE_TEST_TIMEOUT
		get_tree().create_timer(timeout).timeout.connect(_finish_smoke_test.bind(2, "timed out"))
	_run_launch_action.call_deferred()


## Very short phases so automated tests can play whole games quickly.
static func fast_config() -> GameConfig:
	var config := GameConfig.new()
	config.guess_rounds = 2
	config.deal_duration = 0.5
	config.round_duration = 20.0
	config.ask_duration = 2.0
	config.answer_duration = 1.5
	config.result_duration = 0.3
	config.reveal_duration = 0.8
	return config


func consume_message() -> String:
	var message: String = _pending_message
	_pending_message = ""
	return message


## Whether portraits may be fetched from Wikimedia Commons. Off in settings or with
## --offline-portraits.
func online_images_allowed() -> bool:
	return options != null and Settings.online_portraits and not options.offline_portraits


func _run_launch_action() -> void:
	var player_name: String = options.player_name if not options.player_name.is_empty() else Settings.player_name
	if options.room_preview > 0:
		get_tree().change_scene_to_file(ROOM_SCENE)
	elif options.host:
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
		if not options.smoke_test_full_game:
			get_tree().create_timer(_SMOKE_TEST_LINGER).timeout.connect(_finish_smoke_test.bind(0, "game started"))


func _on_guess_updated(view: GuessView, previous: GuessView) -> void:
	if not options.smoke_test_full_game or view.phase != GuessMatch.Phase.GAME_OVER:
		return
	if previous == null or previous.phase != GuessMatch.Phase.GAME_OVER:
		var names: PackedStringArray = []
		for winner: int in view.winner_ids:
			names.append(view.player_name(winner))
		_smoke_game_over = "game over after %d rounds, %d solved in the last, winner %s" % [
			view.round_number, view.solved.size(), ", ".join(names) if not names.is_empty() else "nobody"]
		get_tree().create_timer(_SMOKE_TEST_LINGER).timeout.connect(_finish_smoke_test.bind(0, _smoke_game_over))


func _on_returned_to_lobby() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)
	if options.auto_ready and not Session.is_host():
		Session.set_ready.call_deferred(true)


func _on_session_ended(reason: String) -> void:
	if options.smoke_test:
		# Once the game has started, peers quitting is expected (unless we wait for the end).
		if not _smoke_game_started:
			_finish_smoke_test(1, "session ended before the game started: %s" % reason)
		elif options.smoke_test_full_game:
			# The host may quit first once everyone has seen the end; that still counts.
			if not _smoke_game_over.is_empty():
				_finish_smoke_test(0, _smoke_game_over)
			else:
				_finish_smoke_test(1, "session ended before the game was over: %s" % reason)
		return
	_pending_message = reason
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _finish_smoke_test(exit_code: int, detail: String) -> void:
	if _smoke_finished:
		return
	_smoke_finished = true
	print("SMOKE_TEST %s: %s" % ["PASS" if exit_code == 0 else "FAIL", detail])
	get_tree().quit(exit_code)
