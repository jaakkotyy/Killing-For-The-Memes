extends GutTest
## The rules (GuessMatch) and the client's view of them (GuessView).

const Phase := GuessMatch.Phase
const Result := Intent.Result
const YES: int = GuessMatch.Answer.YES
const NO: int = GuessMatch.Answer.NO
const UNSURE: int = GuessMatch.Answer.UNSURE

var pack: IdentityPack
var config: GameConfig
var game: GuessMatch


func _make_pack(count: int) -> IdentityPack:
	var entries: Array = []
	for i: int in range(count):
		entries.append({"id": "E%d" % i, "name": "Entry %d" % i, "fame": 100 - i,
			"fields": {"kind": "band" if i % 2 == 0 else "solo artist", "born": 1950 + i}})
	return IdentityPack.from_dict({
		"id": "test", "name": "Test",
		"fields": [{"id": "kind", "type": "enum"}, {"id": "born", "type": "year"}],
		"questions": [{"text": "Am I a band?", "filter": {"field": "kind", "op": "is", "value": "band"}}],
		"entries": entries,
	})


func _make_game(player_count: int, seed_value: int = 1) -> GuessMatch:
	var players: Array[LobbyPlayer] = []
	for i: int in range(player_count):
		players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GuessMatch.new(config, players, pack, rng)


func before_each() -> void:
	pack = _make_pack(30)
	config = GameConfig.new()
	game = _make_game(4)
	game.start(0.0)


## Ends the deal: the first turn starts at t = deal_duration.
func _to_turns() -> float:
	game.update(config.deal_duration)
	return config.deal_duration


## Lets time pass, a second at a time, until the next round is dealt or the game is over.
## (One big jump would start the round clock at the jump's end, like any phase timer.)
func _play_out_round(now: float) -> float:
	var round_number: int = game.round_number
	while game.round_number == round_number and game.phase != Phase.GAME_OVER:
		now += 1.0
		game.update(now)
	return now


## Someone's wrong answer: any pack entry that isn't their identity.
func _wrong_entry(player_id: int) -> String:
	for entry: IdentityPack.Entry in pack.entries():
		if entry.id != game.identity_of(player_id):
			return entry.id
	return ""


## The asker asks and everyone else answers [param value]; returns the time afterwards.
func _ask_and_answer(now: float, value: int) -> float:
	var asker: int = game.asker_id()
	assert_eq(game.ask(asker, {"text": "Am I tall?"}, now), Result.OK)
	for player_id: int in game.present_ids():
		if player_id != asker:
			game.answer(player_id, value, now)
	return now


# --- Deal ---------------------------------------------------------------------------------

func test_everyone_gets_a_different_identity() -> void:
	assert_eq(game.phase, Phase.DEAL)
	var seen: Dictionary = {}
	for player_id: int in game.present_ids():
		var identity: String = game.identity_of(player_id)
		assert_true(pack.has_entry(identity))
		assert_false(seen.has(identity), "dealt twice")
		seen[identity] = true


func test_snapshot_hides_your_own_identity_only() -> void:
	var snapshot: Dictionary = game.to_snapshot(0.0, 2)
	var identities: Dictionary = snapshot["identities"]
	assert_false(identities.has("2"), "you can't see your own")
	for other: String in ["1", "3", "4"]:
		assert_eq(identities[other], game.identity_of(int(other)))
	assert_eq(snapshot["mode"], "guess")


func test_no_identity_comes_back_in_a_later_round() -> void:
	config.guess_rounds = 3
	var seen: Dictionary = {}
	var now: float = 0.0
	for round_index: int in range(3):
		assert_eq(game.round_number, round_index + 1)
		for player_id: int in game.present_ids():
			assert_false(seen.has(game.identity_of(player_id)), "round %d repeats an identity" % (round_index + 1))
			seen[game.identity_of(player_id)] = true
		now = _play_out_round(now)
	assert_eq(game.phase, Phase.GAME_OVER)


# --- Turns and questions ------------------------------------------------------------------

func test_turns_go_round_the_table_by_seat() -> void:
	var now: float = _to_turns()
	assert_eq(game.phase, Phase.ASK)
	assert_eq(game.asker_id(), 1)
	now += config.ask_duration
	game.update(now)
	assert_eq(game.asker_id(), 2, "running out of time passes the turn")
	now = _ask_and_answer(now, YES)
	assert_eq(game.phase, Phase.RESULT, "everyone answered, so the question closed early")
	now += config.result_duration
	game.update(now)
	assert_eq(game.asker_id(), 3)


