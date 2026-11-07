extends GutTest

const MEME: Dictionary = {"template_id": "sad_clown", "top_text": "top", "bottom_text": "bottom"}

var match_: GameMatch
var config: GameConfig


func _make_match(player_count: int, seed_value: int = 1, bullets: int = 2) -> GameMatch:
	var players: Array[LobbyPlayer] = []
	for i: int in range(player_count):
		players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	config = GameConfig.new()
	config.bullets_per_player = bullets
	config.host_paces_spotlight = false
	var deck := PromptDeck.new(PackedStringArray(["prompt one", "prompt two", "prompt three"]), rng)
	return GameMatch.new(config, players, deck, rng)


func before_each() -> void:
	match_ = _make_match(3)
	match_.start(0.0)


## Fast-forwards to the end of the current phase.
func _skip() -> void:
	match_.update(match_.phase_ends_at)


func _skip_to(target_phase: GameMatch.Phase) -> void:
	var guard: int = 0
	while match_.phase != target_phase and guard < 100:
		_skip()
		guard += 1
	assert_eq(match_.phase, target_phase, "never reached phase %s" % GameMatch.Phase.keys()[target_phase])


func _submit_all() -> void:
	for player_id: int in match_.living_ids():
		match_.submit_meme(player_id, MEME, match_.phase_ends_at - 1.0)


## Runs every spotlight of the round. Everyone who may vote downvotes [param victim] and
## upvotes everyone else.
func _vote_against(victim: int) -> void:
	while match_.phase == GameMatch.Phase.SPOTLIGHT:
		var target: int = match_.current_spotlight_id()
		for voter_id: int in [1, 2, 3, 4, 5, 6, 7, 8]:
			match_.cast_vote(voter_id, -1 if target == victim else 1, 0.0)
		_skip()


# --- Phase flow ---------------------------------------------------------------------------

func test_start_shows_a_prompt() -> void:
	assert_eq(match_.phase, GameMatch.Phase.PROMPT)
	assert_eq(match_.round_number, 1)
	assert_ne(match_.prompt, "")
	assert_eq(match_.to_snapshot(0.0, 1)["time_left"], config.prompt_duration)


func test_prompt_leads_to_create_then_spotlight_on_timer() -> void:
	_skip()
	assert_eq(match_.phase, GameMatch.Phase.CREATE)
	assert_eq(match_.phase_ends_at, config.prompt_duration + config.create_duration)
	_skip()
	assert_eq(match_.phase, GameMatch.Phase.SPOTLIGHT, "timer ends creation even if nobody submitted")


func test_create_ends_early_when_everyone_submitted() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 10.0)
	match_.submit_meme(2, MEME, 10.0)
	assert_eq(match_.phase, GameMatch.Phase.CREATE)
	match_.submit_meme(3, MEME, 10.0)
	assert_eq(match_.phase, GameMatch.Phase.SPOTLIGHT)
	assert_eq(match_.phase_ends_at, 10.0 + config.spotlight_duration)


func test_every_living_player_gets_exactly_one_spotlight() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	var seen: Array[int] = []
	while match_.phase == GameMatch.Phase.SPOTLIGHT:
		seen.append(match_.current_spotlight_id())
		_skip()
	seen.sort()
	assert_eq(seen, [1, 2, 3] as Array[int])
	assert_eq(match_.phase, GameMatch.Phase.ELIMINATION)


func test_a_stall_never_shortens_the_next_phase() -> void:
	# The server hitched for 3 s past the end of the prompt.
	match_.update(config.prompt_duration + 3.0)
	assert_eq(match_.phase, GameMatch.Phase.CREATE)
	assert_eq(match_.phase_ends_at, config.prompt_duration + 3.0 + config.create_duration, "full creation time from now")


func test_idle_game_still_finishes() -> void:
	var guard: int = 0
	while match_.phase != GameMatch.Phase.GAME_OVER and guard < 100:
		_skip()
		guard += 1
	assert_eq(match_.phase, GameMatch.Phase.GAME_OVER, "nobody acting must not stall the game")
	assert_ne(match_.winner_id, 0)


# --- Submitting ---------------------------------------------------------------------------

