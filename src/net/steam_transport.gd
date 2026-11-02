class_name SteamTransport
extends NetTransport
## Placeholder for Steam networking. It will be implemented with GodotSteam once the game
## has a Steam App ID. Planned flow:
##   host():  Steam.createLobby() → on lobby_created → SteamMultiplayerPeer.create_host() → peer_ready
##   join():  target is a lobby id (from an overlay invite or join request)
##            Steam.joinLobby() → on lobby_joined → create_client(lobby owner) → peer_ready
##   get_join_info(): {"lobby_id": int}; friends join through the Steam overlay instead of codes.
## Nothing outside src/net/ and src/platform/ needs to change when this is implemented.


func get_transport_name() -> String:
	return "Steam"


func host(_port: int, _max_clients: int) -> void:
	failed.emit("Steam networking is not available in this build.")


func join(_target: String) -> void:
	failed.emit("Steam networking is not available in this build.")
