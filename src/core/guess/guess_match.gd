class_name GuessMatch
extends RefCounted
## Guess mode's authoritative rules ("Who Am I?", docs/GUESS_MODE.md). Same contract as
## GameMatch: time comes in as `now`, randomness from an injected RNG, player input as
## untrusted intents returning a GameMatch.IntentResult, and to_snapshot(now, viewer) is
## the only thing a client may see.
##
## A round: DEAL, then turns (ASK → ANSWER → RESULT) until everyone has solved their
## identity or the round clock runs out, then REVEAL. After config.guess_rounds rounds,
## GAME_OVER: most points wins. Nobody dies in this mode; only disconnected players leave.
##
## Guesses can come at any time during the turns. A wrong one costs points and locks the
## guesser out until their own next turn as asker.

signal phase_changed(phase: Phase)
signal player_left(player_id: int)
## [param answer] is an Answer.
signal question_answered(asker_id: int, answer: int)
signal guessed(player_id: int, correct: bool)
## [param winner_ids] is everyone sharing the best score (empty if nobody is left).
signal game_over(winner_ids: Array[int])

enum Phase { WAITING, DEAL, ASK, ANSWER, RESULT, REVEAL, GAME_OVER }
## What one player answered, and what a question's majority came to.
enum Answer { UNSURE = 0, YES = 1, NO = -1 }

const MIN_PLAYERS_TO_START: int = 2
const QUESTION_MAX_LENGTH: int = 120

var config: GameConfig
var pack: IdentityPack
var phase: Phase = Phase.WAITING
var round_number: int = 0
var phase_ends_at: float = 0.0
var round_ends_at: float = 0.0

var _players: Dictionary[int, PlayerState] = {}
var _scores: Dictionary[int, int] = {}
var _deck: IdentityDeck
var _winner_ids: Array[int] = []

# --- Current round ---
var _identities: Dictionary[int, String] = {}  # player id -> entry id
## Solvers in the order they solved.
var _solved: Array[int] = []
## Players whose wrong guess locks them out until their next turn.
var _locked: Dictionary[int, bool] = {}
var _wrong_guesses: Dictionary[int, int] = {}
var _questions_asked: Dictionary[int, int] = {}
var _round_points: Dictionary[int, int] = {}
## player id -> [{text, stock, answer}], the questions they asked this round and the result.
var _clues: Dictionary[int, Array] = {}
var _turn_order: Array[int] = []
var _turn_index: int = -1
var _asker_id: int = 0
## The question on the wall TV: {text, stock} (stock is -1 for the asker's own).
var _question: Dictionary = {}
var _answers: Dictionary[int, int] = {}  # answerer id -> Answer
var _last_answer: int = Answer.UNSURE


func _init(p_config: GameConfig, lobby_players: Array[LobbyPlayer], p_pack: IdentityPack,
		rng: RandomNumberGenerator) -> void:
	config = p_config
	pack = p_pack
	_deck = IdentityDeck.new(pack, rng, config.deal_pool)
	for lobby_player: LobbyPlayer in lobby_players:
		_players[lobby_player.id] = PlayerState.new(lobby_player.id, lobby_player.name, lobby_player.seat, 0)
		_scores[lobby_player.id] = 0


func start(now: float) -> void:
	assert(phase == Phase.WAITING, "match already started")
	assert(present_ids().size() >= MIN_PLAYERS_TO_START, "not enough players")
	_begin_round(now)


## Advances through every phase (and round) whose time is up. Call every frame on the server.
func update(now: float) -> void:
	while _is_running():
		if _in_turns() and now >= round_ends_at:
			_end_round(now)
		elif now >= phase_ends_at:
			_advance(now)
		else:
			break


# --- Intents ------------------------------------------------------------------------------