func test_a_different_player_opens_each_round() -> void:
	_to_turns()
	assert_eq(game.asker_id(), 1)
	game.update(10000.0)  # round clock runs out
	assert_eq(game.phase, Phase.REVEAL)
	game.update(20000.0)  # reveal ends, next deal
	assert_eq(game.round_number, 2)
	game.update(30000.0)
	assert_eq(game.asker_id(), 2)


func test_only_the_asker_asks_and_only_valid_questions() -> void:
	assert_eq(game.ask(1, {"text": "early"}, 0.0), Result.WRONG_PHASE)
	var now: float = _to_turns()
	assert_eq(game.ask(2, {"text": "not my turn"}, now), Result.NOT_ALLOWED)
	assert_eq(game.ask(1, "Am I tall?", now), Result.INVALID)
	assert_eq(game.ask(1, {"text": "   "}, now), Result.INVALID)
	assert_eq(game.ask(1, {"stock": 5}, now), Result.INVALID)
	assert_eq(game.ask(1, {"stock": "0"}, now), Result.INVALID)
	assert_eq(game.ask(1, {"stock": 0}, now), Result.OK)
	assert_eq(game.phase, Phase.ANSWER)
	var question: Dictionary = game.to_snapshot(now, 2)["question"]
	assert_eq(question["text"], "Am I a band?", "a stock question carries its text")
	assert_eq(question["stock"], 0)


func test_own_questions_are_cleaned() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "  Do I\nwear   a hat?  "}, now)
	assert_eq(game.to_snapshot(now, 2)["question"]["text"], "Do I wear a hat?")
	assert_eq(game.to_snapshot(now, 2)["question"]["stock"], -1)


func test_answers_are_checked() -> void:
	var now: float = _to_turns()
	assert_eq(game.answer(2, YES, now), Result.WRONG_PHASE)
	game.ask(1, {"text": "Am I tall?"}, now)
	assert_eq(game.answer(1, YES, now), Result.NOT_ALLOWED, "the asker can't answer")
	assert_eq(game.answer(2, 2, now), Result.INVALID)
	assert_eq(game.answer(2, "yes", now), Result.INVALID)
	assert_eq(game.answer(9, YES, now), Result.NOT_ALLOWED)
	assert_eq(game.answer(2, YES, now), Result.OK)
	assert_eq(game.answer(2, NO, now), Result.OK, "answers can change")


func test_the_majority_decides_and_earns_points() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Am I tall?"}, now)
	game.answer(2, YES, now)
	game.answer(3, YES, now)
	game.answer(4, NO, now)
	assert_eq(game.phase, Phase.RESULT)
	var snapshot: Dictionary = game.to_snapshot(now, 1)
	assert_eq(snapshot["tally"]["answer"], YES)
	assert_eq(snapshot["tally"]["yes"], 2)
	assert_eq(snapshot["tally"]["no"], 1)
	assert_eq(game.get_score(2), config.answer_points)
	assert_eq(game.get_score(4), 0)
	assert_eq(snapshot["clues"]["1"], [{"text": "Am I tall?", "stock": -1, "answer": YES}])


func test_ties_and_unsure_answers_are_unclear() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.answer(2, YES, now)
	game.answer(3, NO, now)
	game.answer(4, UNSURE, now)
	assert_eq(game.to_snapshot(now, 1)["tally"]["answer"], UNSURE)
	assert_eq(game.get_score(2), 0, "no points without a majority")


func test_answering_time_runs_out() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.answer(2, NO, now)
	game.update(now + config.answer_duration)
	assert_eq(game.phase, Phase.RESULT)
	assert_eq(game.to_snapshot(now, 1)["tally"]["answer"], NO, "one No and two silent is a No")


func test_nobody_sees_who_answered_what_until_the_result() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.answer(2, YES, now)
	var for_asker: Dictionary = game.to_snapshot(now, 1)
	assert_eq(for_asker["tally"], {"answered": 1, "answerers": 3})
	assert_eq(game.to_snapshot(now, 2)["my_answer"], YES)
	assert_true(game.to_snapshot(now, 2)["my_answered"])
	assert_false(game.to_snapshot(now, 3)["my_answered"])


