class_name LobbyState
extends RefCounted
## Pure data and rules for the pre-game lobby: who is in it, their seats, names and readiness.
##
## The server's ServerController owns the authoritative instance. Clients hold a read-only
## mirror rebuilt from to_dict() snapshots. No networking or scene tree access here.

const HOST_ID: int = 1
const NAME_MAX_LENGTH: int = 16
const DEFAULT_NAME: String = "Player"

var max_players: int
## True once the host has started the game; the lobby then accepts no changes.
var started: bool = false

var _players: Dictionary[int, LobbyPlayer] = {}


func _init(p_max_players: int = 8) -> void:
	max_players = p_max_players


## Adds a player with a sanitized, de-duplicated name and the lowest free seat.
## Callers must check has_player() and is_full() first.
func add_player(id: int, requested_name: String) -> LobbyPlayer:
	assert(not has_player(id), "player %d already in lobby" % id)
	assert(not is_full(), "lobby is full")
	var player := LobbyPlayer.new(id, _make_unique_name(sanitize_name(requested_name)), _first_free_seat())
	_players[id] = player
	return player


func remove_player(id: int) -> void:
	_players.erase(id)


func has_player(id: int) -> bool:
	return _players.has(id)


func get_player(id: int) -> LobbyPlayer:
	return _players.get(id)


## All players ordered by seat.
func get_players() -> Array[LobbyPlayer]:
	var players: Array[LobbyPlayer] = []
	players.assign(_players.values())
	players.sort_custom(func(a: LobbyPlayer, b: LobbyPlayer) -> bool: return a.seat < b.seat)
	return players


func player_count() -> int:
	return _players.size()


func is_full() -> bool:
	return _players.size() >= max_players


func set_ready(id: int, is_ready: bool) -> void:
	if has_player(id):
		_players[id].ready = is_ready


## True when every player except the host has readied up. The host signals readiness by
## pressing Start.
func all_guests_ready() -> bool:
	for player: LobbyPlayer in _players.values():
		if player.id != HOST_ID and not player.ready:
			return false
	return true


func can_start(min_players: int) -> bool:
	return not started and player_count() >= min_players and all_guests_ready()


## Strips control characters, collapses whitespace and trims to NAME_MAX_LENGTH.
## Falls back to DEFAULT_NAME when nothing printable is left.
static func sanitize_name(raw: String) -> String:
	var printable: String = ""
	for i: int in range(raw.length()):
		var code: int = raw.unicode_at(i)
		if code >= 32 and code != 127:
			printable += raw[i]
	var collapsed: String = " ".join(printable.split(" ", false))
	var trimmed: String = collapsed.substr(0, NAME_MAX_LENGTH).strip_edges()
	return trimmed if not trimmed.is_empty() else DEFAULT_NAME


func to_dict() -> Dictionary:
	var players: Array[Dictionary] = []
	for player: LobbyPlayer in get_players():
		players.append(player.to_dict())
	return {"max_players": max_players, "started": started, "players": players}


static func from_dict(data: Dictionary) -> LobbyState:
	var state := LobbyState.new(int(data.get("max_players", 8)))
	state.started = bool(data.get("started", false))
	for entry: Variant in data.get("players", []):
		if entry is Dictionary:
			var player := LobbyPlayer.from_dict(entry)
			state._players[player.id] = player
	return state


func _first_free_seat() -> int:
	var taken: Array[int] = []
	for player: LobbyPlayer in _players.values():
		taken.append(player.seat)
	var seat: int = 0
	while seat in taken:
		seat += 1
	return seat


func _make_unique_name(base: String) -> String:
	if not _is_name_taken(base):
		return base
	var n: int = 2
	while true:
		var suffix: String = " %d" % n
		var candidate: String = base.substr(0, NAME_MAX_LENGTH - suffix.length()).strip_edges() + suffix
		if not _is_name_taken(candidate):
			return candidate
		n += 1
	return base  # Unreachable; keeps the parser happy.


func _is_name_taken(candidate: String) -> bool:
	for player: LobbyPlayer in _players.values():
		if player.name.to_lower() == candidate.to_lower():
			return true
	return false
