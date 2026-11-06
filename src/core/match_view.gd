class_name MatchView
extends RefCounted
## A client's read-only picture of the match, parsed from one GameMatch.to_snapshot().
##
## Session keeps the latest one (Session.match_view); the room and the HUD only read it.
## Comparing a view with the previous one tells the presentation what just happened
## (a shot, a death, a new spotlight), so the server never has to send separate events.

var phase: GameMatch.Phase = GameMatch.Phase.WAITING
var round_number: int = 0
var prompt: String = ""
## Seconds left in the phase when the snapshot was sent; see time_left_at().
var time_left: float = 0.0
## Local clock (Session's) when the snapshot arrived.
var received_at: float = 0.0
## Ordered by seat.
var players: Array[PlayerState] = []
## Players who have submitted a meme this round (alive or not).
var submitted: Array[int] = []
## Your own submission this round, or null.
var my_meme: MemeSpec
var spotlight_id: int = 0
## The meme in the spotlight (blank when that player submitted nothing).
var spotlight_meme: MemeSpec
## Who has shot the player in the spotlight, in order.
var shooters: Array[int] = []
## 0-based position of this spotlight in the round, and how many there are.
var spotlight_index: int = 0
var spotlight_count: int = 0
## Your vote on the current spotlight: +1, -1 or 0.
var my_vote: int = 0
## The most recent elimination (ELIMINATION and GAME_OVER only); 0 when there is none.
var eliminated_id: int = 0
## A Scoring.Reason.
var elimination_reason: int = 0
## One entry per candidate: player_id, score, upvotes, downvotes, bullets, submitted.
var results: Array[Dictionary] = []
## 0 while the game runs, and at the end if nobody is left.
var winner_id: int = 0


static func from_snapshot(data: Dictionary, p_received_at: float) -> MatchView:
	var view := MatchView.new()
	view.phase = clampi(int(data.get("phase", 0)), 0, GameMatch.Phase.size() - 1) as GameMatch.Phase
	view.round_number = int(data.get("round", 0))
	view.prompt = str(data.get("prompt", ""))
	view.time_left = maxf(0.0, float(data.get("time_left", 0.0)))
	view.received_at = p_received_at
	for entry: Variant in data.get("players", []):
		if entry is Dictionary:
			view.players.append(PlayerState.from_dict(entry))
	view.submitted.assign(_int_array(data.get("submitted", [])))
	var mine: Variant = data.get("my_meme", {})
	if mine is Dictionary and not (mine as Dictionary).is_empty():
		view.my_meme = MemeSpec.from_dict(mine)
	var spotlight: Variant = data.get("spotlight", {})
	if spotlight is Dictionary and not (spotlight as Dictionary).is_empty():
		var s: Dictionary = spotlight
		view.spotlight_id = int(s.get("player_id", 0))
		var meme: Variant = s.get("meme", {})
		view.spotlight_meme = MemeSpec.from_dict(meme if meme is Dictionary else {})
		view.shooters.assign(_int_array(s.get("shooters", [])))
		view.spotlight_index = int(s.get("index", 0))
		view.spotlight_count = int(s.get("count", 0))
	view.my_vote = clampi(int(data.get("my_vote", 0)), -1, 1)
	var elimination: Variant = data.get("elimination", {})
	if elimination is Dictionary and not (elimination as Dictionary).is_empty():
		var e: Dictionary = elimination
		view.eliminated_id = int(e.get("player_id", 0))
		view.elimination_reason = int(e.get("reason", 0))
		for entry: Variant in e.get("results", []):
			if entry is Dictionary:
				view.results.append(entry)
	view.winner_id = int(data.get("winner_id", 0))
	return view


## Seconds left in the phase at local time [param now] (same clock as received_at).
func time_left_at(now: float) -> float:
	return maxf(0.0, time_left - (now - received_at))


func get_player(player_id: int) -> PlayerState:
	for player: PlayerState in players:
		if player.id == player_id:
			return player
	return null


func is_alive(player_id: int) -> bool:
	var player: PlayerState = get_player(player_id)
	return player != null and player.is_alive()


func living_ids() -> Array[int]:
	var ids: Array[int] = []
	for player: PlayerState in players:
		if player.is_alive():
			ids.append(player.id)
	return ids


func player_name(player_id: int) -> String:
	var player: PlayerState = get_player(player_id)
	return player.name if player != null else "?"


## Whether [param player_id] may vote on the current spotlight (same rule as the server).
func can_vote(player_id: int, eliminated_can_vote: bool) -> bool:
	if phase != GameMatch.Phase.SPOTLIGHT or player_id == spotlight_id:
		return false
	var player: PlayerState = get_player(player_id)
	if player == null:
		return false
	return player.is_alive() or (player.status == PlayerState.Status.ELIMINATED and eliminated_can_vote)


## Whether [param player_id] may still shoot the current spotlight (same rule as the server).
func can_shoot(player_id: int) -> bool:
	if phase != GameMatch.Phase.SPOTLIGHT or player_id == spotlight_id or shooters.has(player_id):
		return false
	var player: PlayerState = get_player(player_id)
	return player != null and player.is_alive() and player.bullets > 0


## Players in the order they finished: the winner first, then the latest to die.
func standings() -> Array[PlayerState]:
	var ordered: Array[PlayerState] = players.duplicate()
	ordered.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		if a.is_alive() != b.is_alive():
			return a.is_alive()
		if a.out_in_round != b.out_in_round:
			return a.out_in_round > b.out_in_round
		return a.seat < b.seat)
	return ordered


static func _int_array(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw is Array:
		for value: Variant in raw:
			result.append(int(value))
	return result
