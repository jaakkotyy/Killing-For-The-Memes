class_name GameConfig
extends Resource
## Tunable numbers for a match. Defaults match docs/GAME_DESIGN.md.
## Save variants as .tres files (e.g. a quick "party" preset) instead of editing code.

@export_group("Timing (seconds)")
## The host reads the prompt.
@export var prompt_duration: float = 5.0
## Everyone makes a meme. Ends early once every living player has submitted.
@export var create_duration: float = 75.0
## One meme on the wall TV, with voting and shooting.
@export var spotlight_duration: float = 12.0
## Scores are revealed and the loser dies.
@export var elimination_duration: float = 6.0

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


## The subset clients need to show timers and rules.
func to_dict() -> Dictionary:
	return {
		"prompt_duration": prompt_duration,
		"create_duration": create_duration,
		"spotlight_duration": spotlight_duration,
		"elimination_duration": elimination_duration,
		"upvote_points": upvote_points,
		"downvote_points": downvote_points,
		"bullet_points": bullet_points,
		"bullets_per_player": bullets_per_player,
		"eliminated_can_vote": eliminated_can_vote,
	}
