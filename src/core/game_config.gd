class_name GameConfig
extends Resource
## Tunable numbers for a match. Defaults match docs/GAME_DESIGN.md.
## Save variants as .tres files (e.g. a quick "party" preset) instead of editing code.

@export_group("Timing (seconds)")
## The prompt is shown on the wall TV.
@export var prompt_duration: float = 5.0
## Everyone makes a meme. Ends early once every living player has submitted.
@export var create_duration: float = 60.0
## The hosting player presents the memes at their own pace: a spotlight lasts until they
## move on (GameMatch.present_next), with no timer.
@export var host_paces_spotlight: bool = true
## One meme on the wall TV, with voting and shooting, when the host doesn't pace them.
## Bots hosting a game also wait this long before moving on.
@export var spotlight_duration: float = 12.0
## Scores are revealed and the loser dies.
@export var elimination_duration: float = 6.0
## Clients auto-submit their draft this long before creation ends, so it arrives in time.
@export var auto_submit_lead: float = 1.0

@export_group("Scoring")
@export var upvote_points: int = 1
@export var downvote_points: int = -1
## Applied once per bullet the spotlight player takes.
@export var bullet_points: int = -3

@export_group("Bullets")
## Bullets each player gets for the whole game.
@export var bullets_per_player: int = 2

@export_group("Eliminated players")
## MVP: eliminated players spectate but still vote (never shoot), so a final 1v1 is decidable.
@export var eliminated_can_vote: bool = true

@export_group("Guess mode")
## Pack file in data/identities/ (without .json). Defaults match docs/GUESS_MODE.md.
@export var identity_pack: String = "musicians"
## Identities are dealt from this many of the pack's best known entries.
@export var deal_pool: int = 300
@export var guess_rounds: int = 3
## Placards flip and the wall TV shows the category.
@export var deal_duration: float = 5.0
## A whole round; it ends earlier once everyone has solved.
@export var round_duration: float = 240.0
## The asker picks or types a question. Running out passes the turn.
@export var ask_duration: float = 25.0
## Everyone else answers. Ends early once all of them have.
@export var answer_duration: float = 12.0
## The answer stays on the wall TV.
@export var result_duration: float = 3.0
## Every identity is revealed with the round's points.
@export var reveal_duration: float = 8.0
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
		"prompt_duration": prompt_duration,
		"create_duration": create_duration,
		"host_paces_spotlight": host_paces_spotlight,
		"spotlight_duration": spotlight_duration,
		"elimination_duration": elimination_duration,
		"auto_submit_lead": auto_submit_lead,
		"upvote_points": upvote_points,
		"downvote_points": downvote_points,
		"bullet_points": bullet_points,
		"bullets_per_player": bullets_per_player,
		"eliminated_can_vote": eliminated_can_vote,
	}
