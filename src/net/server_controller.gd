class_name ServerController
extends RefCounted
## Authoritative session logic. Exists only on the hosting player's machine.
##
## Session (the RPC bridge) hands it already-received intents tagged with the sender's peer id.
## It validates them against the lobby rules, and its signals tell Session what to broadcast.
## It never touches the network itself, so it can be unit-tested without peers.

## The lobby changed; send this snapshot (LobbyState.to_dict()) to every player.
signal lobby_changed(snapshot: Dictionary)
signal join_accepted(peer_id: int)
## Tell the peer why, then disconnect it.
signal join_rejected(peer_id: int, reason: String)
signal game_started(snapshot: Dictionary)

var lobby: LobbyState

var _min_players: int
## Peers that connected but have not sent a join request yet: peer id -> connect time.
var _pending: Dictionary[int, float] = {}


func _init(min_players: int = Protocol.MIN_PLAYERS, max_players: int = Protocol.MAX_PLAYERS) -> void:
	_min_players = min_players
	lobby = LobbyState.new(max_players)


func handle_peer_connected(peer_id: int, now: float) -> void:
	if not lobby.has_player(peer_id):
		_pending[peer_id] = now


## Arguments are Variants because they arrive straight from the network and must be type-checked.
func handle_join_request(peer_id: int, requested_name: Variant, version: Variant) -> void:
	if lobby.has_player(peer_id):
		return  # Duplicate request; ignore.
	_pending.erase(peer_id)

	if typeof(version) != TYPE_INT or version != Protocol.VERSION:
		join_rejected.emit(peer_id, Protocol.REJECT_VERSION_MISMATCH)
		return
	if lobby.started:
		join_rejected.emit(peer_id, Protocol.REJECT_GAME_IN_PROGRESS)
		return
	if lobby.is_full():
		join_rejected.emit(peer_id, Protocol.REJECT_LOBBY_FULL)
		return

	var name_text: String = requested_name if typeof(requested_name) == TYPE_STRING else ""
	lobby.add_player(peer_id, name_text)
	join_accepted.emit(peer_id)
	_emit_lobby_changed()


func handle_set_ready(peer_id: int, is_ready: Variant) -> void:
	if typeof(is_ready) != TYPE_BOOL or not lobby.has_player(peer_id) or lobby.started:
		return
	if lobby.get_player(peer_id).ready == is_ready:
		return
	lobby.set_ready(peer_id, is_ready)
	_emit_lobby_changed()


## Only the host may start, and only when the lobby rules allow it.
func handle_start_request(peer_id: int) -> void:
	if peer_id != LobbyState.HOST_ID or not lobby.can_start(_min_players):
		return
	lobby.started = true
	game_started.emit(lobby.to_dict())


func handle_peer_disconnected(peer_id: int) -> void:
	_pending.erase(peer_id)
	if lobby.has_player(peer_id):
		lobby.remove_player(peer_id)
		_emit_lobby_changed()


## Returns (and forgets) peers that connected but never sent a join request in time.
func collect_timed_out_peers(now: float) -> Array[int]:
	var timed_out: Array[int] = []
	for peer_id: int in _pending.keys():
		if now - _pending[peer_id] >= Protocol.JOIN_REQUEST_TIMEOUT:
			timed_out.append(peer_id)
	for peer_id: int in timed_out:
		_pending.erase(peer_id)
	return timed_out


func can_start() -> bool:
	return lobby.can_start(_min_players)


func _emit_lobby_changed() -> void:
	lobby_changed.emit(lobby.to_dict())