# --- Guesses ------------------------------------------------------------------------------

func test_guessing_only_during_the_turns() -> void:
	assert_eq(game.guess(1, game.identity_of(1), 0.0), Result.WRONG_PHASE)
	var now: float = _to_turns()
	assert_eq(game.guess(1, "nope", now), Result.INVALID)
	assert_eq(game.guess(1, 3, now), Result.INVALID)
	assert_eq(game.guess(9, game.identity_of(1), now), Result.NOT_ALLOWED)


func test_a_right_guess_scores_less_for_every_question() -> void:
	var now: float = _to_turns()
	_ask_and_answer(now, YES)  # player 1 asked once
	assert_eq(game.guess(1, game.identity_of(1), now), Result.OK)
	assert_true(game.is_solved(1))
	assert_eq(game.get_score(1), config.solve_points - config.per_question_cost + config.first_bonus)
	assert_eq(game.guess(1, game.identity_of(1), now), Result.NOT_ALLOWED, "solved already")
	assert_eq(game.guess(2, game.identity_of(2), now), Result.OK)
	assert_eq(game.get_score(2), config.solve_points + config.answer_points, "no first bonus, no questions asked")
	assert_true((game.to_snapshot(now, 1)["identities"] as Dictionary).has("1"), "a solver sees their own")


func test_solving_never_scores_below_the_minimum() -> void:
	config.per_question_cost = 1000
	var now: float = _to_turns()
	_ask_and_answer(now, YES)
	game.guess(1, game.identity_of(1), now)
	assert_eq(game.get_score(1), config.solve_min + config.first_bonus)


func test_a_wrong_guess_costs_points_and_locks_until_your_turn() -> void:
	var now: float = _to_turns()  # player 1 asks
	assert_eq(game.guess(3, _wrong_entry(3), now), Result.OK)
	assert_eq(game.get_score(3), -config.wrong_guess_penalty)
	assert_eq(game.guess(3, game.identity_of(3), now), Result.ALREADY_DONE, "locked")
	now += config.ask_duration
	game.update(now)  # player 2's turn
	assert_eq(game.guess(3, game.identity_of(3), now), Result.ALREADY_DONE, "still locked")
	now += config.ask_duration
	game.update(now)  # player 3's turn lifts it
	assert_eq(game.asker_id(), 3)
	assert_eq(game.guess(3, game.identity_of(3), now), Result.OK)
	assert_false(game.is_solved(4))


func test_an_asker_who_solves_hands_the_turn_on() -> void:
	var now: float = _to_turns()
	game.guess(1, game.identity_of(1), now)
	assert_eq(game.phase, Phase.ASK)
	assert_eq(game.asker_id(), 2)


func test_solved_players_get_no_more_turns_but_still_answer() -> void:
	var now: float = _to_turns()
	game.guess(2, game.identity_of(2), now)
	now += config.ask_duration
	game.update(now)
	assert_eq(game.asker_id(), 3, "player 2 is skipped")
	game.ask(3, {"text": "Q"}, now)
	assert_eq(game.answer(2, YES, now), Result.OK)


# --- Round end and game over --------------------------------------------------------------

func test_the_round_ends_once_everyone_has_solved() -> void:
	var now: float = _to_turns()
	for player_id: int in [2, 3, 4, 1]:
		game.guess(player_id, game.identity_of(player_id), now)
	assert_eq(game.phase, Phase.REVEAL)
	var snapshot: Dictionary = game.to_snapshot(now, 2)
	assert_eq((snapshot["identities"] as Dictionary).size(), 4, "everything is revealed")
	assert_eq(snapshot["solved"], [2, 3, 4, 1])


func test_the_round_clock_ends_the_round_whatever_the_phase() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.update(now + config.round_duration)
	assert_eq(game.phase, Phase.REVEAL)
	assert_eq(game.asker_id(), 0)
	assert_eq(game.guess(1, game.identity_of(1), now + config.round_duration), Result.WRONG_PHASE)