## The asker's question: {"text": "..."} for their own, or {"stock": index} for one of the
## pack's stock questions.
func ask(player_id: int, data: Variant, now: float) -> GameMatch.IntentResult:
	if phase != Phase.ASK:
		return GameMatch.IntentResult.WRONG_PHASE
	if player_id != _asker_id:
		return GameMatch.IntentResult.NOT_ALLOWED
	if not data is Dictionary:
		return GameMatch.IntentResult.INVALID
	var d: Dictionary = data
	var question: Dictionary = {}
	if d.has("stock"):
		var stock: IdentityPack.StockQuestion = pack.stock_question(d["stock"])
		if stock == null:
			return GameMatch.IntentResult.INVALID
		question = {"text": stock.text, "stock": int(d["stock"])}
	else:
		var text: String = MemeSpec.sanitize_caption(d.get("text")).substr(0, QUESTION_MAX_LENGTH)
		if text.is_empty():
			return GameMatch.IntentResult.INVALID
		question = {"text": text, "stock": -1}
	_question = question
	_questions_asked[player_id] = int(_questions_asked.get(player_id, 0)) + 1
	_answers.clear()
	_set_phase(Phase.ANSWER, now + config.answer_duration)
	if _answerers().is_empty():
		_close_question(now)
	return GameMatch.IntentResult.OK


## Answers the question on the wall TV: 1 Yes, -1 No, 0 "I don't know". Can be changed
## until the answering time is up.
func answer(player_id: int, value: Variant, now: float) -> GameMatch.IntentResult:
	if phase != Phase.ANSWER:
		return GameMatch.IntentResult.WRONG_PHASE
	if typeof(value) != TYPE_INT or not [Answer.YES, Answer.NO, Answer.UNSURE].has(value):
		return GameMatch.IntentResult.INVALID
	if not _answerers().has(player_id):
		return GameMatch.IntentResult.NOT_ALLOWED
	_answers[player_id] = int(value)
	if _answers.size() >= _answerers().size():
		_close_question(now)
	return GameMatch.IntentResult.OK


## Guesses the player's own identity: [param entry_id] is a pack entry id.
func guess(player_id: int, entry_id: Variant, now: float) -> GameMatch.IntentResult:
	if not _in_turns():
		return GameMatch.IntentResult.WRONG_PHASE
	if not _is_present(player_id) or not _identities.has(player_id) or _solved.has(player_id):
		return GameMatch.IntentResult.NOT_ALLOWED
	if _locked.has(player_id):
		return GameMatch.IntentResult.ALREADY_DONE
	if typeof(entry_id) != TYPE_STRING or not pack.has_entry(entry_id):
		return GameMatch.IntentResult.INVALID
	var correct: bool = entry_id == _identities[player_id]
	if correct:
		var points: int = maxi(config.solve_min,
			config.solve_points - config.per_question_cost * int(_questions_asked.get(player_id, 0)))
		if _solved.is_empty():
			points += config.first_bonus
		_solved.append(player_id)
		_add_points(player_id, points)
	else:
		_locked[player_id] = true
		_wrong_guesses[player_id] = int(_wrong_guesses.get(player_id, 0)) + 1
		_add_points(player_id, -config.wrong_guess_penalty)
	guessed.emit(player_id, correct)
	if correct:
		if _unsolved_ids().is_empty():
			_end_round(now)
		elif player_id == _asker_id and phase == Phase.ASK:
			_next_turn(now)  # nothing left for them to ask
	return GameMatch.IntentResult.OK


## A player disconnected. They are out for good; the game carries on without them.
func remove_player(player_id: int, now: float) -> void:
	if not _players.has(player_id) or _players[player_id].status == PlayerState.Status.LEFT:
		return
	_players[player_id].status = PlayerState.Status.LEFT
	_players[player_id].out_in_round = round_number
	_locked.erase(player_id)
	_answers.erase(player_id)
	player_left.emit(player_id)
	if not _is_running():
		return
	if present_ids().size() < MIN_PLAYERS_TO_START:
		_finish()
	elif _in_turns() and _unsolved_ids().is_empty():
		_end_round(now)
	elif player_id == _asker_id and (phase == Phase.ASK or phase == Phase.ANSWER):
		_next_turn(now)
	elif phase == Phase.ANSWER and _answers.size() >= _answerers().size():
		_close_question(now)


# --- Queries ------------------------------------------------------------------------------

