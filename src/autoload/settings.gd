extends Node
## Persistent per-machine settings stored in user://settings.cfg (autoload "Settings").

const _PATH: String = "user://settings.cfg"
const _SECTION: String = "general"

var player_name: String = ""
var host_port: int = Protocol.DEFAULT_PORT
var last_join_target: String = ""
## Host: offer popular meme templates from imgflip.com besides our own.
var online_templates: bool = true
## Host: your own GIPHY API key, for GIF templates (https://developers.giphy.com). Kept in
## user://settings.cfg on this machine only; the GIPHY_API_KEY environment variable wins.
var giphy_api_key: String = ""
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
	online_templates = bool(config.get_value(_SECTION, "online_templates", online_templates))
	giphy_api_key = str(config.get_value(_SECTION, "giphy_api_key", giphy_api_key)).strip_edges()
	music_volume = clampf(float(config.get_value(_SECTION, "music_volume", music_volume)), 0.0, 1.0)


## The key to use for GIPHY ("" = no GIF templates). Never print it.
func get_giphy_api_key() -> String:
	var from_env: String = OS.get_environment("GIPHY_API_KEY").strip_edges()
	return from_env if not from_env.is_empty() else giphy_api_key


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "player_name", player_name)
	config.set_value(_SECTION, "host_port", host_port)
	config.set_value(_SECTION, "last_join_target", last_join_target)
	config.set_value(_SECTION, "online_templates", online_templates)
	config.set_value(_SECTION, "music_volume", music_volume)
	if not giphy_api_key.is_empty():
		config.set_value(_SECTION, "giphy_api_key", giphy_api_key)
	var err: Error = config.save(_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))
