extends GutTest

var config: GameConfig
var rng: RandomNumberGenerator


func before_each() -> void:
	config = GameConfig.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func _ids(values: Array) -> Array[int]:
	var ids: Array[int] = []
	ids.assign(values)
	return ids


func test_spotlight_score() -> void:
	assert_eq(Scoring.spotlight_score({}, 0, config), 0)
	assert_eq(Scoring.spotlight_score({2: 1, 3: 1, 4: -1}, 0, config), 1)
	assert_eq(Scoring.spotlight_score({2: 1}, 2, config), 1 - 6, "each bullet is -3")


func test_lowest_score_dies() -> void:
	var outcome: Dictionary = Scoring.choose_elimination(
		_ids([1, 2, 3]), {1: 2, 2: -1, 3: 0}, {}, _ids([1, 2, 3]), rng)
	assert_eq(outcome, {"player_id": 2, "reason": Scoring.Reason.LOWEST_SCORE})


func test_non_submitter_dies_even_with_better_score() -> void:
	var outcome: Dictionary = Scoring.choose_elimination(
		_ids([1, 2, 3]), {1: 5, 2: -4, 3: 0}, {}, _ids([2, 3]), rng)
	assert_eq(outcome, {"player_id": 1, "reason": Scoring.Reason.NO_SUBMISSION})


func test_among_non_submitters_lowest_score_dies() -> void:
	var outcome: Dictionary = Scoring.choose_elimination(
		_ids([1, 2, 3]), {1: 1, 2: -2, 3: 0}, {}, _ids([3]), rng)
	assert_eq(outcome["player_id"], 2)
	assert_eq(outcome["reason"], Scoring.Reason.NO_SUBMISSION)


func test_tie_broken_by_most_bullets() -> void:
	var outcome: Dictionary = Scoring.choose_elimination(
		_ids([1, 2, 3]), {1: -3, 2: -3, 3: 4}, {1: 0, 2: 1}, _ids([1, 2, 3]), rng)
	assert_eq(outcome, {"player_id": 2, "reason": Scoring.Reason.TIE_BULLETS})


func test_full_tie_is_random_but_seeded() -> void:
	var picks: Dictionary = {}
	for seed_value: int in range(40):
		var seeded := RandomNumberGenerator.new()
		seeded.seed = seed_value
		var outcome: Dictionary = Scoring.choose_elimination(
			_ids([3, 1, 2]), {1: 0, 2: 0, 3: 0}, {}, _ids([1, 2, 3]), seeded)
		assert_eq(outcome["reason"], Scoring.Reason.TIE_RANDOM)
		picks[outcome["player_id"]] = true
	assert_eq(picks.size(), 3, "every tied player can be picked")


func test_random_pick_ignores_candidate_order() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 99
	var b := RandomNumberGenerator.new()
	b.seed = 99
	var first: Dictionary = Scoring.choose_elimination(_ids([1, 2, 3]), {}, {}, _ids([1, 2, 3]), a)
	var second: Dictionary = Scoring.choose_elimination(_ids([3, 2, 1]), {}, {}, _ids([1, 2, 3]), b)
	assert_eq(first, second)


func test_no_candidates() -> void:
	assert_eq(Scoring.choose_elimination(_ids([]), {}, {}, _ids([]), rng), {})


func test_reason_name() -> void:
	assert_eq(Scoring.reason_name(Scoring.Reason.TIE_BULLETS), "tie_bullets")
