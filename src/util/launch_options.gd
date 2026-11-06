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
##   --smoke-test=game    the same, but only once a whole game has been played to the end
##   --auto-play          a bot plays for you: submits memes, votes and sometimes shoots (dev)
##   --fast-rounds        (host) very short phases, for automated full games (debug builds only)
##   --seed=<n>           (host) fixed seed for prompts, spotlight order and tie-breaks
##   --offline-templates  (host) only our original templates; don't fetch popular ones
##   --room-preview=<n>   open the 3D room directly with n fake players, no network (dev)
##   --room-camera=<view> first room camera: seat (default), tv, overview, or editor
##                        (starts zoomed into your CRT's meme editor)

var host: bool = false
var join_target: String = ""
var player_name: String = ""
var port: int = Protocol.DEFAULT_PORT
var auto_ready: bool = false
var auto_start: bool = false
## 0 means "not set".
var min_players: int = 0
var smoke_test: bool = false
## With --smoke-test=game: pass only after GAME_OVER instead of at the start.
var smoke_test_full_game: bool = false
var auto_play: bool = false
var fast_rounds: bool = false
## 0 means "random".
var seed_value: int = 0
var offline_templates: bool = false
## 0 means "not set"; otherwise the number of fake players in the room preview.
var room_preview: int = 0
## "" (seat), "seat", "tv", "overview" or "editor".
var room_camera: String = ""

const ROOM_CAMERAS: PackedStringArray = ["seat", "tv", "overview", "editor"]


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
				options.smoke_test_full_game = value == "game"
			"--auto-play":
				options.auto_play = true
			"--fast-rounds":
				options.fast_rounds = true
			"--offline-templates":
				options.offline_templates = true
			"--seed":
				if value.is_valid_int():
					options.seed_value = value.to_int()
			"--room-preview":
				if value.is_valid_int():
					options.room_preview = clampi(value.to_int(), 1, Protocol.MAX_PLAYERS)
			"--room-camera":
				if value in ROOM_CAMERAS:
					options.room_camera = value
	return options
