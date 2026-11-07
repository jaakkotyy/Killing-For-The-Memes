class_name SearchStation
extends CrtStation
## Guess mode's CRT: the SearchTerminal (the identity database) on the local player's monitor.

var terminal: SearchTerminal


func setup(camera: CameraRig, seat: Seat, pack: IdentityPack) -> void:
	terminal = SearchTerminal.new()
	terminal.name = "SearchTerminal"
	terminal.set_pack(pack)
	terminal.portraits_enabled = App.online_images_allowed()
	setup_screen(camera, seat, terminal)


func _focus_screen() -> void:
	terminal.focus_first_field()