func test_submit_rules() -> void:
	assert_eq(match_.submit_meme(1, MEME, 0.0), GameMatch.IntentResult.WRONG_PHASE, "not during the prompt")
	_skip_to(GameMatch.Phase.CREATE)
	assert_eq(match_.submit_meme(99, MEME, 6.0), GameMatch.IntentResult.NOT_ALLOWED, "unknown player")
	assert_eq(match_.submit_meme(1, {"template_id": "!!"}, 6.0), GameMatch.IntentResult.INVALID)
	assert_eq(match_.submit_meme(1, "junk", 6.0), GameMatch.IntentResult.INVALID)
	assert_eq(match_.submit_meme(1, MEME, 6.0), GameMatch.IntentResult.OK)


func test_resubmitting_replaces_the_meme() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 6.0)
	match_.submit_meme(1, {"template_id": "office_fire", "top_text": "v2"}, 7.0)
	assert_eq(match_.get_submission(1).template_id, "office_fire")
	assert_eq(match_.get_submission(1).top_text, "v2")


func test_allowed_templates_are_enforced() -> void:
	var players: Array[LobbyPlayer] = [LobbyPlayer.new(1, "A", 0), LobbyPlayer.new(2, "B", 1)]
	var rng := RandomNumberGenerator.new()
	var restricted := GameMatch.new(GameConfig.new(), players, PromptDeck.new(PackedStringArray(["p"]), rng), rng, PackedStringArray(["office_fire"]))
	restricted.start(0.0)
	restricted.update(restricted.phase_ends_at)
	assert_eq(restricted.submit_meme(1, MEME, 6.0), GameMatch.IntentResult.INVALID)
	assert_eq(restricted.submit_meme(1, {"template_id": "office_fire"}, 6.0), GameMatch.IntentResult.OK)


func test_template_accepts_overrides_the_allowed_list() -> void:
	var players: Array[LobbyPlayer] = [LobbyPlayer.new(1, "A", 0), LobbyPlayer.new(2, "B", 1)]
	var rng := RandomNumberGenerator.new()
	var custom := GameMatch.new(GameConfig.new(), players, PromptDeck.new(PackedStringArray(["p"]), rng), rng, PackedStringArray(["office_fire"]))
	custom.template_accepts = func(id: String) -> bool: return id.begins_with("imgflip-")
	custom.start(0.0)
	custom.update(custom.phase_ends_at)
	assert_eq(custom.submit_meme(1, {"template_id": "imgflip-found1"}, 6.0), GameMatch.IntentResult.OK)
	assert_eq(custom.submit_meme(1, {"template_id": "office_fire"}, 6.0), GameMatch.IntentResult.INVALID)
	assert_eq(custom.submit_meme(1, {"template_id": "imgflip-bad id"}, 6.0), GameMatch.IntentResult.INVALID)


# --- Voting and shooting ------------------------------------------------------------------

func test_vote_rules() -> void:
	assert_eq(match_.cast_vote(1, 1, 0.0), GameMatch.IntentResult.WRONG_PHASE)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var target: int = match_.current_spotlight_id()
	var voter: int = 1 if target != 1 else 2
	assert_eq(match_.cast_vote(target, 1, 0.0), GameMatch.IntentResult.NOT_ALLOWED, "no self-votes")
	assert_eq(match_.cast_vote(voter, 2, 0.0), GameMatch.IntentResult.INVALID)
	assert_eq(match_.cast_vote(voter, true, 0.0), GameMatch.IntentResult.INVALID, "bools are not votes")
	assert_eq(match_.cast_vote(voter, "1", 0.0), GameMatch.IntentResult.INVALID)
	assert_eq(match_.cast_vote(99, 1, 0.0), GameMatch.IntentResult.NOT_ALLOWED, "unknown voter")
	assert_eq(match_.cast_vote(voter, 1, 0.0), GameMatch.IntentResult.OK)
	assert_eq(match_.to_snapshot(0.0, voter)["my_vote"], 1)
	match_.cast_vote(voter, -1, 0.0)
	assert_eq(match_.to_snapshot(0.0, voter)["my_vote"], -1, "votes can change")
	match_.cast_vote(voter, 0, 0.0)
	assert_eq(match_.to_snapshot(0.0, voter)["my_vote"], 0, "0 takes the vote back")