func test_round_points_reset_but_scores_add_up() -> void:
	var now: float = _to_turns()
	game.guess(2, game.identity_of(2), now)
	game.update(now + config.round_duration)  # reveal
	var points: int = game.get_score(2)
	now += config.round_duration + config.reveal_duration
	game.update(now)
	assert_eq(game.round_number, 2)
	var mine: Dictionary = (game.to_snapshot(now, 2)["players"] as Array)[1]
	assert_eq(mine["round_points"], 0)
	assert_eq(mine["score"], points)


func test_most_points_wins_and_ties_share() -> void:
	config.guess_rounds = 1
	var now: float = _to_turns()
	game.guess(3, game.identity_of(3), now)
	game.update(now + config.round_duration)
	game.update(now + config.round_duration + config.reveal_duration)
	assert_eq(game.phase, Phase.GAME_OVER)
	assert_eq(game.winner_ids(), [3] as Array[int])

	game = _make_game(3)
	game.start(0.0)
	var now_2: float = 0.0
	for _round: int in range(config.guess_rounds):
		now_2 = _play_out_round(now_2)
	assert_eq(game.phase, Phase.GAME_OVER)
	assert_eq(game.winner_ids(), [1, 2, 3] as Array[int], "nobody scored: everyone shares")


# --- Disconnects --------------------------------------------------------------------------

func test_the_asker_leaving_passes_the_turn() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.remove_player(1, now)
	assert_eq(game.phase, Phase.ASK)
	assert_eq(game.asker_id(), 2)


func test_the_last_missing_answer_leaving_closes_the_question() -> void:
	var now: float = _to_turns()
	game.ask(1, {"text": "Q"}, now)
	game.answer(2, YES, now)
	game.answer(3, YES, now)
	game.remove_player(4, now)
	assert_eq(game.phase, Phase.RESULT)


func test_the_last_unsolved_player_leaving_ends_the_round() -> void:
	var now: float = _to_turns()
	for player_id: int in [1, 2, 3]:
		game.guess(player_id, game.identity_of(player_id), now)
	game.remove_player(4, now)
	assert_eq(game.phase, Phase.REVEAL)


func test_one_player_left_ends_the_game() -> void:
	game.remove_player(2, 0.0)
	game.remove_player(3, 0.0)
	game.remove_player(4, 0.0)
	assert_eq(game.phase, Phase.GAME_OVER)
	assert_eq(game.winner_ids(), [1] as Array[int])


# --- GuessView ----------------------------------------------------------------------------

func test_view_reads_a_snapshot_and_knows_the_rules() -> void:
	var now: float = _to_turns()
	game.ask(1, {"stock": 0}, now)
	game.answer(3, NO, now)
	var view := GuessView.from_snapshot(game.to_snapshot(now, 2), 50.0)
	assert_eq(view.phase, Phase.ANSWER)
	assert_eq(view.pack_id, "test")
	assert_eq(view.asker_id, 1)
	assert_eq(view.question_text, "Am I a band?")
	assert_eq(view.question_stock, 0)
	assert_eq(view.answered, 1)
	assert_eq(view.identity_of(2), "", "the view never knows your own")
	assert_eq(view.identity_of(3), game.identity_of(3))
	assert_true(view.can_answer(2))
	assert_false(view.can_answer(1))
	assert_false(view.can_ask(2))
	assert_true(view.can_guess(2))
	assert_almost_eq(view.time_left_at(52.0), config.answer_duration - 2.0, 0.001)
	assert_almost_eq(view.round_time_left_at(50.0), config.round_duration, 0.001)


func test_view_standings_and_locks() -> void:
	var now: float = _to_turns()
	game.guess(4, game.identity_of(4), now)
	game.guess(2, _wrong_entry(2), now)
	var view := GuessView.from_snapshot(game.to_snapshot(now, 1), 0.0)
	assert_eq(view.standings()[0].id, 4)
	assert_eq(view.standings()[3].id, 2)
	assert_true(view.locked.has(2))
	assert_false(view.can_guess(2))
	assert_false(view.can_guess(4), "solved")
	assert_eq(view.solved, [4] as Array[int])
	assert_eq(view.wrong_guesses[2], 1)


func test_view_survives_garbage() -> void:
	var view := GuessView.from_snapshot({"phase": 99, "players": "x", "identities": [1], "clues": {"1": "x"}, "solved": ["a", 2]}, 0.0)
	assert_eq(view.phase, Phase.GAME_OVER)
	assert_true(view.players.is_empty())
	assert_eq(view.solved, [2] as Array[int])
