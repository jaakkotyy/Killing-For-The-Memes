extends GutTest
## The server side of a game: the host picks the identity pack in the lobby,
## ServerController runs a GuessMatch, routes its intents and sends per-peer snapshots;
## plus the lobby, launch flags and pack lookup that carry the choice.

var server: ServerController


func before_each() -> void:
	server = ServerController.new(3, 4)
	server.rng_seed = 42
	for id: int in [1, 2, 3]:
		server.handle_peer_connected(id, 0.0)
		server.handle_join_request(id, "P%d" % id, Protocol.VERSION)
	server.handle_set_ready(2, true)
	server.handle_set_ready(3, true)
	watch_signals(server)


func _start(pack: String = "movies") -> void:
	server.handle_set_pack(1, pack)
	server.handle_start_request(1, 0.0)
	server.flush()


# --- Choosing the pack --------------------------------------------------------------------

func test_lobby_starts_with_the_default_pack() -> void:
	assert_eq(server.lobby.pack, "musicians")


func test_only_the_host_picks_and_only_real_packs() -> void:
	server.handle_set_pack(2, "movies")
	assert_eq(server.lobby.pack, "musicians", "guests can't")
	server.handle_set_pack(1, "../secrets")
	server.handle_set_pack(1, "nope")
	server.handle_set_pack(1, 4)
	assert_eq(server.lobby.pack, "musicians")
	assert_signal_not_emitted(server, "lobby_changed")
	server.handle_set_pack(1, "movies")
	assert_eq(server.lobby.pack, "movies")
	assert_signal_emitted(server, "lobby_changed")
	var snapshot: Dictionary = get_signal_parameters(server, "lobby_changed")[0]
	assert_eq(snapshot["pack"], "movies", "everyone sees the choice")


func test_the_pack_is_locked_once_the_game_starts() -> void:
	_start()
	server.handle_set_pack(1, "musicians")
	assert_eq(server.lobby.pack, "movies")


# --- Running a game -----------------------------------------------------------------------

func test_starting_creates_a_guess_match() -> void:
	_start()
	assert_signal_emitted(server, "game_started")
	assert_not_null(server.guess_match)
	assert_eq(server.guess_match.pack.id, "movies")
	assert_signal_emitted(server, "match_changed")
	var snapshot: Dictionary = server.snapshot_for(2, 0.0)
	assert_eq(snapshot["mode"], "guess")
	assert_false((snapshot["identities"] as Dictionary).has("2"), "per-peer: your own is hidden")
	assert_true((snapshot["identities"] as Dictionary).has("3"))


func test_intents_are_routed_and_mark_the_match_dirty() -> void:
	assert_eq(server.handle_ask(1, {"text": "early"}, 0.0), Intent.Result.WRONG_PHASE, "no game yet")
	_start()
	var now: float = server.config.deal_duration
	server.update(now)
	server.flush()
	watch_signals(server)
	var asker: int = server.guess_match.asker_id()
	assert_eq(server.handle_ask(asker, {"stock": 0}, now), Intent.Result.OK)
	server.flush()
	assert_signal_emitted(server, "match_changed")
	var answerer: int = 2 if asker != 2 else 3
	assert_eq(server.handle_answer(answerer, GuessMatch.Answer.YES, now), Intent.Result.OK)
	assert_eq(server.handle_guess(answerer, server.guess_match.identity_of(answerer), now), Intent.Result.OK)
	assert_true(server.guess_match.is_solved(answerer))
	assert_eq(server.handle_guess(answerer, "Q1", now), Intent.Result.NOT_ALLOWED)


func test_disconnects_reach_the_match() -> void:
	_start()
	server.handle_peer_disconnected(3, 1.0)
	assert_eq(server.guess_match.get_player(3).status, PlayerState.Status.LEFT)


func test_back_to_the_lobby_after_a_game() -> void:
	server.config.guess_rounds = 1
	_start()
	server.handle_return_to_lobby(1)
	assert_not_null(server.guess_match, "not before the game is over")
	var now: float = 0.0
	while not server.is_match_over() and now < 2000.0:
		now += 1.0
		server.update(now)
	assert_true(server.is_match_over())
	server.handle_return_to_lobby(2)
	assert_not_null(server.guess_match, "only the host")
	server.handle_return_to_lobby(1)
	assert_null(server.guess_match)
	assert_false(server.lobby.started)
	assert_eq(server.lobby.pack, "movies", "the next game uses the same pack")


# --- Lobby, flags and packs ---------------------------------------------------------------

func test_lobby_snapshots_carry_the_pack() -> void:
	var lobby := LobbyState.new()
	lobby.pack = "movies"
	var copy: LobbyState = LobbyState.from_dict(lobby.to_dict())
	assert_eq(copy.pack, "movies")
	assert_eq(LobbyState.from_dict({}).pack, "musicians")


func test_pack_flag() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--pack=movies"])).pack, "movies")
	assert_eq(LaunchOptions.parse(PackedStringArray(["--pack=../x"])).pack, "")


func test_shipped_packs_are_found_and_loaded_once() -> void:
	assert_true(IdentityPack.available_ids().has("movies"))
	assert_true(IdentityPack.available_ids().has("musicians"))
	assert_true(IdentityPack.exists("movies"))
	assert_false(IdentityPack.exists("../movies"))
	assert_false(IdentityPack.exists(7))
	assert_same(IdentityPack.load_pack("movies"), IdentityPack.load_pack("movies"))
	assert_null(IdentityPack.load_pack("nope"))
	assert_eq(IdentityPack.display_name("movies"), "Movies")