func test_shoot_rules() -> void:
	assert_eq(match_.shoot(1, 0.0), GameMatch.IntentResult.WRONG_PHASE)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var target: int = match_.current_spotlight_id()
	var shooter: int = 1 if target != 1 else 2
	watch_signals(match_)
	assert_eq(match_.shoot(target, 0.0), GameMatch.IntentResult.NOT_ALLOWED, "no shooting yourself")
	assert_eq(match_.shoot(shooter, 0.0), GameMatch.IntentResult.OK)
	assert_signal_emitted_with_parameters(match_, "shot_fired", [shooter, target])
	assert_eq(match_.get_player(shooter).bullets, config.bullets_per_player - 1)
	assert_eq(match_.shoot(shooter, 0.0), GameMatch.IntentResult.ALREADY_DONE, "one bullet per spotlight")
	assert_eq(match_.get_player(shooter).bullets, config.bullets_per_player - 1, "refused shot costs nothing")
	assert_eq(match_.to_snapshot(0.0, 3)["spotlight"]["shooters"], [shooter], "shots are public")


func test_bullets_run_out() -> void:
	match_ = _make_match(3, 1, 1)
	match_.start(0.0)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var shooter: int = match_.current_spotlight_id() % 3 + 1  # Someone who isn't in the spotlight.
	assert_eq(match_.shoot(shooter, 0.0), GameMatch.IntentResult.OK)
	_skip()
	while match_.phase == GameMatch.Phase.SPOTLIGHT and match_.current_spotlight_id() == shooter:
		_skip()
	if match_.phase == GameMatch.Phase.SPOTLIGHT:
		assert_eq(match_.shoot(shooter, 0.0), GameMatch.IntentResult.NOT_ALLOWED, "no bullets left")


func test_bullets_last_the_whole_game() -> void:
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var shooter: int = match_.current_spotlight_id() % 3 + 1
	match_.shoot(shooter, 0.0)
	_skip_to(GameMatch.Phase.ELIMINATION)
	_skip()
	if match_.get_player(shooter).is_alive():
		assert_eq(match_.get_player(shooter).bullets, config.bullets_per_player - 1, "bullets don't refill per round")


# --- Elimination and game over ------------------------------------------------------------

func test_lowest_score_is_eliminated() -> void:
	watch_signals(match_)
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(2)
	assert_eq(match_.phase, GameMatch.Phase.ELIMINATION)
	assert_false(match_.get_player(2).is_alive())
	assert_eq(match_.get_player(2).status, PlayerState.Status.ELIMINATED)
	assert_eq(match_.get_player(2).out_in_round, 1)
	assert_signal_emitted_with_parameters(match_, "player_eliminated", [2, Scoring.Reason.LOWEST_SCORE])
	var elimination: Dictionary = match_.get_last_elimination()
	assert_eq(elimination["player_id"], 2)
	assert_eq(elimination["results"].size(), 3, "everyone's score is revealed")


func test_non_submitter_is_eliminated() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 6.0)
	match_.submit_meme(3, MEME, 6.0)
	_skip()  # Creation times out; player 2 never submitted.
	_vote_against(1)
	assert_eq(match_.get_last_elimination()["player_id"], 2)
	assert_eq(match_.get_last_elimination()["reason"], Scoring.Reason.NO_SUBMISSION)


func test_next_round_starts_after_elimination() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(3)
	_skip()
	assert_eq(match_.phase, GameMatch.Phase.PROMPT)
	assert_eq(match_.round_number, 2)
	assert_eq(match_.living_ids(), [1, 2] as Array[int])
	assert_eq(match_.get_last_elimination(), {}, "round data is reset")


func test_eliminated_player_votes_but_cannot_submit_or_shoot() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(3)
	_skip_to(GameMatch.Phase.CREATE)
	assert_eq(match_.submit_meme(3, MEME, 0.0), GameMatch.IntentResult.NOT_ALLOWED)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	assert_eq(match_.cast_vote(3, 1, 0.0), GameMatch.IntentResult.OK, "ghost-lite voting")
	assert_eq(match_.shoot(3, 0.0), GameMatch.IntentResult.NOT_ALLOWED)


func test_eliminated_voting_can_be_disabled() -> void:
	config.eliminated_can_vote = false
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(3)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	assert_eq(match_.cast_vote(3, 1, 0.0), GameMatch.IntentResult.NOT_ALLOWED)


