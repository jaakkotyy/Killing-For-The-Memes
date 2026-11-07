class_name GameConfig
extends Resource
## Tunable numbers for a match. Defaults match docs/GAME_DESIGN.md.
## Save variants as .tres files (e.g. a quick "party" preset) instead of editing code.

@export_group("Pack")
## Pack file in data/identities/ (without .json).
@export var identity_pack: String = "musicians"
## Identities are dealt from this many of the pack's best known entries.
@export var deal_pool: int = 300

@export_group("Timing (seconds)")
@export var guess_rounds: int = 3
## Placards flip and the screen shows the category.
@export var deal_duration: float = 5.0
## A whole round; it ends earlier once everyone has solved.
@export var round_duration: float = 240.0
## The asker picks or types a question. Running out passes the turn.
@export var ask_duration: float = 25.0
## Everyone else answers. Ends early once all of them have.
@export var answer_duration: float = 12.0
## The answer stays on the screen.
@export var result_duration: float = 3.0
## Every identity is revealed with the round's points.
@export var reveal_duration: float = 8.0

@export_group("Points")
@export var solve_points: int = 100
## Taken off solve_points for every question the solver asked this round.
@export var per_question_cost: int = 8
@export var solve_min: int = 30
## For the first player to solve in a round.
@export var first_bonus: int = 25
@export var wrong_guess_penalty: int = 15
## For answering Yes or No with the final majority (so people don't hide behind "I don't know").
@export var answer_points: int = 2


## The subset clients need to show timers and rules.
func to_dict() -> Dictionary:
	return {
		"identity_pack": identity_pack,
		"guess_rounds": guess_rounds,
		"deal_duration": deal_duration,
		"round_duration": round_duration,
		"ask_duration": ask_duration,
		"answer_duration": answer_duration,
		"result_duration": result_duration,
		"reveal_duration": reveal_duration,
		"solve_points": solve_points,
		"per_question_cost": per_question_cost,
		"solve_min": solve_min,
		"first_bonus": first_bonus,
		"wrong_guess_penalty": wrong_guess_penalty,
		"answer_points": answer_points,
	}
