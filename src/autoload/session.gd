extends Node
## Session RPC bridge (autoload "Session"): the one place where session RPCs live.
##
## Every peer has this node at /root/Session, so RPC paths match on all machines.
##   client → server: intents via rpc_id(1, ...), validated by ServerController.
##   server → client: authoritative snapshots via rpc_id(peer, ...).
## UI and world scenes call the public methods and listen to the signals below; they never
## send RPCs themselves. The RPC list is documented in src/net/protocol.gd.

## Emitted once, when the local player has been accepted into a lobby.
signal lobby_entered
## Emitted whenever the local lobby mirror changes.
signal lobby_updated(lobby: LobbyState)
signal game_started
## A new GuessMatch snapshot arrived (also on the host). [param previous] is null for the first.
signal guess_updated(view: GuessView, previous: GuessView)
## The host ended a finished game; everyone is back in the lobby.
signal returned_to_lobby
## The session is over. An empty reason means the local player chose to leave.
signal session_ended(reason: String)

## Seconds between sending a rejection and disconnecting the peer, so the message arrives.
const _KICK_DELAY: float = 0.5
const _TIMEOUT_CHECK_INTERVAL: float = 1.0

## Local mirror of the lobby, rebuilt from server snapshots. Treat as read-only.
var lobby: LobbyState = LobbyState.new()
## Minimum players needed to start (lowered with --min-players for local testing).
var min_players: int = Protocol.MIN_PLAYERS
## Development option: the host starts the game as soon as the lobby allows it.
var auto_start: bool = false
## Host only: rules for matches hosted from now on (App may swap in faster rounds).
var host_config: GameConfig = GameConfig.new()
## Host only: fixed match seed (0 = random), for reproducible test games.
var host_seed: int = 0
## Host only: the identity pack a new lobby starts with (the host can change it in the
## lobby). App sets this from --pack.
var host_pack: String = "musicians"
## Latest picture of the running match; null outside a game. Treat as read-only.
var guess_view: GuessView = null
## The match rules as the host sent them (GameConfig.to_dict()).
var match_config: Dictionary = {}

## Only set on the host.
var _server: ServerController = null
var _local_name: String = ""
var _in_lobby: bool = false
var _rejection_reason: String = ""
var _clock: float = 0.0
var _timeout_check_elapsed: float = 0.0


func _ready() -> void:
	Net.hosted.connect(_on_net_hosted)
	Net.connected.connect(_on_net_connected)
	Net.connect_failed.connect(_end)
	Net.server_lost.connect(_on_net_server_lost)
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.peer_left.connect(_on_net_peer_left)


func _process(delta: float) -> void:
	_clock += delta
	if _server == null:
		return
	_server.update(_clock)
	_server.flush()
	_timeout_check_elapsed += delta
	if _timeout_check_elapsed >= _TIMEOUT_CHECK_INTERVAL:
		_timeout_check_elapsed = 0.0
		for peer_id: int in _server.collect_timed_out_peers(_clock):
			_on_server_join_rejected(peer_id, Protocol.REJECT_TIMEOUT)


# --- Public API ---------------------------------------------------------------------------

func host_game(player_name: String, port: int) -> void:
	_reset()
	_local_name = player_name
	Net.host(port)


func join_game(target: String, player_name: String) -> void:
	_reset()
	_local_name = player_name
	Net.join(target)


func leave() -> void:
	_end("")


func set_ready(is_ready: bool) -> void:
	if is_host():
		_server.handle_set_ready(multiplayer.get_unique_id(), is_ready)
	elif Net.is_joined():
		_rpc_set_ready.rpc_id(1, is_ready)


## Host only, in the lobby: the next game's identity pack.
func set_pack(pack: String) -> void:
	if is_host():
		_server.handle_set_pack(local_peer_id(), pack)


## Host only. Ignored unless the lobby can start.
func request_start() -> void:
	if is_host():
		_server.handle_start_request(multiplayer.get_unique_id(), _clock)


## On your turn: ask your own yes/no question.
func ask_question(text: String) -> void:
	_send_ask({"text": text})


## On your turn: ask the pack's stock question number [param index].
func ask_stock_question(index: int) -> void:
	_send_ask({"stock": index})


## Answer the question on the screen (a GuessMatch.Answer: 1, -1 or 0).
func answer_question(value: int) -> void:
	if is_host():
		_server.handle_answer(local_peer_id(), value, _clock)
	elif Net.is_joined():
		_rpc_answer.rpc_id(1, value)


