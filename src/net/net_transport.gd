class_name NetTransport
extends RefCounted
## Abstract network transport: produces the MultiplayerPeer that Godot's high-level
## multiplayer API runs on. Game code never knows which transport is active.
##
## Implementations:
##   EnetTransport  - direct UDP (development, LAN, VPN, port forwarding)
##   SteamTransport - Steam lobbies + relay networking via GodotSteam (later)
##
## host() and join() may finish asynchronously (Steam lobby creation does), so results are
## reported through signals rather than return values.

## The peer is ready to install. For clients the connection may still be in progress;
## the multiplayer API reports when it completes.
signal peer_ready(peer: MultiplayerPeer)
signal failed(reason: String)


func get_transport_name() -> String:
	return "none"


## Starts hosting. Must eventually emit peer_ready or failed.
func host(_port: int, _max_clients: int) -> void:
	failed.emit("Hosting is not supported by the %s transport." % get_transport_name())


## Starts joining [param _target], whose meaning is transport-specific
## (IP/join code for ENet, lobby id for Steam). Must eventually emit peer_ready or failed.
func join(_target: String) -> void:
	failed.emit("Joining is not supported by the %s transport." % get_transport_name())


## Information the host shows so friends can join, e.g. addresses and join codes.
func get_join_info() -> Dictionary:
	return {}


## Releases transport resources (the peer itself is closed by Net).
func close() -> void:
	pass