func test_last_survivor_wins() -> void:
	watch_signals(match_)
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(3)
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	_vote_against(1)
	assert_eq(match_.phase, GameMatch.Phase.ELIMINATION, "the final death still gets its moment")
	_skip()
	assert_eq(match_.phase, GameMatch.Phase.GAME_OVER)
	assert_eq(match_.winner_id, 2)
	assert_signal_emitted_with_parameters(match_, "game_over", [2])
	assert_eq(match_.to_snapshot(100.0, 1)["winner_id"], 2)


# --- Disconnects --------------------------------------------------------------------------

func test_leaving_during_create_can_end_creation() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 6.0)
	match_.submit_meme(2, MEME, 6.0)
	match_.remove_player(3, 7.0)
	assert_eq(match_.phase, GameMatch.Phase.SPOTLIGHT, "everyone still here has submitted")
	assert_eq(match_.get_player(3).status, PlayerState.Status.LEFT)


func test_spotlight_player_leaving_skips_to_next() -> void:
	match_ = _make_match(4)
	match_.start(0.0)
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var leaver: int = match_.current_spotlight_id()
	match_.remove_player(leaver, 30.0)
	assert_eq(match_.phase, GameMatch.Phase.SPOTLIGHT)
	assert_ne(match_.current_spotlight_id(), leaver)
	assert_eq(match_.phase_ends_at, 30.0 + config.spotlight_duration, "the next spotlight gets full time")


func test_leaver_is_never_spotlighted_or_eliminated() -> void:
	match_ = _make_match(4)
	match_.start(0.0)
	_skip_to(GameMatch.Phase.CREATE)
	match_.remove_player(4, 6.0)
	_submit_all()
	var seen: Array[int] = []
	while match_.phase == GameMatch.Phase.SPOTLIGHT:
		seen.append(match_.current_spotlight_id())
		_skip()
	assert_false(seen.has(4))
	assert_ne(match_.get_last_elimination()["player_id"], 4, "leaving doesn't count as the round's death")


func test_everyone_else_leaving_ends_the_game() -> void:
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	match_.remove_player(1, 20.0)
	match_.remove_player(2, 20.0)
	assert_eq(match_.phase, GameMatch.Phase.GAME_OVER)
	assert_eq(match_.winner_id, 3)


func test_leaving_twice_is_harmless() -> void:
	watch_signals(match_)
	match_.remove_player(2, 1.0)
	match_.remove_player(2, 2.0)
	match_.remove_player(42, 2.0)
	assert_signal_emit_count(match_, "player_left", 1)


# --- Snapshots ----------------------------------------------------------------------------

func test_snapshot_hides_other_memes_during_create() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 6.0)
	var mine: Dictionary = match_.to_snapshot(6.0, 1)
	var theirs: Dictionary = match_.to_snapshot(6.0, 2)
	assert_eq(mine["my_meme"], MEME)
	assert_eq(theirs["my_meme"], {})
	assert_eq(theirs["submitted"], [1], "others only learn *that* player 1 submitted")
	assert_false(var_to_str(theirs).contains("sad_clown"), "player 1's meme must not leak to player 2")


func test_snapshot_reveals_only_the_spotlight_meme() -> void:
	_skip_to(GameMatch.Phase.CREATE)
	match_.submit_meme(1, MEME, 6.0)
	match_.submit_meme(2, {"template_id": "office_fire"}, 6.0)
	match_.submit_meme(3, {"template_id": "cat_stare"}, 6.0)
	var target: int = match_.current_spotlight_id()
	var snapshot: Dictionary = match_.to_snapshot(20.0, 0)
	assert_eq(snapshot["spotlight"]["player_id"], target)
	assert_eq(snapshot["spotlight"]["meme"], match_.get_submission(target).to_dict())
	for other_id: int in [1, 2, 3]:
		if other_id != target:
			var other_template: String = match_.get_submission(other_id).template_id
			assert_false(var_to_str(snapshot).contains(other_template), "unrevealed meme leaked: %s" % other_template)


