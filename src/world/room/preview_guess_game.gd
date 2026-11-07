class_name PreviewGuessGame
extends Node
## A guess game run inside the room for `--room-preview=<n> --mode=guess`, with no network:
## you are player 1, and the fake players ask stock questions and answer them truthfully
## (your own questions get "I don't know"), but never guess.
## It offers the part of Session's API that GuessPresenter and GuessHud use, so the
## terminal, placards, TV and HUD can be tried and screenshotted on their own.

signal guess_updated(view: GuessView, previous: GuessView)

const LOCAL_ID: int = 1
## How long the fake players take to ask or answer.
const FAKE_DELAY: float = 0.6

var guess_view: GuessView
var game: GuessMatch

var _pack: IdentityPack
var _clock: float = 0.0
var _last_snapshot: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## When the current phase started (for the fake players' delay).
var _phase_since: float = 0.0
var _phase_key: String = ""


func setup(players: Array[LobbyPlayer], pack: IdentityPack, config: GameConfig = null) -> void:
	_pack = pack
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	game = GuessMatch.new(config if config != null else GameConfig.new(), players, pack, rng)
	game.start(_clock)
	_publish()


func _process(delta: float) -> void:
	_clock += delta
	if game == null:
		return
	game.update(_clock)
	_play_fakes()
	_publish()


## The fake players' turns: ask a random stock question, answer stock questions from the
## asker's identity.
func _play_fakes() -> void:
	var key: String = "%d:%d:%d" % [game.round_number, game.phase, game.asker_id()]
	if key != _phase_key:
		_phase_key = key
		_phase_since = _clock
	if _clock - _phase_since < FAKE_DELAY:
		return
	if game.phase == GuessMatch.Phase.ASK and game.asker_id() != LOCAL_ID:
		game.ask(game.asker_id(), {"stock": _rng.randi_range(0, _pack.stock_questions().size() - 1)}, _clock)
	elif game.phase == GuessMatch.Phase.ANSWER:
		var question: Dictionary = game.to_snapshot(_clock, 0).get("question", {})
		var stock: IdentityPack.StockQuestion = _pack.stock_question(int(question.get("stock", -1)))
		var entry: IdentityPack.Entry = _pack.get_entry(game.identity_of(game.asker_id()))
		for id: int in game.present_ids():
			if id == LOCAL_ID or id == game.asker_id():
				continue
			var answer: int = GuessMatch.Answer.UNSURE
			if stock != null and entry != null and entry.has_value(stock.filter.field.id):
				answer = GuessMatch.Answer.YES if stock.filter.matches(entry) else GuessMatch.Answer.NO
			game.answer(id, answer, _clock)


## Moves the game's clock on by [param seconds] at once (tests; frames do it otherwise).
func advance(seconds: float) -> void:
	_clock += seconds
	game.update(_clock)
	_publish()


## Sends a new view only when something other than the clocks changed.
func _publish() -> void:
	var snapshot: Dictionary = game.to_snapshot(_clock, LOCAL_ID)
	var compare: Dictionary = snapshot.duplicate()
	compare.erase("time_left")
	compare.erase("round_time_left")
	if compare == _last_snapshot:
		return
	_last_snapshot = compare
	var previous: GuessView = guess_view
	guess_view = GuessView.from_snapshot(snapshot, _clock)
	guess_updated.emit(guess_view, previous)


# --- The Session API the guess presentation uses ------------------------------------------

func local_peer_id() -> int:
	return LOCAL_ID


func is_host() -> bool:
	return true


func guess_pack() -> IdentityPack:
	return _pack


func guess_round_time_left() -> float:
	return guess_view.round_time_left_at(_clock) if guess_view != null else 0.0


func match_time_left() -> float:
	return guess_view.time_left_at(_clock) if guess_view != null else 0.0


func ask_question(text: String) -> void:
	game.ask(LOCAL_ID, {"text": text}, _clock)
	_publish()


func ask_stock_question(index: int) -> void:
	game.ask(LOCAL_ID, {"stock": index}, _clock)
	_publish()


func answer_question(value: int) -> void:
	game.answer(LOCAL_ID, value, _clock)
	_publish()


func guess_identity(entry_id: String) -> void:
	game.guess(LOCAL_ID, entry_id, _clock)
	_publish()


func return_to_lobby() -> void:
	get_tree().quit()


func leave() -> void:
	get_tree().quit()