## Guess your own identity (an entry id of the game's pack).
func guess_identity(entry_id: String) -> void:
	if is_host():
		_server.handle_guess(local_peer_id(), entry_id, _clock)
	elif Net.is_joined():
		_rpc_guess.rpc_id(1, entry_id)


## The running game's identity pack (every client has the same files, or the host's).
func guess_pack() -> IdentityPack:
	var pack_id: String = guess_view.pack_id if guess_view != null else lobby.pack
	return IdentityPack.load_pack(pack_id)


## Seconds left on the round clock, counted down locally.
func guess_round_time_left() -> float:
	return guess_view.round_time_left_at(_clock) if guess_view != null else 0.0


func _send_ask(question: Dictionary) -> void:
	if is_host():
		_server.handle_ask(local_peer_id(), question, _clock)
	elif Net.is_joined():
		_rpc_ask.rpc_id(1, question)


## Host only, after the game is over: back to the lobby with the same players.
func return_to_lobby() -> void:
	if is_host():
		_server.handle_return_to_lobby(local_peer_id())


## Seconds left in the current phase, counted down locally between snapshots.
func match_time_left() -> float:
	return guess_view.time_left_at(_clock) if guess_view != null else 0.0


func is_host() -> bool:
	return _server != null


func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func get_local_player() -> LobbyPlayer:
	return lobby.get_player(local_peer_id())


# --- Net events ---------------------------------------------------------------------------

func _on_net_hosted() -> void:
	_server = ServerController.new(min_players)
	_server.config = host_config
	_server.rng_seed = host_seed
	_server.lobby_changed.connect(_on_server_lobby_changed)
	_server.join_rejected.connect(_on_server_join_rejected)
	_server.game_started.connect(_on_server_game_started)
	_server.match_changed.connect(_on_server_match_changed)
	_server.returned_to_lobby.connect(_on_server_returned_to_lobby)
	_server.handle_set_pack(LobbyState.HOST_ID, host_pack)
	# The host joins its own lobby directly, without an RPC.
	_server.handle_join_request(multiplayer.get_unique_id(), _local_name, Protocol.VERSION)


func _on_net_connected() -> void:
	_rpc_request_join.rpc_id(1, _local_name, Protocol.VERSION)


func _on_net_server_lost() -> void:
	var reason: String = _rejection_reason if not _rejection_reason.is_empty() else "Lost connection to the host."
	_end(reason)


func _on_net_peer_joined(peer_id: int) -> void:
	if _server != null:
		_server.handle_peer_connected(peer_id, _clock)


func _on_net_peer_left(peer_id: int) -> void:
	if _server != null:
		_server.handle_peer_disconnected(peer_id, _clock)


# --- Server-side handlers (host only) -----------------------------------------------------

func _on_server_lobby_changed(snapshot: Dictionary) -> void:
	_send_to_guests(_rpc_lobby_snapshot, snapshot)
	_apply_lobby_snapshot(snapshot)
	if auto_start and _server.can_start():
		_server.handle_start_request.call_deferred(multiplayer.get_unique_id(), _clock)


func _on_server_join_rejected(peer_id: int, reason: String) -> void:
	print("[Session] Rejecting peer %d: %s" % [peer_id, reason])
	_rpc_join_rejected.rpc_id(peer_id, reason)
	get_tree().create_timer(_KICK_DELAY).timeout.connect(Net.kick.bind(peer_id))


func _on_server_game_started(snapshot: Dictionary) -> void:
	# New connections stay open on purpose: late joiners get a clear "already started"
	# rejection from ServerController. (ENet's refuse_new_connections leaves them hanging.)
	var config: Dictionary = _server.config.to_dict()
	# A custom identity pack ("Our friends") exists only on the host: send its file along.
	var pack_text: String = IdentityPack.custom_pack_text(_server.lobby.pack)
	for player: LobbyPlayer in _server.lobby.get_players():
		if player.id != local_peer_id():
			_rpc_game_started.rpc_id(player.id, snapshot, config, pack_text)
	_apply_game_started(snapshot, config)


## Everyone gets their own snapshot: hidden information differs per player.
func _on_server_match_changed() -> void:
	for player: LobbyPlayer in _server.lobby.get_players():
		var snapshot: Dictionary = _server.snapshot_for(player.id, _clock)
		if player.id == local_peer_id():
			_apply_match_snapshot(snapshot)
		else:
			_rpc_match_snapshot.rpc_id(player.id, snapshot)


