class_name GuessPresenter
extends Node
## Guess mode's MatchPresenter: turns GuessViews into what happens in the room. The wall
## TV shows the category, the question and its answer; the spotlight follows the asker;
## placards show everyone's identity except your own; the CRT runs the SearchTerminal;
## solvers stand up and wave, wrong guessers flinch, and the winners celebrate.
##
## Like MatchPresenter it only reads views and calls room methods, and works out events by
## diffing the new view with the previous one. Views come from [member source]: Session
## in a real game, a PreviewGuessGame in `--room-preview --mode=guess`. Anything with the
## same signal and methods works.

## Session, or a stand-in with guess_updated, guess_view, guess_pack(),
## guess_round_time_left() and the guess intents (ask_question, ask_stock_question,
## answer_question, guess_identity).
var source: Object

var _room: GameRoom
var _station: SearchStation


func setup(room: GameRoom, p_source: Object = null) -> void:
	_room = room
	source = p_source if p_source != null else Session
	_station = room.get_search_station()
	if _station != null:
		var terminal: SearchTerminal = _station.terminal
		terminal.ask_requested.connect(func(text: String) -> void: source.call("ask_question", text))
		terminal.stock_requested.connect(func(index: int) -> void: source.call("ask_stock_question", index))
		terminal.answer_requested.connect(func(value: int) -> void: source.call("answer_question", value))
		terminal.guess_requested.connect(func(entry_id: String) -> void: source.call("guess_identity", entry_id))
	source.connect("guess_updated", apply)
	var current: GuessView = source.get("guess_view")
	if current != null:
		apply(current, null)
	else:
		room.set_editing_allowed(false)
		_tv().show_caption(tr("WHO AM I?"), tr("The game is about to begin."))


func _process(_delta: float) -> void:
	var view: GuessView = source.get("guess_view") if source != null else null
	if _station == null or view == null:
		return
	_station.terminal.set_time_left(source.call("guess_round_time_left") if view.in_turns() else -1.0)


func apply(view: GuessView, previous: GuessView) -> void:
	var entered: bool = previous == null or previous.phase != view.phase \
		or previous.round_number != view.round_number
	var pack: IdentityPack = source.call("guess_pack")
	if _station != null:
		if pack != null and _station.terminal.pack != pack:
			_station.terminal.set_pack(pack)
		_station.terminal.apply_view(view, _local_id())
	_update_placards(view, pack)
	_apply_guesses(view, previous)
	match view.phase:
		GuessMatch.Phase.DEAL:
			if entered:
				_enter_deal(view, pack)
		GuessMatch.Phase.ASK:
			if entered or previous.asker_id != view.asker_id:
				_enter_ask(view)
		GuessMatch.Phase.ANSWER:
			if entered:
				_enter_answer(view)
			_show_question(view)
		GuessMatch.Phase.RESULT:
			if entered:
				_enter_result(view)
		GuessMatch.Phase.REVEAL:
			if entered:
				_enter_reveal(view, pack)
		GuessMatch.Phase.GAME_OVER:
			if entered:
				_enter_game_over(view)


# --- Phases -------------------------------------------------------------------------------

func _enter_deal(view: GuessView, pack: IdentityPack) -> void:
	_room.focus_spotlight(0)
	_everyone_relaxed(view)
	_tv().show_caption(tr("ROUND %d") % view.round_number,
		tr("Who am I? Category: %s") % (pack.name if pack != null else view.pack_id))
	# Searching is allowed from the deal on; the turns start in a moment.
	_room.set_editing_allowed(true)
	_room.set_view(GameRoom.View.TV)


func _enter_ask(view: GuessView) -> void:
	_room.set_editing_allowed(true)
	_room.focus_spotlight(view.asker_id)
	_everyone_relaxed(view)
	var asker: Seat = _seat(view.asker_id)
	if asker != null:
		asker.avatar.type_on_keyboard()
	if view.asker_id == _local_id():
		_tv().show_caption(tr("YOUR TURN"), tr("Ask a yes/no question on your terminal."))
		_room.set_view(GameRoom.View.SEAT)
		if _station != null and not _station.is_open():
			_station.open()
	else:
		_tv().show_caption(tr("%s\nIS ASKING") % view.player_name(view.asker_id).to_upper(),
			tr("Search your terminal while you wait."))


