class_name Scoring
extends RefCounted
## Pure scoring and elimination rules for a round. See docs/GAME_DESIGN.md → Scoring.

## Why a player was eliminated. Sent to clients so the host can announce it.
enum Reason {
	LOWEST_SCORE,   ## Clear lowest score.
	NO_SUBMISSION,  ## Didn't submit a meme; non-submitters always rank last.
	TIE_BULLETS,    ## Tied on score; took the most bullets this round.
	TIE_RANDOM,     ## Still tied; the host picked at random.
}


## Score for one spotlight. [param votes] maps voter id -> +1 (up) or -1 (down).
static func spotlight_score(votes: Dictionary, bullets_taken: int, config: GameConfig) -> int:
	var score: int = 0
	for vote: Variant in votes.values():
		if int(vote) > 0:
			score += config.upvote_points
		elif int(vote) < 0:
			score += config.downvote_points
	return score + bullets_taken * config.bullet_points


## Picks who dies among [param candidates] (ids of living players).
## Order of rules: non-submitters first, then lowest score, then most bullets taken, then random.
## Returns {"player_id": int, "reason": Reason}, or {} when there are no candidates.
static func choose_elimination(
		candidates: Array[int],
		scores: Dictionary,
		bullets_taken: Dictionary,
		submitted: Array[int],
		rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty():
		return {}

	# filter()/map() return untyped arrays, hence assign() into the typed ones.
	var pool: Array[int] = []
	pool.assign(candidates.filter(func(id: int) -> bool: return not submitted.has(id)))
	if pool.is_empty():
		pool.assign(candidates)

	var lowest: int = pool.map(func(id: int) -> int: return int(scores.get(id, 0))).min()
	var tied: Array[int] = []
	tied.assign(pool.filter(func(id: int) -> bool: return int(scores.get(id, 0)) == lowest))
	var reason: Reason = Reason.LOWEST_SCORE

	if tied.size() > 1:
		var most_bullets: int = tied.map(func(id: int) -> int: return int(bullets_taken.get(id, 0))).max()
		var shot_most: Array[int] = []
		shot_most.assign(tied.filter(func(id: int) -> bool: return int(bullets_taken.get(id, 0)) == most_bullets))
		if shot_most.size() < tied.size():
			reason = Reason.TIE_BULLETS
		tied = shot_most

	var loser: int = tied[0]
	if tied.size() > 1:
		reason = Reason.TIE_RANDOM
		tied.sort()  # Same seed → same pick, regardless of dictionary order.
		loser = tied[rng.randi_range(0, tied.size() - 1)]

	if reason == Reason.LOWEST_SCORE and not submitted.has(loser):
		reason = Reason.NO_SUBMISSION
	return {"player_id": loser, "reason": reason}


static func reason_name(reason: Reason) -> String:
	return Reason.keys()[reason].to_lower()
