class_name NullPlatform
extends PlatformService
## Used when the game runs without a store platform (development, DRM-free builds).


func get_platform_name() -> String:
	return "none"


## Suggests the OS user name as a default player name.
func get_player_name() -> String:
	var user: String = OS.get_environment("USERNAME")
	return user if not user.is_empty() else OS.get_environment("USER")
