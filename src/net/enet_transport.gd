class_name EnetTransport
extends NetTransport
## Direct UDP connections via ENet. Works on a LAN, over a virtual LAN (Tailscale/ZeroTier)
## or over the internet when the host forwards the port.

var _port: int = 0


func get_transport_name() -> String:
	return "ENet"


func host(port: int, max_clients: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		failed.emit("Could not host on port %d (%s). Is another program already using it?" % [port, error_string(err)])
		return
	_port = port
	peer_ready.emit(peer)


func join(target: String) -> void:
	var parsed: Dictionary = JoinCode.parse_target(target)
	if parsed.is_empty():
		failed.emit("\"%s\" is not a valid address or join code." % target)
		return
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(str(parsed["address"]), int(parsed["port"]))
	if err != OK:
		failed.emit("Could not connect to %s (%s)." % [target, error_string(err)])
		return
	peer_ready.emit(peer)


## {"port": int, "addresses": [{"address": String, "code": String}, ...]}
func get_join_info() -> Dictionary:
	var addresses: Array[Dictionary] = []
	for address: String in local_ipv4_addresses():
		addresses.append({"address": address, "code": JoinCode.encode(address, _port)})
	return {"port": _port, "addresses": addresses}


func close() -> void:
	_port = 0


## This machine's IPv4 addresses that other machines could plausibly reach, most useful first.
static func local_ipv4_addresses() -> PackedStringArray:
	var candidates: Array[String] = []
	for address: String in IP.get_local_addresses():
		if JoinCode.is_valid_ipv4(address) and not address.begins_with("127.") and not address.begins_with("169.254."):
			candidates.append(address)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var rank_a: int = address_rank(a)
		var rank_b: int = address_rank(b)
		return rank_a < rank_b if rank_a != rank_b else a < b)
	return PackedStringArray(candidates)


## Lower is more likely to be the address friends should use. Home LANs come first;
## 172.16/12 comes last because on Windows it is usually a Hyper-V/WSL/Docker adapter.
static func address_rank(address: String) -> int:
	var octets: PackedStringArray = address.split(".")
	var first: int = octets[0].to_int()
	var second: int = octets[1].to_int()
	if first == 192 and second == 168:
		return 0
	if first == 10:
		return 1
	if first == 100 and second >= 64 and second <= 127:
		return 2  # Carrier-grade NAT range, used by Tailscale.
	if first == 172 and second >= 16 and second <= 31:
		return 4
	return 3