func get_player(player_id: int) -> PlayerState:
	return _players.get(player_id)


## Connected players, by id.
func present_ids() -> Array[int]:
	var ids: Array[int] = []
	for player: PlayerState in _players.values():
		if player.is_present():
			ids.append(player.id)
	ids.sort()
	return ids


func get_score(player_id: int) -> int:
	return int(_scores.get(player_id, 0))


## Who is asking (0 outside the turns).
func asker_id() -> int:
	return _asker_id if _in_turns() else 0


func identity_of(player_id: int) -> String:
	return _identities.get(player_id, "")


func is_solved(player_id: int) -> bool:
	return _solved.has(player_id)


func winner_ids() -> Array[int]:
	return _winner_ids


## State as [param viewer_id] may see it: every identity except their own (until they
## solve it or the round is revealed), how many answered (never who answered what), and
## their own answer.
func to_snapshot(now: float, viewer_id: int) -> Dictionary:
	var players: Array[Dictionary] = []
	var sorted_players: Array[PlayerState] = []
	sorted_players.assign(_players.values())
	sorted_players.sort_custom(func(a: PlayerState, b: PlayerState) -> bool: return a.seat < b.seat)
	var revealed: bool = phase == Phase.REVEAL or phase == Phase.GAME_OVER
	var identities: Dictionary = {}
	for player: PlayerState in sorted_players:
		var info: Dictionary = player.to_dict()
		info["score"] = get_score(player.id)
		info["round_points"] = int(_round_points.get(player.id, 0))
		info["questions"] = int(_questions_asked.get(player.id, 0))
		info["wrong_guesses"] = int(_wrong_guesses.get(player.id, 0))
		info["locked"] = _locked.has(player.id)
		players.append(info)
		if _identities.has(player.id) and (player.id != viewer_id or revealed or _solved.has(player.id)):
			identities[str(player.id)] = _identities[player.id]

	var clues: Dictionary = {}
	for player_id: int in _clues:
		clues[str(player_id)] = (_clues[player_id] as Array).duplicate(true)

	var tally: Dictionary = {}
	if phase == Phase.ANSWER or phase == Phase.RESULT:
		tally = {"answered": _answers.size(), "answerers": _answerers().size()}
		if phase == Phase.RESULT:
			tally["yes"] = _answers.values().count(Answer.YES)
			tally["no"] = _answers.values().count(Answer.NO)
			tally["unsure"] = _answers.values().count(Answer.UNSURE)
			tally["answer"] = _last_answer

	return {
		"mode": "guess",
		"phase": phase,
		"round": round_number,
		"rounds": config.guess_rounds,
		"pack": pack.id,
		"time_left": maxf(0.0, phase_ends_at - now) if _is_running() else 0.0,
		"round_time_left": maxf(0.0, round_ends_at - now) if _in_turns() else 0.0,
		"players": players,
		"identities": identities,
		"solved": _solved.duplicate(),
		"asker_id": asker_id(),
		"question": _question.duplicate() if phase == Phase.ANSWER or phase == Phase.RESULT else {},
		"tally": tally,
		"my_answer": int(_answers.get(viewer_id, Answer.UNSURE)) if phase == Phase.ANSWER else 0,
		"my_answered": _answers.has(viewer_id),
		"clues": clues,
		"winner_ids": _winner_ids.duplicate(),
	}


# --- Phase flow ---------------------------------------------------------------------------

func _advance(now: float) -> void:
	match phase:
		Phase.DEAL:
			round_ends_at = now + config.round_duration
			_next_turn(now)
		Phase.ASK:
			_next_turn(now)  # the asker let the time run out
		Phase.ANSWER:
			_close_question(now)
		Phase.RESULT:
			_next_turn(now)
		Phase.REVEAL:
			if round_number >= config.guess_rounds:
				_finish()
			else:
				_begin_round(now)


