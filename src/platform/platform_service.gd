class_name PlatformService
extends RefCounted
## Store/platform features the game may use: player identity, achievements, rich presence.
## This base class is a harmless no-op so game code can call it unconditionally.
## Implementations: NullPlatform (no store), SteamPlatform (GodotSteam, later).


func get_platform_name() -> String:
	return "none"


## The player's platform display name, or "" if unknown.
func get_player_name() -> String:
	return ""


func unlock_achievement(_achievement_id: String) -> void:
	pass


## Status text shown to friends (e.g. "In lobby (3/8)").
func set_rich_presence(_text: String) -> void:
	pass
