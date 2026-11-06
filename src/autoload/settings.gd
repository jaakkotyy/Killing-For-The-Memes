extends Node
## Persistent per-machine settings stored in user://settings.cfg (autoload "Settings").

const _PATH: String = "user://settings.cfg"
const _SECTION: String = "general"

var player_name: String = ""
var host_port: int = Protocol.DEFAULT_PORT
var last_join_target: String = ""


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_PATH) != OK:
		return
	player_name = str(config.get_value(_SECTION, "player_name", player_name))
	host_port = int(config.get_value(_SECTION, "host_port", host_port))
	last_join_target = str(config.get_value(_SECTION, "last_join_target", last_join_target))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "player_name", player_name)
	config.set_value(_SECTION, "host_port", host_port)
	config.set_value(_SECTION, "last_join_target", last_join_target)
	var err: Error = config.save(_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))
