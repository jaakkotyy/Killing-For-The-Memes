extends Node
## Development bot for guess mode (--auto-play, next to AutoPlayer): plays the local
## player's turns through the public Session API, like the terminal UI will.
##
## It asks the pack's stock questions it hasn't asked yet (now and then its own), answers
## stock questions truthfully from the asker's identity (which it can see, like any other
## player) and its own questions with "I don't know", turns its clear answers into search
## filters, crosses out everyone else's identities, and guesses the best known candidate
## once few are left or the round clock runs low.

const OWN_QUESTION_CHANCE: float = 0.2
## Sometimes it doesn't know either.
const UNSURE_CHANCE: float = 0.1
const GUESS_WHEN_LEFT: int = 3
## Guesses anyway once this share of the round clock is left.
const LATE_GUESS_SHARE: float = 0.3
const MIN_DELAY: float = 0.05
const MAX_DELAY: float = 0.3

var _rng := RandomNumberGenerator.new()
var _query := IdentityQuery.new()
var _round: int = -1
## Turns, questions and guesses already acted on ("kind:round:n").
var _handled: Dictionary = {}
var _last_guess: String = ""


func _ready() -> void:
	_rng.randomize()
	Session.guess_updated.connect(_on_guess_updated)


func _on_guess_updated(view: GuessView, previous: GuessView) -> void:
	var me: int = Session.local_peer_id()
	var pack: IdentityPack = Session.guess_pack()
	if pack == null:
		return
	if view.round_number != _round:
		_round = view.round_number
		_query = IdentityQuery.new()
		_last_guess = ""
	_learn(view, previous, me, pack)

	var key: String
	if view.can_ask(me):
		key = "ask:%d:%d" % [view.round_number, int(view.questions_asked.get(me, 0))]
		if _once(key):
			_after_delay(_ask.bind(key, pack))
	if view.can_answer(me) and not view.my_answered:
		key = "answer:%d:%d:%d" % [view.round_number, view.asker_id, int(view.questions_asked.get(view.asker_id, 0))]
		if _once(key):
			_after_delay(_answer.bind(key, pack))
	if view.can_guess(me):
		var open: int = _query.count_open(pack)
		var late: bool = view.round_time_left < float(Session.match_config.get("round_duration", 240.0)) * LATE_GUESS_SHARE
		if open <= GUESS_WHEN_LEFT or late:
			key = "guess:%d:%d" % [view.round_number, _query.struck.size()]
			if _once(key):
				_after_delay(_guess.bind(key, pack))


## Updates the search from what this round has taught us.
func _learn(view: GuessView, previous: GuessView, me: int, pack: IdentityPack) -> void:
	for player_id: int in view.identities:
		if player_id != me:
			_query.struck[view.identities[player_id]] = true  # someone else's: not ours
	if previous != null and previous.round_number == view.round_number \
			and int(view.wrong_guesses.get(me, 0)) > int(previous.wrong_guesses.get(me, 0)) and not _last_guess.is_empty():
		_query.struck[_last_guess] = true
	_query.filters.clear()
	for clue: Variant in view.clues.get(me, []):
		var c: Dictionary = clue
		var stock: IdentityPack.StockQuestion = pack.stock_question(int(c.get("stock", -1)))
		var answer: int = int(c.get("answer", GuessMatch.Answer.UNSURE))
		if stock != null and answer != GuessMatch.Answer.UNSURE:
			_query.add_filter(stock.filter if answer == GuessMatch.Answer.YES else stock.filter.negated())


func _ask(key: String, pack: IdentityPack) -> void:
	var view: GuessView = Session.guess_view
	if view == null or not view.can_ask(Session.local_peer_id()) or not _still(key, "ask:%d:%d" % [view.round_number, int(view.questions_asked.get(Session.local_peer_id(), 0))]):
		return
	var asked: Dictionary = {}
	for clue: Variant in view.clues.get(Session.local_peer_id(), []):
		asked[int((clue as Dictionary).get("stock", -1))] = true
	var fresh: Array[int] = []
	for index: int in range(pack.stock_questions().size()):
		if not asked.has(index):
			fresh.append(index)
	if fresh.is_empty() or _rng.randf() < OWN_QUESTION_CHANCE:
		Session.ask_question("Am I someone a bot would know?")
	else:
		Session.ask_stock_question(fresh[_rng.randi_range(0, fresh.size() - 1)])


func _answer(_key: String, pack: IdentityPack) -> void:
	var view: GuessView = Session.guess_view
	if view == null or not view.can_answer(Session.local_peer_id()):
		return
	var answer: int = GuessMatch.Answer.UNSURE
	var stock: IdentityPack.StockQuestion = pack.stock_question(view.question_stock)
	var entry: IdentityPack.Entry = pack.get_entry(view.identity_of(view.asker_id))
	if stock != null and entry != null and entry.has_value(stock.filter.field.id) and _rng.randf() >= UNSURE_CHANCE:
		answer = GuessMatch.Answer.YES if stock.filter.matches(entry) else GuessMatch.Answer.NO
	Session.answer_question(answer)


func _guess(_key: String, pack: IdentityPack) -> void:
	var view: GuessView = Session.guess_view
	if view == null or not view.can_guess(Session.local_peer_id()):
		return
	for entry: IdentityPack.Entry in _query.run(pack):
		if not _query.is_struck(entry.id):
			_last_guess = entry.id
			print("[GuessBot] Guessing %s (%d candidates left)" % [entry.name, _query.count_open(pack)])
			Session.guess_identity(entry.id)
			return


func _once(key: String) -> bool:
	if _handled.has(key):
		return false
	_handled[key] = true
	return true


func _still(key: String, current: String) -> bool:
	return key == current


func _after_delay(callback: Callable) -> void:
	get_tree().create_timer(_rng.randf_range(MIN_DELAY, MAX_DELAY)).timeout.connect(callback)
