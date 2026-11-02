extends Node
## Network connection lifecycle (autoload "Net").
##
## Owns the active NetTransport and installs the MultiplayerPeer it produces into Godot's
## high-level multiplayer API. Knows nothing about lobbies or game rules; that is Session.
## Switching from ENet to Steam means calling set_transport(), nothing else.

signal hosted
signal connected
signal connect_failed(reason: String)
## The server closed or dropped the connection (clients only).
signal server_lost
## A client connected/disconnected (server only).
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Mode { OFFLINE, HOSTING, CONNECTING, CONNECTED }

var mode: Mode = Mode.OFFLINE
var transport: NetTransport

var _requested_mode: Mode = Mode.OFFLINE
var _connect_timer: Timer


func _ready() -> void:
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = Protocol.CONNECT_TIMEOUT
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)

	set_transport(EnetTransport.new())

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Clients only ever talk to the server; never relay messages between clients.
	(multiplayer as SceneMultiplayer).server_relay = false


func set_transport(new_transport: NetTransport) -> void:
	if transport != null:
		close()
		transport.peer_ready.disconnect(_on_transport_peer_ready)
		transport.failed.disconnect(_on_transport_failed)
	transport = new_transport
	transport.peer_ready.connect(_on_transport_peer_ready)
	transport.failed.connect(_on_transport_failed)


func host(port: int) -> void:
	close()
	_requested_mode = Mode.HOSTING
	transport.host(port, Protocol.MAX_PLAYERS - 1)


func join(target: String) -> void:
	close()
	_requested_mode = Mode.CONNECTING
	mode = Mode.CONNECTING
	transport.join(target)


## Disconnects everything and returns to offline mode. Emits no signals.
func close() -> void:
	_connect_timer.stop()
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if transport != null:
		transport.close()
	mode = Mode.OFFLINE
	_requested_mode = Mode.OFFLINE


## Server only: disconnects a client.
func kick(peer_id: int) -> void:
	if mode == Mode.HOSTING and peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func is_hosting() -> bool:
	return mode == Mode.HOSTING


func is_joined() -> bool:
	return mode == Mode.CONNECTED


func _on_transport_peer_ready(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	if _requested_mode == Mode.HOSTING:
		mode = Mode.HOSTING
		print("[Net] Hosting via %s." % transport.get_transport_name())
		hosted.emit()
	else:
		mode = Mode.CONNECTING
		_connect_timer.start()


func _on_transport_failed(reason: String) -> void:
	close()
	connect_failed.emit(reason)


func _on_connected_to_server() -> void:
	_connect_timer.stop()
	mode = Mode.CONNECTED
	print("[Net] Connected as peer %d." % multiplayer.get_unique_id())
	connected.emit()


func _on_connection_failed() -> void:
	close()
	connect_failed.emit("Could not connect to the host.")


func _on_connect_timeout() -> void:
	if mode == Mode.CONNECTING:
		close()
		connect_failed.emit("Could not reach the host (timed out). Check the address and that the host's port is open.")


func _on_server_disconnected() -> void:
	close()
	server_lost.emit()


func _on_peer_connected(peer_id: int) -> void:
	if mode == Mode.HOSTING:
		peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode == Mode.HOSTING:
		peer_left.emit(peer_id)