func _enter_answer(view: GuessView) -> void:
	_room.focus_spotlight(view.asker_id)
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat != null and player.is_present() and player.id != view.asker_id:
			seat.avatar.look_up()
	# Answerers who aren't busy in their terminal look at the question.
	if view.asker_id != _local_id() and (_station == null or not _station.is_open()):
		_room.set_view(GameRoom.View.TV)


func _show_question(view: GuessView) -> void:
	_tv().show_caption(view.question_text,
		tr("%s asks.   %d/%d answered") % [view.player_name(view.asker_id), view.answered, view.answerers])


func _enter_result(view: GuessView) -> void:
	_tv().show_caption(SearchTerminal.answer_text(view.result),
		tr("%s: %d yes · %d no · %d don't know") % [view.question_text, view.yes_count, view.no_count, view.unsure_count])
	var asker: Seat = _seat(view.asker_id)
	if asker != null and view.result == GuessMatch.Answer.NO:
		asker.avatar.flinch()


func _enter_reveal(view: GuessView, pack: IdentityPack) -> void:
	_close_station()
	_room.focus_spotlight(0)
	_everyone_relaxed(view)
	var lines: PackedStringArray = []
	for player: PlayerState in view.players:
		var entry: IdentityPack.Entry = pack.get_entry(view.identity_of(player.id)) if pack != null else null
		if entry == null:
			continue
		lines.append("%s: %s  %+d" % [player.name, entry.name, int(view.round_points.get(player.id, 0))])
	_tv().show_caption(tr("ROUND %d OVER") % view.round_number, "\n".join(lines))
	_room.set_view(GameRoom.View.OVERVIEW)


func _enter_game_over(view: GuessView) -> void:
	_close_station()
	_everyone_relaxed(view)
	_room.focus_spotlight(view.winner_ids[0] if view.winner_ids.size() == 1 else 0)
	var names: PackedStringArray = []
	for id: int in view.winner_ids:
		names.append(view.player_name(id).to_upper())
		var seat: Seat = _seat(id)
		if seat != null:
			seat.avatar.celebrate()
	if names.is_empty():
		_tv().show_caption(tr("GAME OVER"), tr("Thank you for playing."))
	else:
		_tv().show_caption(tr("%s\nWINS") % " & ".join(names),
			tr("%d points. Thank you for playing.") % view.score_of(view.winner_ids[0]))
	_room.set_view(GameRoom.View.OVERVIEW)


# --- Events derived from two views --------------------------------------------------------

## Fresh solvers stand up and wave; wrong guessers flinch.
func _apply_guesses(view: GuessView, previous: GuessView) -> void:
	if previous == null or previous.round_number != view.round_number:
		return
	for id: int in view.solved:
		if not previous.solved.has(id) and _seat(id) != null:
			_seat(id).avatar.celebrate()
	for id: int in view.wrong_guesses:
		if int(view.wrong_guesses[id]) > int(previous.wrong_guesses.get(id, 0)) and _seat(id) != null:
			_seat(id).avatar.flinch()


## Everyone's placard shows their identity, except yours until you solve it (or the
## round's reveal). Players who left keep theirs.
func _update_placards(view: GuessView, pack: IdentityPack) -> void:
	if view.phase == GuessMatch.Phase.WAITING or view.phase == GuessMatch.Phase.GAME_OVER:
		for player: PlayerState in view.players:
			if _seat(player.id) != null:
				_seat(player.id).hide_placard()
		return
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat == null:
			continue
		var entry: IdentityPack.Entry = pack.get_entry(view.identity_of(player.id)) if pack != null else null
		if entry == null:
			seat.show_placard("", IdentityPlacard.State.HIDDEN)
		else:
			seat.show_placard(entry.name, IdentityPlacard.State.SOLVED if view.is_solved(player.id) else IdentityPlacard.State.KNOWN)
		seat.avatar.set_spectator(not player.is_present())


# --- Helpers ------------------------------------------------------------------------------

func _close_station() -> void:
	_room.set_editing_allowed(false)


func _everyone_relaxed(view: GuessView) -> void:
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat != null and player.is_present():
			seat.avatar.relax()


func _local_id() -> int:
	return _room.get_local_id()


func _seat(player_id: int) -> Seat:
	return _room.get_seat(player_id)


func _tv() -> WallTv:
	return _room.get_tv()
