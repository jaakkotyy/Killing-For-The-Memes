class_name LaunchOptions
extends RefCounted
## Command-line flags for development and local multiplayer testing.
## Put them after "--" so Godot passes them through, e.g.
##   godot --path . -- --host --name=Alice
##
##   --host               host a game immediately
##   --join=<target>      join immediately (IP, IP:port or join code)
##   --name=<name>        player name for this instance (not saved to settings)
##   --port=<port>        port to host on (default Protocol.DEFAULT_PORT)
##   --auto-ready         ready up automatically after entering a lobby
##   --auto-start         (host) start as soon as the lobby allows it
##   --min-players=<n>    override the minimum player count (debug builds only)
##   --smoke-test         quit with exit code 0 once the game starts, non-zero on failure

var host: bool = false
var join_target: String = ""
var player_name: String = ""
var port: int = Protocol.DEFAULT_PORT
var auto_ready: bool = false
var auto_start: bool = false
## 0 means "not set".
var min_players: int = 0
var smoke_test: bool = false


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg: String in args:
		var key: String = arg
		var value: String = ""
		var equals: int = arg.find("=")
		if equals != -1:
			key = arg.substr(0, equals)
			value = arg.substr(equals + 1)
		match key:
			"--host":
				options.host = true
			"--join":
				options.join_target = value
			"--name":
				options.player_name = value
			"--port":
				if value.is_valid_int():
					options.port = clampi(value.to_int(), 1, 65535)
			"--auto-ready":
				options.auto_ready = true
			"--auto-start":
				options.auto_start = true
			"--min-players":
				if value.is_valid_int():
					options.min_players = clampi(value.to_int(), 1, Protocol.MAX_PLAYERS)
			"--smoke-test":
				options.smoke_test = true
	return options