func _begin_round(now: float) -> void:
	round_number += 1
	_identities.clear()
	_solved.clear()
	_locked.clear()
	_wrong_guesses.clear()
	_questions_asked.clear()
	_round_points.clear()
	_clues.clear()
	_question = {}
	_answers.clear()
	_asker_id = 0
	var ids: Array[int] = present_ids()
	var hand: PackedStringArray = _deck.deal(ids.size())
	for i: int in range(mini(ids.size(), hand.size())):
		_identities[ids[i]] = hand[i]
	# Ids are dealt in id order; the deck's order is already shuffled.
	_turn_order = _by_seat(ids)
	# A different player opens every round.
	_turn_index = posmod(round_number - 2, maxi(1, _turn_order.size()))
	_set_phase(Phase.DEAL, now + config.deal_duration)


## Hands the turn to the next connected player who hasn't solved, or ends the round.
func _next_turn(now: float) -> void:
	_question = {}
	_answers.clear()
	if _unsolved_ids().is_empty():
		_end_round(now)
		return
	for _step: int in range(_turn_order.size()):
		_turn_index = (_turn_index + 1) % _turn_order.size()
		var candidate: int = _turn_order[_turn_index]
		if _is_present(candidate) and _identities.has(candidate) and not _solved.has(candidate):
			_asker_id = candidate
			_locked.erase(candidate)  # a new turn lifts a wrong guess's lock
			_set_phase(Phase.ASK, now + config.ask_duration)
			return
	_end_round(now)


## The answering time is over (or everyone answered): record the majority.
func _close_question(now: float) -> void:
	var yes: int = _answers.values().count(Answer.YES)
	var no: int = _answers.values().count(Answer.NO)
	_last_answer = Answer.YES if yes > no else (Answer.NO if no > yes else Answer.UNSURE)
	if _last_answer != Answer.UNSURE:
		for answerer: int in _answers:
			if _answers[answerer] == _last_answer:
				_add_points(answerer, config.answer_points)
	var clue: Dictionary = _question.duplicate()
	clue["answer"] = _last_answer
	(_clues.get_or_add(_asker_id, []) as Array).append(clue)
	question_answered.emit(_asker_id, _last_answer)
	_set_phase(Phase.RESULT, now + config.result_duration)


func _end_round(now: float) -> void:
	_question = {}
	_answers.clear()
	_asker_id = 0
	_set_phase(Phase.REVEAL, now + config.reveal_duration)


func _finish() -> void:
	var best: int = -2147483648
	_winner_ids.clear()
	for player_id: int in present_ids():
		var score: int = get_score(player_id)
		if score > best:
			best = score
			_winner_ids.clear()
		if score == best:
			_winner_ids.append(player_id)
	_asker_id = 0
	phase = Phase.GAME_OVER
	phase_ends_at = 0.0
	phase_changed.emit(phase)
	game_over.emit(_winner_ids)


func _set_phase(new_phase: Phase, ends_at: float) -> void:
	phase = new_phase
	phase_ends_at = ends_at
	phase_changed.emit(phase)


# --- Helpers ------------------------------------------------------------------------------

func _is_running() -> bool:
	return phase != Phase.WAITING and phase != Phase.GAME_OVER


## In a round's turns, where guessing is allowed and the round clock runs.
func _in_turns() -> bool:
	return phase == Phase.ASK or phase == Phase.ANSWER or phase == Phase.RESULT


func _is_present(player_id: int) -> bool:
	return _players.has(player_id) and _players[player_id].is_present()


## Who may answer the current question: every connected player but the asker.
func _answerers() -> Array[int]:
	var ids: Array[int] = present_ids()
	ids.erase(_asker_id)
	return ids


func _unsolved_ids() -> Array[int]:
	var ids: Array[int] = []
	for player_id: int in present_ids():
		if _identities.has(player_id) and not _solved.has(player_id):
			ids.append(player_id)
	return ids


func _add_points(player_id: int, points: int) -> void:
	_scores[player_id] = get_score(player_id) + points
	_round_points[player_id] = int(_round_points.get(player_id, 0)) + points


func _by_seat(ids: Array[int]) -> Array[int]:
	var ordered: Array[int] = ids.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool: return _players[a].seat < _players[b].seat)
	return ordered
