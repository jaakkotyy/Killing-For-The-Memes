class_name JoinCode
extends RefCounted
## Turns an IPv4 address + port into a short, friendly code (e.g. "60R2A-1GZ8H") and parses
## whatever a player types into the Join box: a code, an IP, IP:port, or a host name.
##
## The code is only the address in disguise, so it works wherever that address is reachable
## (same LAN, Tailscale/ZeroTier, or a forwarded port). Steam lobbies replace this later.

## Crockford base32: no I, L, O or U, so codes are hard to misread.
const _ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
## 48 bits of payload (32-bit address + 16-bit port) fit in 10 base32 digits.
const _CODE_LENGTH: int = 10
const _PAYLOAD_BITS: int = 48


## Returns the join code for [param address]:[param port], or "" if either is invalid.
static func encode(address: String, port: int) -> String:
	if not is_valid_ipv4(address) or port < 1 or port > 65535:
		return ""
	var value: int = 0
	for octet: String in address.split("."):
		value = (value << 8) | octet.to_int()
	value = (value << 16) | port

	var digits: String = ""
	for i: int in range(_CODE_LENGTH):
		digits = _ALPHABET[value & 31] + digits
		value >>= 5
	return digits.substr(0, 5) + "-" + digits.substr(5)


## Decodes a join code into {"address": String, "port": int}, or {} if it is not valid.
## Case, dashes and spaces are ignored, and O/I/L are read as 0/1/1.
static func decode(code: String) -> Dictionary:
	var normalized: String = _normalize(code)
	if normalized.length() != _CODE_LENGTH:
		return {}
	var value: int = 0
	for i: int in range(normalized.length()):
		var digit: int = _ALPHABET.find(normalized[i])
		if digit < 0:
			return {}
		value = (value << 5) | digit
	if value >> _PAYLOAD_BITS != 0:
		return {}

	var port: int = value & 0xFFFF
	if port == 0:
		return {}
	var ip: int = value >> 16
	var address: String = "%d.%d.%d.%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255]
	return {"address": address, "port": port}


## Parses text typed in the Join box into {"address": String, "port": int}, or {} if invalid.
## Accepts "1.2.3.4", "1.2.3.4:9000", "localhost", "my-pc.lan:9000" and join codes.
static func parse_target(text: String, default_port: int = Protocol.DEFAULT_PORT) -> Dictionary:
	var target: String = text.strip_edges()
	if target.is_empty():
		return {}

	var looks_like_address: bool = target.contains(".") or target.contains(":") or target.to_lower() == "localhost"
	if not looks_like_address:
		if _normalize(target).length() == _CODE_LENGTH:
			return decode(target)
		if _is_valid_hostname(target):
			return {"address": target, "port": default_port}
		return {}

	var address: String = target
	var port: int = default_port
	if target.contains(":"):
		if target.count(":") > 1:
			return {}  # IPv6 is not supported yet.
		var colon: int = target.find(":")
		address = target.substr(0, colon)
		var port_text: String = target.substr(colon + 1)
		if not _is_digits(port_text):
			return {}
		port = port_text.to_int()

	if address.is_empty() or port < 1 or port > 65535:
		return {}
	# Anything made only of digits and dots must be a real IPv4 address, not a "host name".
	if _is_digits(address.replace(".", "")):
		if not is_valid_ipv4(address):
			return {}
	elif not _is_valid_hostname(address):
		return {}
	return {"address": address, "port": port}


static func is_valid_ipv4(address: String) -> bool:
	var parts: PackedStringArray = address.split(".")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part.length() > 3 or not _is_digits(part) or part.to_int() > 255:
			return false
	return true


static func _normalize(code: String) -> String:
	return code.strip_edges().to_upper().replace("-", "").replace(" ", "") \
		.replace("O", "0").replace("I", "1").replace("L", "1")


static func _is_digits(text: String) -> bool:
	return not text.is_empty() and text.lstrip("0123456789").is_empty()


static func _is_valid_hostname(text: String) -> bool:
	var label: String = "[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
	var regex: RegEx = RegEx.create_from_string("^%s(\\.%s)*$" % [label, label])
	return text.length() <= 253 and regex.search(text) != null
