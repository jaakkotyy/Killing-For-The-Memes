class_name LobbyPlayer
extends RefCounted
## One player in the pre-game lobby.

## Network peer id. The host is always LobbyState.HOST_ID.
var id: int
## Display name, already sanitized and unique within the lobby.
var name: String
## Seat index at the table (0..max_players-1). Seats are reused when players leave.
var seat: int
var ready: bool = false


func _init(p_id: int = 0, p_name: String = "", p_seat: int = 0) -> void:
	id = p_id
	name = p_name
	seat = p_seat


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "seat": seat, "ready": ready}


static func from_dict(data: Dictionary) -> LobbyPlayer:
	var player := LobbyPlayer.new(int(data.get("id", 0)), str(data.get("name", "")), int(data.get("seat", 0)))
	player.ready = bool(data.get("ready", false))
	return player
