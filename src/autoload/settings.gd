extends Node
## Persistent per-machine settings stored in user://settings.cfg (autoload "Settings").

const _PATH: String = "user://settings.cfg"
const _SECTION: String = "general"

var player_name: String = ""
var host_port: int = Protocol.DEFAULT_PORT
var last_join_target: String = ""
## Show portraits of the identities, fetched from Wikimedia Commons.
var online_portraits: bool = true
## Background music volume, 0 (off) to 1.
var music_volume: float = 0.6


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_PATH) != OK:
		return
	player_name = str(config.get_value(_SECTION, "player_name", player_name))
	host_port = int(config.get_value(_SECTION, "host_port", host_port))
	last_join_target = str(config.get_value(_SECTION, "last_join_target", last_join_target))
	online_portraits = bool(config.get_value(_SECTION, "online_portraits", online_portraits))
	music_volume = clampf(float(config.get_value(_SECTION, "music_volume", music_volume)), 0.0, 1.0)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "player_name", player_name)
	config.set_value(_SECTION, "host_port", host_port)
	config.set_value(_SECTION, "last_join_target", last_join_target)
	config.set_value(_SECTION, "online_portraits", online_portraits)
	config.set_value(_SECTION, "music_volume", music_volume)
	var err: Error = config.save(_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))
