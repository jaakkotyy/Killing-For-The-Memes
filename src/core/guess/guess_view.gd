class_name GuessView
extends RefCounted
## A client's parsed guess-mode snapshot (GuessMatch.to_snapshot), plus the client-side
## copies of the ask/answer/guess rules so the UI only offers what the server will accept.
## The presentation diffs two views to find new questions, answers, solves and wrong guesses.

var phase: GuessMatch.Phase = GuessMatch.Phase.WAITING
var round_number: int = 0
var rounds: int = 0
var pack_id: String = ""
var time_left: float = 0.0
var round_time_left: float = 0.0
## Local clock time the snapshot arrived (the timers count down from here).
var received_at: float = 0.0
var players: Array[PlayerState] = []
var scores: Dictionary[int, int] = {}
var round_points: Dictionary[int, int] = {}
var questions_asked: Dictionary[int, int] = {}
var wrong_guesses: Dictionary[int, int] = {}
var locked: Dictionary[int, bool] = {}
## Player id -> entry id, for every identity this viewer may know.
var identities: Dictionary[int, String] = {}
## In the order they solved.
var solved: Array[int] = []
var asker_id: int = 0
var question_text: String = ""
## Index of the pack's stock question, or -1 for the asker's own.
var question_stock: int = -1
var answered: int = 0
var answerers: int = 0
## Only after answering ends (RESULT): the counts and the majority (a GuessMatch.Answer).
var yes_count: int = 0
var no_count: int = 0
var unsure_count: int = 0
var result: int = GuessMatch.Answer.UNSURE
var my_answer: int = GuessMatch.Answer.UNSURE
var my_answered: bool = false
## Player id -> [{text, stock, answer}], everyone's questions this round.
var clues: Dictionary[int, Array] = {}
var winner_ids: Array[int] = []


static func from_snapshot(data: Dictionary, p_received_at: float) -> GuessView:
	var view := GuessView.new()
	view.phase = clampi(int(data.get("phase", 0)), 0, GuessMatch.Phase.size() - 1) as GuessMatch.Phase
	view.round_number = int(data.get("round", 0))
	view.rounds = int(data.get("rounds", 0))
	view.pack_id = str(data.get("pack", ""))
	view.time_left = maxf(0.0, float(data.get("time_left", 0.0)))
	view.round_time_left = maxf(0.0, float(data.get("round_time_left", 0.0)))
	view.received_at = p_received_at
	for entry: Variant in _array(data.get("players")):
		if not entry is Dictionary:
			continue
		var info: Dictionary = entry
		var player: PlayerState = PlayerState.from_dict(info)
		view.players.append(player)
		view.scores[player.id] = int(info.get("score", 0))
		view.round_points[player.id] = int(info.get("round_points", 0))
		view.questions_asked[player.id] = int(info.get("questions", 0))
		view.wrong_guesses[player.id] = int(info.get("wrong_guesses", 0))
		if bool(info.get("locked", false)):
			view.locked[player.id] = true
	var identities: Variant = data.get("identities")
	if identities is Dictionary:
		for key: Variant in identities:
			view.identities[int(str(key))] = str((identities as Dictionary)[key])
	view.solved.assign(_ints(data.get("solved")))
	view.asker_id = int(data.get("asker_id", 0))
	var question: Variant = data.get("question")
	if question is Dictionary:
		view.question_text = str((question as Dictionary).get("text", ""))
		view.question_stock = int((question as Dictionary).get("stock", -1))
	var tally: Variant = data.get("tally")
	if tally is Dictionary:
		var t: Dictionary = tally
		view.answered = int(t.get("answered", 0))
		view.answerers = int(t.get("answerers", 0))
		view.yes_count = int(t.get("yes", 0))
		view.no_count = int(t.get("no", 0))
		view.unsure_count = int(t.get("unsure", 0))
		view.result = clampi(int(t.get("answer", 0)), -1, 1)
	view.my_answer = clampi(int(data.get("my_answer", 0)), -1, 1)
	view.my_answered = bool(data.get("my_answered", false))
	var clues: Variant = data.get("clues")
	if clues is Dictionary:
		for key: Variant in clues:
			var list: Array = []
			for clue: Variant in _array((clues as Dictionary)[key]):
				if clue is Dictionary:
					list.append(clue)
			view.clues[int(str(key))] = list
	view.winner_ids.assign(_ints(data.get("winner_ids")))
	return view


## Seconds left in the phase at local time [param now] (same clock as received_at).
func time_left_at(now: float) -> float:
	return maxf(0.0, time_left - (now - received_at))


func round_time_left_at(now: float) -> float:
	return maxf(0.0, round_time_left - (now - received_at))


func get_player(player_id: int) -> PlayerState:
	for player: PlayerState in players:
		if player.id == player_id:
			return player
	return null


func player_name(player_id: int) -> String:
	var player: PlayerState = get_player(player_id)
	return player.name if player != null else "?"


func is_present(player_id: int) -> bool:
	var player: PlayerState = get_player(player_id)
	return player != null and player.is_present()


func score_of(player_id: int) -> int:
	return int(scores.get(player_id, 0))


## The entry id of [param player_id]'s identity, or "" if this viewer may not know it.
func identity_of(player_id: int) -> String:
	return identities.get(player_id, "")


func is_solved(player_id: int) -> bool:
	return solved.has(player_id)


## Whether the turns are running (guessing allowed, round clock ticking).
func in_turns() -> bool:
	return phase == GuessMatch.Phase.ASK or phase == GuessMatch.Phase.ANSWER or phase == GuessMatch.Phase.RESULT


func can_ask(player_id: int) -> bool:
	return phase == GuessMatch.Phase.ASK and player_id == asker_id


func can_answer(player_id: int) -> bool:
	return phase == GuessMatch.Phase.ANSWER and player_id != asker_id and is_present(player_id)


func can_guess(player_id: int) -> bool:
	return in_turns() and is_present(player_id) and not is_solved(player_id) and not locked.has(player_id)


## Players by score, best first (ties by seat), for the scoreboard.
func standings() -> Array[PlayerState]:
	var ordered: Array[PlayerState] = players.duplicate()
	ordered.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		if score_of(a.id) != score_of(b.id):
			return score_of(a.id) > score_of(b.id)
		return a.seat < b.seat)
	return ordered


static func _array(value: Variant) -> Array:
	return value if value is Array else []


static func _ints(value: Variant) -> Array[int]:
	var ints: Array[int] = []
	for item: Variant in _array(value):
		if typeof(item) in [TYPE_INT, TYPE_FLOAT]:
			ints.append(int(item))
	return ints
