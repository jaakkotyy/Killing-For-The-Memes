extends GutTest
## MatchView: parsing snapshots (including hostile ones) and the client-side rules helpers.


func _players() -> Array:
	return [
		{"id": 1, "name": "Ann", "seat": 0, "bullets": 2, "status": PlayerState.Status.ALIVE},
		{"id": 2, "name": "Bob", "seat": 1, "bullets": 0, "status": PlayerState.Status.ALIVE},
		{"id": 3, "name": "Cid", "seat": 2, "bullets": 1, "status": PlayerState.Status.ELIMINATED, "out_in_round": 1},
		{"id": 4, "name": "Dee", "seat": 3, "bullets": 2, "status": PlayerState.Status.ALIVE},
	]


func _spotlight_view(target: int = 4, shooters: Array = []) -> MatchView:
	return MatchView.from_snapshot({
		"phase": GameMatch.Phase.SPOTLIGHT,
		"round": 2,
		"prompt": "p",
		"time_left": 10.0,
		"players": _players(),
		"submitted": [1, 4],
		"spotlight": {"player_id": target, "meme": {"template_id": "sad_clown", "top_text": "hi"},
			"shooters": shooters, "index": 1, "count": 3},
		"my_vote": 1,
	}, 5.0)


func test_parses_a_real_snapshot() -> void:
	var players: Array[LobbyPlayer] = []
	for i: int in range(3):
		players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var game := GameMatch.new(GameConfig.new(), players, PromptDeck.new(PackedStringArray(["a prompt"]), rng), rng)
	game.start(0.0)
	var view := MatchView.from_snapshot(game.to_snapshot(1.0, 2), 1.0)
	assert_eq(view.phase, GameMatch.Phase.PROMPT)
	assert_eq(view.round_number, 1)
	assert_eq(view.prompt, "a prompt")
	assert_eq(view.players.size(), 3)
	assert_almost_eq(view.time_left, GameConfig.new().prompt_duration - 1.0, 0.001)
	assert_null(view.my_meme)
	assert_eq(view.spotlight_id, 0)


func test_parses_spotlight_fields() -> void:
	var view: MatchView = _spotlight_view(4, [1])
	assert_eq(view.spotlight_id, 4)
	assert_eq(view.spotlight_meme.top_text, "hi")
	assert_eq(view.shooters, [1] as Array[int])
	assert_eq(view.spotlight_index, 1)
	assert_eq(view.spotlight_count, 3)
	assert_eq(view.my_vote, 1)
	assert_eq(view.submitted, [1, 4] as Array[int])


func test_garbage_snapshot_gives_a_safe_view() -> void:
	var view := MatchView.from_snapshot({
		"phase": 999, "players": ["nope", 3], "submitted": "x", "spotlight": [], "my_vote": 7,
		"elimination": "dead", "time_left": -5.0,
	}, 0.0)
	assert_eq(view.phase, GameMatch.Phase.size() - 1)
	assert_eq(view.players.size(), 0)
	assert_eq(view.submitted.size(), 0)
	assert_eq(view.spotlight_id, 0)
	assert_eq(view.my_vote, 1)
	assert_eq(view.time_left, 0.0)
	assert_eq(view.player_name(42), "?")


func test_time_left_counts_down_locally() -> void:
	var view: MatchView = _spotlight_view()
	assert_almost_eq(view.time_left_at(5.0), 10.0, 0.001)
	assert_almost_eq(view.time_left_at(8.5), 6.5, 0.001)
	assert_eq(view.time_left_at(100.0), 0.0)


func test_vote_and_shoot_rules_match_the_server() -> void:
	var view: MatchView = _spotlight_view(4, [1])
	assert_false(view.can_vote(4, true), "the spotlight player votes on themself")
	assert_true(view.can_vote(1, true))
	assert_true(view.can_vote(3, true), "eliminated players vote in the MVP")
	assert_false(view.can_vote(3, false))
	assert_false(view.can_shoot(1), "already shot")
	assert_false(view.can_shoot(2), "no bullets")
	assert_false(view.can_shoot(3), "dead players never shoot")
	assert_false(view.can_shoot(4), "can't shoot yourself")
	view.shooters.clear()
	assert_true(view.can_shoot(1))


func test_nothing_is_allowed_outside_a_spotlight() -> void:
	var view: MatchView = _spotlight_view()
	view.phase = GameMatch.Phase.CREATE
	assert_false(view.can_vote(1, true))
	assert_false(view.can_shoot(1))


func test_standings_put_the_living_first_then_the_latest_dead() -> void:
	var players: Array = _players()
	players[1]["status"] = PlayerState.Status.ELIMINATED
	players[1]["out_in_round"] = 2
	players[3]["status"] = PlayerState.Status.LEFT
	players[3]["out_in_round"] = 3
	var view := MatchView.from_snapshot({"phase": GameMatch.Phase.GAME_OVER, "players": players, "winner_id": 1}, 0.0)
	var order: Array[int] = []
	for player: PlayerState in view.standings():
		order.append(player.id)
	assert_eq(order, [1, 4, 2, 3] as Array[int])
	assert_eq(view.living_ids(), [1] as Array[int])
