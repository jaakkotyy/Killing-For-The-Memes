class_name ServerController
extends RefCounted
## Authoritative session logic. Exists only on the hosting player's machine.
##
## Session (the RPC bridge) hands it already-received intents tagged with the sender's peer id.
## It validates them against the lobby and match rules, and its signals tell Session what to
## broadcast. It never touches the network itself, so it can be unit-tested without peers.
##
## Once the game starts it owns the GuessMatch. Anything that changes the match marks it
## dirty; Session calls flush() once per frame, which emits match_changed at most once, and
## then sends every player their own snapshot_for().

## The lobby changed; send this snapshot (LobbyState.to_dict()) to every player.
signal lobby_changed(snapshot: Dictionary)
signal join_accepted(peer_id: int)
## Tell the peer why, then disconnect it.
signal join_rejected(peer_id: int, reason: String)
signal game_started(snapshot: Dictionary)
## The match changed; send every player snapshot_for(their id).
signal match_changed
## The host ended the game and everyone is back in the lobby (LobbyState.to_dict()).
signal returned_to_lobby(snapshot: Dictionary)

var lobby: LobbyState
## The running match; null in the lobby.
var guess_match: GuessMatch
## Rules for the next match. Replace before the game starts (e.g. faster rounds for testing).
var config: GameConfig = GameConfig.new()
## Seeds the match's deals and orders; 0 picks a random seed.
var rng_seed: int = 0

var _min_players: int
var _dirty: bool = false
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


## Host only, in the lobby: the next game's identity pack. An unknown pack changes nothing.
func handle_set_pack(peer_id: int, pack: Variant) -> void:
	if peer_id != LobbyState.HOST_ID or lobby.started or not IdentityPack.exists(pack):
		return
	if lobby.pack == pack:
		return
	lobby.pack = pack
	_emit_lobby_changed()


func handle_set_ready(peer_id: int, is_ready: Variant) -> void:
	if typeof(is_ready) != TYPE_BOOL or not lobby.has_player(peer_id) or lobby.started:
		return
	if lobby.get_player(peer_id).ready == is_ready:
		return
	lobby.set_ready(peer_id, is_ready)
	_emit_lobby_changed()


## Only the host may start, and only when the lobby rules allow it.
func handle_start_request(peer_id: int, now: float = 0.0) -> void:
	if peer_id != LobbyState.HOST_ID or not lobby.can_start(_min_players):
		return
	var pack: IdentityPack = IdentityPack.load_pack(lobby.pack)
	if pack == null:
		push_error("Identity pack %s is missing or broken" % lobby.pack)
		return
	lobby.started = true
	guess_match = GuessMatch.new(config, lobby.get_players(), pack, _new_rng())
	guess_match.phase_changed.connect(_mark_dirty.unbind(1))
	guess_match.player_left.connect(_mark_dirty.unbind(1))
	guess_match.start(now)
	game_started.emit(lobby.to_dict())
	_mark_dirty()


## Advances the match clock. Call every frame.
func update(now: float) -> void:
	if guess_match != null:
		guess_match.update(now)


## Emits match_changed if anything changed since the last flush. Call once per frame.
func flush() -> void:
	if _dirty and guess_match != null:
		_dirty = false
		match_changed.emit()


## What [param peer_id] may see of the match right now (hidden information removed).
func snapshot_for(peer_id: int, now: float) -> Dictionary:
	return guess_match.to_snapshot(now, peer_id) if guess_match != null else {}


## The asker's question ({text} or {stock}). Arguments come straight from the network;
## GuessMatch validates them.
func handle_ask(peer_id: int, question: Variant, now: float) -> Intent.Result:
	if guess_match == null:
		return Intent.Result.WRONG_PHASE
	return _after_intent(guess_match.ask(peer_id, question, now))


## 1 Yes, -1 No, 0 "I don't know".
func handle_answer(peer_id: int, value: Variant, now: float) -> Intent.Result:
	if guess_match == null:
		return Intent.Result.WRONG_PHASE
	return _after_intent(guess_match.answer(peer_id, value, now))


## A guess at your own identity (a pack entry id).
func handle_guess(peer_id: int, entry_id: Variant, now: float) -> Intent.Result:
	if guess_match == null:
		return Intent.Result.WRONG_PHASE
	return _after_intent(guess_match.guess(peer_id, entry_id, now))


## Host only, once the game is over: everyone goes back to the lobby to play again.
func handle_return_to_lobby(peer_id: int) -> void:
	if peer_id != LobbyState.HOST_ID or not is_match_over():
		return
	guess_match = null
	_dirty = false
	lobby.started = false
	for player: LobbyPlayer in lobby.get_players():
		lobby.set_ready(player.id, false)
	returned_to_lobby.emit(lobby.to_dict())


func is_match_over() -> bool:
	return guess_match != null and guess_match.phase == GuessMatch.Phase.GAME_OVER


func handle_peer_disconnected(peer_id: int, now: float = 0.0) -> void:
	_pending.erase(peer_id)
	if lobby.has_player(peer_id):
		lobby.remove_player(peer_id)
		_emit_lobby_changed()
	if guess_match != null:
		guess_match.remove_player(peer_id, now)


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


func _new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	return rng


func _after_intent(result: Intent.Result) -> Intent.Result:
	if result == Intent.Result.OK:
		_mark_dirty()
	return result


func _mark_dirty() -> void:
	_dirty = true