func _on_server_returned_to_lobby(snapshot: Dictionary) -> void:
	_send_to_guests(_rpc_returned_to_lobby, snapshot)
	_apply_returned_to_lobby(snapshot)


func _send_to_guests(method: Callable, payload: Variant) -> void:
	for player: LobbyPlayer in _server.lobby.get_players():
		if player.id != multiplayer.get_unique_id():
			method.rpc_id(player.id, payload)


# --- RPCs: client → server ----------------------------------------------------------------
# Parameters are Variants because remote input is untrusted; ServerController type-checks them.

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_join(player_name: Variant, version: Variant) -> void:
	if _server != null:
		_server.handle_join_request(multiplayer.get_remote_sender_id(), player_name, version)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(is_ready: Variant) -> void:
	if _server != null:
		_server.handle_set_ready(multiplayer.get_remote_sender_id(), is_ready)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask(question: Variant) -> void:
	if _server != null:
		_server.handle_ask(multiplayer.get_remote_sender_id(), question, _clock)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_answer(value: Variant) -> void:
	if _server != null:
		_server.handle_answer(multiplayer.get_remote_sender_id(), value, _clock)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_guess(entry_id: Variant) -> void:
	if _server != null:
		_server.handle_guess(multiplayer.get_remote_sender_id(), entry_id, _clock)


# --- RPCs: server → client ----------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_snapshot(snapshot: Dictionary) -> void:
	_apply_lobby_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_rejected(reason: String) -> void:
	# The server disconnects us right after; _on_net_server_lost reports this reason.
	_rejection_reason = reason


@rpc("authority", "call_remote", "reliable")
func _rpc_game_started(snapshot: Dictionary, config: Dictionary, pack_text: String) -> void:
	if not pack_text.is_empty():
		var lobby_pack: String = str(snapshot.get("pack", ""))
		var received: IdentityPack = IdentityPack.receive(lobby_pack, pack_text)
		print("[Session] Received the host's pack %s (%d entries)." % [lobby_pack, received.size() if received != null else 0])
	_apply_game_started(snapshot, config)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_snapshot(snapshot: Dictionary) -> void:
	_apply_match_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable")
func _rpc_returned_to_lobby(snapshot: Dictionary) -> void:
	_apply_returned_to_lobby(snapshot)


# --- Local state --------------------------------------------------------------------------

func _apply_lobby_snapshot(snapshot: Dictionary) -> void:
	lobby = LobbyState.from_dict(snapshot)
	if not _in_lobby and lobby.has_player(local_peer_id()):
		_in_lobby = true
		lobby_entered.emit()
	lobby_updated.emit(lobby)


func _apply_game_started(snapshot: Dictionary, config: Dictionary) -> void:
	_apply_lobby_snapshot(snapshot)
	match_config = config
	guess_view = null
	print("[Session] Game started with %d players." % lobby.player_count())
	game_started.emit()


func _apply_match_snapshot(snapshot: Dictionary) -> void:
	var previous: GuessView = guess_view
	guess_view = GuessView.from_snapshot(snapshot, _clock)
	var phase_changed: bool = previous == null or previous.phase != guess_view.phase
	if phase_changed:
		print("[Session] Round %d: %s" % [guess_view.round_number, GuessMatch.Phase.keys()[guess_view.phase]])
	if phase_changed and guess_view.phase == GuessMatch.Phase.GAME_OVER:
		var names: PackedStringArray = []
		for winner: int in guess_view.winner_ids:
			names.append("%s (%d)" % [guess_view.player_name(winner), guess_view.score_of(winner)])
		print("[Session] Game over. Winner: %s" % (", ".join(names) if not names.is_empty() else "nobody"))
	guess_updated.emit(guess_view, previous)


func _apply_returned_to_lobby(snapshot: Dictionary) -> void:
	guess_view = null
	_apply_lobby_snapshot(snapshot)
	print("[Session] Back in the lobby.")
	returned_to_lobby.emit()


func _end(reason: String) -> void:
	Net.close()
	_reset()
	IdentityPack.forget_received()
	session_ended.emit(reason)


func _reset() -> void:
	_server = null
	lobby = LobbyState.new()
	guess_view = null
	match_config = {}
	_in_lobby = false
	_rejection_reason = ""
	_timeout_check_elapsed = 0.0
