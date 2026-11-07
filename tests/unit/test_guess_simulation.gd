extends GutTest
## Plays many complete guess-mode games with random (and often invalid) input, including
## disconnects, and checks the rules' invariants after every step.

const GAMES: int = 120

var _pack: IdentityPack


func before_all() -> void:
	var entries: Array = []
	for i: int in range(40):
		entries.append({"id": "E%d" % i, "name": "Entry %d" % i, "fame": 40 - i, "fields": {"born": 1900 + i}})
	_pack = IdentityPack.from_dict({
		"id": "sim", "fields": [{"id": "born", "type": "year"}],
		"questions": [{"text": "Old?", "filter": {"field": "born", "op": "before", "value": 1920}}],
		"entries": entries,
	})


func _random_intents(game: GuessMatch, rng: RandomNumberGenerator, player_count: int, now: float) -> void:
	for i: int in range(rng.randi_range(0, 5)):
		var actor: int = rng.randi_range(0, player_count + 1)  # includes ids that don't exist
		match rng.randi_range(0, 3):
			0:
				var question: Variant = [{"text": "Am I %d?" % i}, {"stock": rng.randi_range(-1, 2)}, "junk", {"text": ""}][rng.randi_range(0, 3)]
				game.ask(game.asker_id() if rng.randf() < 0.7 else actor, question, now)
			1:
				game.answer(actor, rng.randi_range(-2, 2), now)
			2, 3:
				# Mostly sensible guesses: the right one, a random entry, or nonsense.
				var target: Variant = "E%d" % rng.randi_range(0, 45)
				if rng.randf() < 0.15:
					target = game.identity_of(actor)
				elif rng.randf() < 0.05:
					target = 7
				game.guess(actor, target, now)


func _check_invariants(game: GuessMatch, player_count: int, now: float) -> void:
	var dealt: Dictionary = {}
	for id: int in range(1, player_count + 1):
		var identity: String = game.identity_of(id)
		if identity.is_empty():
			continue
		assert_false(dealt.has(identity), "two players share an identity")
		dealt[identity] = true
		if game.phase == GuessMatch.Phase.ASK or game.phase == GuessMatch.Phase.ANSWER:
			var own: Dictionary = game.to_snapshot(now, id)["identities"]
			assert_eq(own.has(str(id)), game.is_solved(id), "only a solver sees their own identity")
	# An asker who leaves during RESULT stays named until their answer leaves the wall TV.
	if game.asker_id() != 0 and game.phase != GuessMatch.Phase.RESULT:
		assert_true(game.get_player(game.asker_id()).is_present(), "the asker is connected")
		assert_false(game.is_solved(game.asker_id()) and game.phase == GuessMatch.Phase.ASK, "solved players don't ask")


func test_random_games_always_finish_correctly() -> void:
	var rng := RandomNumberGenerator.new()
	var outcomes: Dictionary = {true: 0, false: 0}  # right / wrong guesses over all games
	for game_index: int in range(GAMES):
		rng.seed = game_index
		var player_count: int = rng.randi_range(2, 8)
		var config := GameConfig.new()
		config.guess_rounds = rng.randi_range(1, 3)
		var players: Array[LobbyPlayer] = []
		for i: int in range(player_count):
			players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
		var game := GuessMatch.new(config, players, _pack, rng)
		game.guessed.connect(func(_id: int, correct: bool) -> void: outcomes[correct] += 1)
		var all_dealt: Dictionary = {}
		var disconnects: int = 0
		var now: float = 0.0
		game.start(now)
		var steps: int = 0
		while game.phase != GuessMatch.Phase.GAME_OVER and steps < 20000:
			if game.phase == GuessMatch.Phase.DEAL:
				for id: int in game.present_ids():
					var identity: String = game.identity_of(id)
					if not all_dealt.has(identity):
						all_dealt[identity] = game.round_number
					assert_eq(all_dealt[identity], game.round_number, "game %d deals an identity again" % game_index)
			_random_intents(game, rng, player_count, now)
			if rng.randf() < 0.003:
				game.remove_player(rng.randi_range(1, player_count), now)
				disconnects += 1
			now += rng.randf_range(0.2, 4.0)
			game.update(now)
			_check_invariants(game, player_count, now)
			steps += 1

		assert_eq(game.phase, GuessMatch.Phase.GAME_OVER, "game %d did not finish" % game_index)
		if disconnects == 0:
			assert_eq(game.round_number, config.guess_rounds, "game %d played every round" % game_index)
		var winners: Array[int] = game.winner_ids()
		if not game.present_ids().is_empty():
			assert_false(winners.is_empty(), "game %d has a winner" % game_index)
		for winner: int in winners:
			for other: int in game.present_ids():
				assert_true(game.get_score(winner) >= game.get_score(other), "game %d: winners have the best score" % game_index)
	assert_gt(outcomes[true], GAMES, "the bots solve plenty")
	assert_gt(outcomes[false], GAMES, "and guess wrong plenty")
