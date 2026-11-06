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


## The subset clients need to show timers and rules.
func to_dict() -> Dictionary:
	return {
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
