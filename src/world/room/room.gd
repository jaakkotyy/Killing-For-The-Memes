extends Control
## Placeholder for the 3D room (milestone M3). Shows who is at the table so the
## lobby → game transition can be tested end to end.

@onready var _players_label: Label = %PlayersLabel
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	Session.lobby_updated.connect(_refresh)
	_leave_button.pressed.connect(Session.leave)
	_refresh(Session.lobby)


func _refresh(lobby: LobbyState) -> void:
	var names: PackedStringArray = []
	for player: LobbyPlayer in lobby.get_players():
		names.append("Seat %d: %s" % [player.seat + 1, player.name])
	_players_label.text = "\n".join(names)
