class_name MatchPresenter
extends Node
## Turns match snapshots into what happens in the room: the wall TV, the spotlight, the
## camera, the host's face, the meme station, shots and deaths. It only reads MatchViews
## (Session.match_updated) and calls room methods; game state never changes here.
##
## Everything is derived by comparing the new view with the previous one, so a client that
## enters late (previous == null) simply shows the current state without replaying effects.

var _room: GameRoom
var _station: MemeStation


func setup(room: GameRoom) -> void:
	_room = room
	_station = room.get_station()
	if _station != null:
		_station.meme_submitted.connect(Session.submit_meme)
	Session.match_updated.connect(apply)
	if Session.match_view != null:
		apply(Session.match_view, null)
	else:
		room.set_editing_allowed(false)
		_tv().show_caption(tr("GET READY"), tr("The game is about to begin."))


func apply(view: MatchView, previous: MatchView) -> void:
	_apply_deaths(view, previous)
	_apply_shots(view, previous)
	var entered: bool = previous == null or previous.phase != view.phase \
		or previous.round_number != view.round_number
	match view.phase:
		GameMatch.Phase.PROMPT:
			if entered:
				_enter_prompt(view)
		GameMatch.Phase.CREATE:
			if entered:
				_enter_create(view)
			_sync_editor_timer()
		GameMatch.Phase.SPOTLIGHT:
			if entered or previous.spotlight_id != view.spotlight_id or previous.spotlight_index != view.spotlight_index:
				_enter_spotlight(view)
		GameMatch.Phase.ELIMINATION:
			if entered:
				_enter_elimination(view)
		GameMatch.Phase.GAME_OVER:
			if entered:
				_enter_game_over(view)


# --- Phases -------------------------------------------------------------------------------

func _enter_prompt(view: MatchView) -> void:
	_lock_editor()
	_room.focus_spotlight(0)
	_host().set_expression(&"grin")
	_tv().show_caption(tr("ROUND %d") % view.round_number, view.prompt)
	_everyone_idle(view)
	_room.set_view(GameRoom.View.TV)


func _enter_create(view: MatchView) -> void:
	var me: int = _local_id()
	var alive: bool = view.is_alive(me)
	_tv().show_caption(tr("MAKE YOUR MEME"), view.prompt)
	_room.focus_spotlight(0)
	if _station == null:
		return
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat != null and player.is_alive():
			seat.avatar.type_on_keyboard()
	_station.editor.reset()
	_station.editor.set_prompt(view.prompt)
	_station.editor.set_locked(not alive)
	_room.set_editing_allowed(alive)
	if alive:
		_room.set_view(GameRoom.View.SEAT)
		_station.open()


func _enter_spotlight(view: MatchView) -> void:
	_lock_editor()
	var target: int = view.spotlight_id
	_room.focus_spotlight(target)
	_tv().show_meme(view.spotlight_meme if view.spotlight_meme != null else MemeSpec.new())
	_host().set_expression(&"grin")
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat == null or not player.is_alive():
			continue
		if player.id == target:
			seat.avatar.flinch()  # caught in the light
		else:
			seat.avatar.look_up()
	_room.set_view(GameRoom.View.TV)


func _enter_elimination(view: MatchView) -> void:
	_lock_editor()
	_everyone_idle(view)
	_host().set_expression(&"sinister")
	_room.focus_spotlight(view.eliminated_id)
	_tv().show_caption(tr("%s\nIS OUT") % view.player_name(view.eliminated_id).to_upper(),
		MatchHud.reason_text(view.elimination_reason))
	_room.set_view(GameRoom.View.OVERVIEW)


func _enter_game_over(view: MatchView) -> void:
	_lock_editor()
	_everyone_idle(view)
	_host().set_expression(&"grin")
	_room.focus_spotlight(view.winner_id)
	var winner: Seat = _seat(view.winner_id)
	if winner != null:
		winner.avatar.celebrate()
	if view.winner_id != 0:
		_tv().show_caption(tr("%s\nSURVIVES") % view.player_name(view.winner_id).to_upper(), tr("Thank you for playing."))
	else:
		_tv().show_caption(tr("NOBODY\nSURVIVES"), tr("Thank you for playing."))
	_room.set_view(GameRoom.View.OVERVIEW)


# --- Events derived from two views --------------------------------------------------------

## New shooters on the same spotlight: muzzle flash at the shooter, a flinch at the target.
func _apply_shots(view: MatchView, previous: MatchView) -> void:
	if previous == null or view.phase != GameMatch.Phase.SPOTLIGHT \
			or previous.spotlight_id != view.spotlight_id or previous.spotlight_index != view.spotlight_index:
		return
	var target: Seat = _seat(view.spotlight_id)
	for shooter_id: int in view.shooters:
		if previous.shooters.has(shooter_id):
			continue
		var shooter: Seat = _seat(shooter_id)
		if shooter != null and target != null:
			shooter.flash_shot(target.get_spotlight_target())
		if target != null:
			target.avatar.flinch()
		_host().set_expression(&"surprised")


## Players who just died get the full death; ones already dead when we arrived lie still.
func _apply_deaths(view: MatchView, previous: MatchView) -> void:
	for player: PlayerState in view.players:
		if player.status != PlayerState.Status.ELIMINATED:
			continue
		var seat: Seat = _seat(player.id)
		if seat == null or seat.avatar.is_dead():
			continue
		var was_alive: bool = previous != null and previous.is_alive(player.id)
		seat.avatar.die(was_alive)


# --- Helpers ------------------------------------------------------------------------------

func _sync_editor_timer() -> void:
	if _station == null:
		return
	# Auto-submit a little before the server's deadline so the draft arrives in time.
	var lead: float = float(Session.match_config.get("auto_submit_lead", 1.0))
	_station.editor.set_time_left(maxf(0.05, Session.match_time_left() - lead))


func _lock_editor() -> void:
	if _station == null:
		return
	_room.set_editing_allowed(false)
	_station.editor.set_time_left(-1.0)
	_station.editor.set_locked(true)


## Sits everyone back in their relaxed idle (between rounds, eliminations, game over).
func _everyone_idle(view: MatchView) -> void:
	for player: PlayerState in view.players:
		var seat: Seat = _seat(player.id)
		if seat != null and player.is_alive():
			seat.avatar.relax()


func _local_id() -> int:
	return _room.get_local_id()


func _seat(player_id: int) -> Seat:
	return _room.get_seat(player_id)


func _tv() -> WallTv:
	return _room.get_tv()


func _host() -> TheHost:
	return _room.get_host()
