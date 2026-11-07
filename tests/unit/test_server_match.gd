extends GutTest
## ServerController's match wiring: starting the match, intents, per-peer snapshots,
## disconnects mid-game and going back to the lobby.

const MEME: Dictionary = {"template_id": "sad_clown", "top_text": "top", "bottom_text": "bottom"}

var server: ServerController


func before_each() -> void:
	server = ServerController.new(3, 4)
	server.rng_seed = 42
	server.config.host_paces_spotlight = false  # most tests run the spotlight on its timer
	server.allowed_templates = PackedStringArray(["sad_clown"])
	for id: int in [1, 2, 3]:
		server.handle_peer_connected(id, 0.0)
		server.handle_join_request(id, "P%d" % id, Protocol.VERSION)
	server.handle_set_ready(2, true)
	server.handle_set_ready(3, true)
	watch_signals(server)


func _start() -> void:
	server.handle_start_request(1, 0.0)
	server.flush()


## Runs the clock until the match reaches [param phase].
func _run_to(phase: GameMatch.Phase) -> void:
	var guard: int = 0
	while server.game_match.phase != phase and guard < 100:
		server.update(server.game_match.phase_ends_at)
		guard += 1
	assert_eq(server.game_match.phase, phase)


func test_start_creates_a_running_match() -> void:
	_start()
	assert_not_null(server.game_match)
	assert_eq(server.game_match.phase, GameMatch.Phase.PROMPT)
	assert_signal_emitted(server, "game_started")
	assert_signal_emit_count(server, "match_changed", 1)


func test_only_the_host_can_start() -> void:
	server.handle_start_request(2, 0.0)
	assert_null(server.game_match)
	assert_signal_not_emitted(server, "game_started")


func test_flush_only_emits_after_a_change() -> void:
	_start()
	server.flush()
	assert_signal_emit_count(server, "match_changed", 1)
	server.update(server.game_match.phase_ends_at)  # PROMPT -> CREATE
	server.flush()
	assert_signal_emit_count(server, "match_changed", 2)


func test_intents_before_the_match_are_wrong_phase() -> void:
	assert_eq(server.handle_submit_meme(2, MEME, 0.0), GameMatch.IntentResult.WRONG_PHASE)
	assert_eq(server.handle_vote(2, 1, 0.0), GameMatch.IntentResult.WRONG_PHASE)
	assert_eq(server.handle_shoot(2, 0.0), GameMatch.IntentResult.WRONG_PHASE)
	assert_eq(server.snapshot_for(2, 0.0), {})


func test_submissions_are_validated_and_mark_dirty() -> void:
	_start()
	_run_to(GameMatch.Phase.CREATE)
	server.flush()
	var before: int = get_signal_emit_count(server, "match_changed")
	assert_eq(server.handle_submit_meme(2, {"template_id": "not_allowed"}, 6.0), GameMatch.IntentResult.INVALID)
	server.flush()
	assert_signal_emit_count(server, "match_changed", before)
	assert_eq(server.handle_submit_meme(2, MEME, 6.0), GameMatch.IntentResult.OK)
	server.flush()
	assert_signal_emit_count(server, "match_changed", before + 1)


func test_snapshots_hide_other_players_memes() -> void:
	_start()
	_run_to(GameMatch.Phase.CREATE)
	server.handle_submit_meme(2, MEME, 6.0)
	var own: Dictionary = server.snapshot_for(2, 6.0)
	var other: Dictionary = server.snapshot_for(3, 6.0)
	assert_eq(own["my_meme"]["top_text"], "top")
	assert_eq(other["my_meme"], {})
	assert_eq(other["submitted"], [2])
	assert_false(var_to_str(other).contains("\"top\""), "another player's caption leaked")


func test_votes_and_shots_reach_the_snapshot() -> void:
	_start()
	_run_to(GameMatch.Phase.CREATE)
	for id: int in [1, 2, 3]:
		server.handle_submit_meme(id, MEME, 6.0)
	assert_eq(server.game_match.phase, GameMatch.Phase.SPOTLIGHT)
	var target: int = server.game_match.current_spotlight_id()
	var judge: int = 1 if target != 1 else 2
	assert_eq(server.handle_vote(judge, -1, 6.0), GameMatch.IntentResult.OK)
	assert_eq(server.handle_vote(judge, "down", 6.0), GameMatch.IntentResult.INVALID)
	assert_eq(server.handle_shoot(judge, 6.0), GameMatch.IntentResult.OK)
	assert_eq(server.handle_shoot(judge, 6.0), GameMatch.IntentResult.ALREADY_DONE)
	var view := MatchView.from_snapshot(server.snapshot_for(judge, 6.0), 0.0)
	assert_eq(view.my_vote, -1)
	assert_eq(view.shooters, [judge] as Array[int])
	assert_eq(view.get_player(judge).bullets, server.config.bullets_per_player - 1)


func test_disconnect_mid_game_removes_the_player_from_the_match() -> void:
	_start()
	server.handle_peer_disconnected(3, 1.0)
	assert_eq(server.game_match.get_player(3).status, PlayerState.Status.LEFT)
	assert_false(server.lobby.has_player(3))


func test_only_the_host_presents_the_next_meme() -> void:
	server.config.host_paces_spotlight = true
	_start()
	_run_to(GameMatch.Phase.CREATE)
	for id: int in [1, 2, 3]:
		server.handle_submit_meme(id, MEME, 1.0)
	assert_eq(server.game_match.phase, GameMatch.Phase.SPOTLIGHT)
	var first: int = server.game_match.current_spotlight_id()
	server.update(10000.0)
	assert_eq(server.game_match.current_spotlight_id(), first, "no timer: the meme stays up")
	assert_eq(server.snapshot_for(2, 10000.0)["time_left"], -1.0)
	assert_eq(server.handle_present_next(2, 0, 10000.0), GameMatch.IntentResult.NOT_ALLOWED)
	assert_eq(server.game_match.current_spotlight_id(), first)
	server.flush()
	assert_eq(server.handle_present_next(1, 0, 10000.0), GameMatch.IntentResult.OK)
	assert_ne(server.game_match.current_spotlight_id(), first)
	server.flush()
	assert_signal_emit_count(server, "match_changed", 3, "start, the memes, the next spotlight")


func test_return_to_lobby_only_after_game_over_and_only_by_host() -> void:
	_start()
	server.handle_return_to_lobby(1)
	assert_signal_not_emitted(server, "returned_to_lobby")
	server.handle_peer_disconnected(2, 1.0)
	server.handle_peer_disconnected(3, 1.0)
	assert_true(server.is_match_over())
	server.handle_return_to_lobby(2)
	assert_signal_not_emitted(server, "returned_to_lobby")
	server.handle_return_to_lobby(1)
	assert_signal_emitted(server, "returned_to_lobby")
	assert_null(server.game_match)
	assert_false(server.lobby.started)


func test_returning_to_lobby_clears_ready_flags() -> void:
	# Play a whole seeded game where nobody submits; someone dies every round.
	_start()
	var guard: int = 0
	while not server.is_match_over() and guard < 200:
		server.update(server.game_match.phase_ends_at)
		guard += 1
	assert_true(server.is_match_over())
	server.handle_return_to_lobby(1)
	for player: LobbyPlayer in server.lobby.get_players():
		assert_false(player.ready, "%s still ready" % player.name)
	assert_true(server.lobby.has_player(2) and server.lobby.has_player(3))
