class_name PlayerState
extends RefCounted
## One player's state for the whole match (as opposed to LobbyPlayer, which only lives in the lobby).

enum Status { ALIVE, ELIMINATED, LEFT }

var id: int
var name: String
var seat: int
var status: Status = Status.ALIVE
var bullets: int = 0
## Round in which the player died or left; 0 while alive.
var out_in_round: int = 0


func _init(p_id: int = 0, p_name: String = "", p_seat: int = 0, p_bullets: int = 0) -> void:
	id = p_id
	name = p_name
	seat = p_seat
	bullets = p_bullets


func is_alive() -> bool:
	return status == Status.ALIVE


## Still connected and watching (alive or eliminated, but not disconnected).
func is_present() -> bool:
	return status != Status.LEFT


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "seat": seat, "status": status, "bullets": bullets, "out_in_round": out_in_round}


static func from_dict(data: Dictionary) -> PlayerState:
	var player := PlayerState.new(int(data.get("id", 0)), str(data.get("name", "")), int(data.get("seat", 0)), int(data.get("bullets", 0)))
	player.status = int(data.get("status", Status.ALIVE)) as Status
	player.out_in_round = int(data.get("out_in_round", 0))
	return player
