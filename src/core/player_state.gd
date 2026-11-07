class_name PlayerState
extends RefCounted
## One player's state for the whole match (as opposed to LobbyPlayer, which only lives in the lobby).

enum Status { PLAYING, LEFT }

var id: int
var name: String
var seat: int
var status: Status = Status.PLAYING
## Round in which the player left; 0 while still playing.
var out_in_round: int = 0


func _init(p_id: int = 0, p_name: String = "", p_seat: int = 0) -> void:
	id = p_id
	name = p_name
	seat = p_seat


## Still connected (not disconnected).
func is_present() -> bool:
	return status != Status.LEFT


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "seat": seat, "status": status, "out_in_round": out_in_round}


static func from_dict(data: Dictionary) -> PlayerState:
	var player := PlayerState.new(int(data.get("id", 0)), str(data.get("name", "")), int(data.get("seat", 0)))
	var status_value: int = int(data.get("status", Status.PLAYING))
	player.status = Status.LEFT if status_value == Status.LEFT else Status.PLAYING
	player.out_in_round = int(data.get("out_in_round", 0))
	return player