func test_snapshot_hides_other_players_votes() -> void:
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var target: int = match_.current_spotlight_id()
	var voter: int = target % 3 + 1
	var bystander: int = voter % 3 + 1
	if bystander == target:
		bystander = bystander % 3 + 1
	match_.cast_vote(voter, -1, 0.0)
	assert_eq(match_.to_snapshot(0.0, bystander)["my_vote"], 0)


func test_snapshot_time_left_counts_down() -> void:
	assert_almost_eq(float(match_.to_snapshot(2.0, 1)["time_left"]), config.prompt_duration - 2.0, 0.001)
	assert_eq(match_.to_snapshot(1000.0, 1)["time_left"], 0.0, "never negative")


func test_blank_meme_shown_for_non_submitter() -> void:
	_skip_to(GameMatch.Phase.SPOTLIGHT)
	var snapshot: Dictionary = match_.to_snapshot(0.0, 1)
	assert_eq(snapshot["spotlight"]["meme"]["template_id"], "", "an empty template id means 'blank meme'")


func test_same_seed_plays_out_the_same() -> void:
	var outcomes: Array = []
	for seed_value: int in [1234, 1234, 99]:
		match_ = _make_match(5, seed_value)
		var deaths: Array[int] = []
		match_.player_eliminated.connect(func(id: int, _reason: int) -> void: deaths.append(id))
		match_.start(0.0)
		# Nobody acts, so every round is a full tie decided by the seeded RNG.
		while match_.phase != GameMatch.Phase.GAME_OVER:
			_skip()
		outcomes.append([deaths, match_.winner_id])
	assert_eq(outcomes[0], outcomes[1], "same seed, same deaths in the same order")
	assert_eq((outcomes[0][0] as Array).size(), 4)
	assert_ne(outcomes[0], outcomes[2], "a different seed plays out differently")


# --- Host-paced spotlight -------------------------------------------------------------

func _paced_match() -> GameMatch:
	var game := _make_match(3)
	config.host_paces_spotlight = true
	game.start(0.0)
	match_ = game
	_skip_to(GameMatch.Phase.CREATE)
	_submit_all()
	assert_eq(game.phase, GameMatch.Phase.SPOTLIGHT)
	return game


func test_a_host_paced_spotlight_waits_for_the_host() -> void:
	var game := _paced_match()
	var first: int = game.current_spotlight_id()
	game.update(1.0e9)
	assert_eq(game.current_spotlight_id(), first, "no timer")
	assert_true(game.is_untimed())
	assert_eq(game.to_snapshot(1.0e9, 1)["time_left"], -1.0)
	assert_eq(game.present_next(game.current_spotlight_index(), 50.0), GameMatch.IntentResult.OK)
	assert_ne(game.current_spotlight_id(), first)


func test_present_next_ignores_a_stale_press() -> void:
	var game := _paced_match()
	var index: int = game.current_spotlight_index()
	assert_eq(game.present_next(index, 50.0), GameMatch.IntentResult.OK)
	var second: int = game.current_spotlight_id()
	# The same press arriving twice must not skip the second meme.
	assert_eq(game.present_next(index, 50.0), GameMatch.IntentResult.ALREADY_DONE)
	assert_eq(game.current_spotlight_id(), second)
	assert_eq(game.present_next("next", 50.0), GameMatch.IntentResult.INVALID)


func test_presenting_past_the_last_meme_shows_the_results() -> void:
	var game := _paced_match()
	for i: int in range(3):
		assert_eq(game.present_next(game.current_spotlight_index(), 50.0), GameMatch.IntentResult.OK)
	assert_eq(game.phase, GameMatch.Phase.ELIMINATION)
	assert_false(game.is_untimed(), "the results are timed again")
	assert_eq(game.present_next(2, 51.0), GameMatch.IntentResult.WRONG_PHASE)


func test_the_snapshot_counts_judges_but_hides_votes() -> void:
	var game := _paced_match()
	var target: int = game.current_spotlight_id()
	var voter: int = 1 if target != 1 else 2
	game.cast_vote(voter, -1, 50.0)
	var spotlight: Dictionary = game.to_snapshot(50.0, target)["spotlight"]
	assert_eq(spotlight["judged"], 1)
	assert_eq(spotlight["judges"], 2)
	assert_eq(game.to_snapshot(50.0, target)["my_vote"], 0, "the target never sees the vote")
