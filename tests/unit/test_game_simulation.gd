extends GutTest
## Plays many complete games with random (and often invalid) player input, including
## disconnects, and checks the rules' invariants after every step.

const GAMES: int = 150
const TEMPLATES: Array[String] = ["sad_clown", "office_fire", "cat_stare", "!!bad!!"]


func _make_match(player_count: int, rng: RandomNumberGenerator) -> GameMatch:
	var players: Array[LobbyPlayer] = []
	for i: int in range(player_count):
		players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
	var deck := PromptDeck.new(PackedStringArray(["a", "b", "c", "d"]), rng)
	return GameMatch.new(GameConfig.new(), players, deck, rng)


func _random_intents(game: GameMatch, rng: RandomNumberGenerator, player_count: int, now: float) -> void:
	for i: int in range(rng.randi_range(0, 6)):
		var actor: int = rng.randi_range(0, player_count + 1)  # Includes ids that don't exist.
		match rng.randi_range(0, 3):
			0:
				game.submit_meme(actor, {"template_id": TEMPLATES[rng.randi_range(0, TEMPLATES.size() - 1)], "top_text": "hi"}, now)
			1:
				game.cast_vote(actor, rng.randi_range(-2, 2), now)
			2:
				game.shoot(actor, now)
			3:
				# The host moves on, sometimes from a stale or nonsense index.
				var index: int = game.current_spotlight_index() + rng.randi_range(-1, 1)
				game.present_next(index if rng.randf() < 0.9 else "next", now)


func _check_invariants(game: GameMatch, player_count: int, bullets_at_start: int) -> void:
	var bullets_left: int = 0
	for id: int in range(1, player_count + 1):
		var player: PlayerState = game.get_player(id)
		assert_true(player.bullets >= 0, "bullets never go negative")
		bullets_left += player.bullets
	assert_true(bullets_left <= bullets_at_start)
	if game.phase == GameMatch.Phase.SPOTLIGHT:
		assert_true(game.get_player(game.current_spotlight_id()).is_alive(), "only living players are spotlighted")


func test_random_games_always_finish_correctly() -> void:
	var rng := RandomNumberGenerator.new()
	for game_index: int in range(GAMES):
		rng.seed = game_index
		var player_count: int = rng.randi_range(3, 8)
		var game: GameMatch = _make_match(player_count, rng)
		var eliminations: Array[int] = []
		game.player_eliminated.connect(func(id: int, _reason: int) -> void: eliminations.append(id))
		var bullets_at_start: int = player_count * game.config.bullets_per_player
		var disconnects: int = 0

		var now: float = 0.0
		game.start(now)
		var steps: int = 0
		while game.phase != GameMatch.Phase.GAME_OVER and steps < 5000:
			_random_intents(game, rng, player_count, now)
			if rng.randf() < 0.004:
				game.remove_player(rng.randi_range(1, player_count), now)
				disconnects += 1
			now += rng.randf_range(0.2, 4.0)
			game.update(now)
			_check_invariants(game, player_count, bullets_at_start)
			steps += 1

		assert_eq(game.phase, GameMatch.Phase.GAME_OVER, "game %d did not finish" % game_index)
		var survivors: Array[int] = game.living_ids()
		assert_true(survivors.size() <= 1, "game %d ended with %d survivors" % [game_index, survivors.size()])
		if survivors.size() == 1:
			assert_eq(game.winner_id, survivors[0])
		else:
			assert_eq(game.winner_id, 0)
		# Without disconnects, exactly one player dies per round.
		if disconnects == 0:
			assert_eq(eliminations.size(), player_count - 1, "game %d" % game_index)
			assert_eq(game.round_number, player_count - 1, "game %d" % game_index)
		var unique: Dictionary = {}
		for id: int in eliminations:
			unique[id] = true
		assert_eq(unique.size(), eliminations.size(), "nobody dies twice (game %d)" % game_index)
