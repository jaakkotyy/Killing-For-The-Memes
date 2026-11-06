class_name MatchHud
extends CanvasLayer
## The match overlay in the room: round, phase and countdown, your bullets, the vote and
## shoot buttons during a spotlight, who shot whom, the round's results and the win screen.
## A view over Session.match_view; every action goes through Session.
##
## Keys during a spotlight: 1 = good, 2 = bad (press again to take the vote back),
## Space = shoot.

const BANNER_SECONDS: float = 2.5
const TOAST_SECONDS: float = 2.0
const TEXT_COLOR: Color = Color(0.92, 0.88, 0.8)
const DIM_COLOR: Color = Color(0.62, 0.58, 0.52)
const DANGER_COLOR: Color = Color(0.95, 0.3, 0.25)
const WINNER_COLOR: Color = Color(0.95, 0.8, 0.35)

var _view: MatchView
var _banner_tween: Tween
var _toast_tween: Tween

@onready var _top_bar: Control = %TopBar
@onready var _phase_label: Label = %PhaseLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _bullets_label: Label = %BulletsLabel
@onready var _banner: Label = %Banner
@onready var _toast: Label = %Toast
@onready var _action_bar: Control = %ActionBar
@onready var _action_status: Label = %ActionStatus
@onready var _action_buttons: Control = %ActionButtons
@onready var _up_button: Button = %UpButton
@onready var _down_button: Button = %DownButton
@onready var _shoot_button: Button = %ShootButton
@onready var _results_panel: Control = %ResultsPanel
@onready var _results_list: VBoxContainer = %ResultsList
@onready var _win_panel: Control = %WinPanel
@onready var _win_title: Label = %WinTitle
@onready var _standings: VBoxContainer = %Standings
@onready var _wait_label: Label = %WaitLabel
@onready var _lobby_button: Button = %LobbyButton
@onready var _menu_button: Button = %MenuButton


## Why someone died, for the TV and the results.
static func reason_text(reason: int) -> String:
	match reason:
		Scoring.Reason.NO_SUBMISSION:
			return TranslationServer.translate("Didn't make a meme.")
		Scoring.Reason.TIE_BULLETS:
			return TranslationServer.translate("Tied for the worst meme and took the most bullets.")
		Scoring.Reason.TIE_RANDOM:
			return TranslationServer.translate("Tied for the worst meme. The host chose.")
	return TranslationServer.translate("Worst meme of the round.")


func _ready() -> void:
	_style()
	_up_button.pressed.connect(_vote.bind(1))
	_down_button.pressed.connect(_vote.bind(-1))
	_shoot_button.pressed.connect(_shoot)
	_lobby_button.pressed.connect(Session.return_to_lobby)
	_menu_button.pressed.connect(Session.leave)
	_banner.modulate.a = 0.0
	_toast.modulate.a = 0.0
	_action_bar.visible = false
	_results_panel.visible = false
	_win_panel.visible = false
	_top_bar.visible = false
	Session.match_updated.connect(_on_match_updated)
	if Session.match_view != null:
		_on_match_updated(Session.match_view, null)


func _process(_delta: float) -> void:
	if _view == null:
		return
	var running: bool = _view.phase != GameMatch.Phase.GAME_OVER and _view.phase != GameMatch.Phase.WAITING
	_timer_label.visible = running
	var seconds: int = ceili(Session.match_time_left())
	_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]


func _unhandled_input(event: InputEvent) -> void:
	if _view == null or _view.phase != GameMatch.Phase.SPOTLIGHT:
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_KP_1:
			_vote(1)
		KEY_2, KEY_KP_2:
			_vote(-1)
		KEY_SPACE:
			_shoot()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_match_updated(view: MatchView, previous: MatchView) -> void:
	_view = view
	var entered: bool = previous == null or previous.phase != view.phase or previous.round_number != view.round_number
	_top_bar.visible = true
	_update_top_bar(view)
	_update_actions(view)
	_announce(view, previous, entered)
	_results_panel.visible = view.phase == GameMatch.Phase.ELIMINATION
	if _results_panel.visible and entered:
		_fill_results(view)
	_win_panel.visible = view.phase == GameMatch.Phase.GAME_OVER
	if _win_panel.visible and entered:
		_fill_win(view)


func _update_top_bar(view: MatchView) -> void:
	var phase_text: String = ""
	match view.phase:
		GameMatch.Phase.PROMPT:
			phase_text = tr("New prompt")
		GameMatch.Phase.CREATE:
			phase_text = tr("Make a meme  %d/%d done") % [_count_submitted(view), view.living_ids().size()]
		GameMatch.Phase.SPOTLIGHT:
			phase_text = tr("Spotlight %d/%d: %s") % [view.spotlight_index + 1, view.spotlight_count, view.player_name(view.spotlight_id)]
		GameMatch.Phase.ELIMINATION:
			phase_text = tr("Results")
		GameMatch.Phase.GAME_OVER:
			phase_text = tr("Game over")
	_phase_label.text = (tr("ROUND %d") % view.round_number) + "   " + phase_text
	var me: PlayerState = view.get_player(Session.local_peer_id())
	if me == null or me.status == PlayerState.Status.LEFT:
		_bullets_label.text = ""
	elif me.is_alive():
		_bullets_label.text = tr("BULLETS %d") % me.bullets
	else:
		_bullets_label.text = tr("SPECTATING")


func _update_actions(view: MatchView) -> void:
	_action_bar.visible = view.phase == GameMatch.Phase.SPOTLIGHT
	if not _action_bar.visible:
		return
	var me: int = Session.local_peer_id()
	if view.spotlight_id == me:
		_action_status.text = tr("You are in the spotlight. Look innocent.")
		_action_buttons.visible = false
		return
	var can_vote: bool = view.can_vote(me, Session.eliminated_can_vote())
	var can_shoot: bool = view.can_shoot(me)
	_action_buttons.visible = can_vote or can_shoot
	_up_button.disabled = not can_vote
	_down_button.disabled = not can_vote
	_up_button.set_pressed_no_signal(view.my_vote == 1)
	_down_button.set_pressed_no_signal(view.my_vote == -1)
	var player: PlayerState = view.get_player(me)
	var bullets: int = player.bullets if player != null else 0
	_shoot_button.disabled = not can_shoot
	_shoot_button.text = tr("SHOOT  [Space]  %d left") % bullets
	if not can_vote and not can_shoot:
		_action_status.text = tr("You can only watch now.")
	elif view.shooters.has(me):
		_action_status.text = tr("You shot %s.") % view.player_name(view.spotlight_id)
	else:
		_action_status.text = tr("Judge %s's meme.") % view.player_name(view.spotlight_id)


## Big text when a phase starts, and a toast for every new shot.
func _announce(view: MatchView, previous: MatchView, entered: bool) -> void:
	var new_spotlight: bool = view.phase == GameMatch.Phase.SPOTLIGHT and (entered
		or previous.spotlight_id != view.spotlight_id or previous.spotlight_index != view.spotlight_index)
	if entered:
		# Old news (who shot whom, the last banner) must not leak into the next phase.
		_hide_label(_toast, _toast_tween)
		_hide_label(_banner, _banner_tween)
		match view.phase:
			GameMatch.Phase.PROMPT:
				_show_banner(view.prompt, TEXT_COLOR)
			GameMatch.Phase.CREATE:
				if not view.is_alive(Session.local_peer_id()):
					_show_banner(tr("The living are making memes."), DIM_COLOR)
			GameMatch.Phase.ELIMINATION:
				# The reason is on the TV and in the results; the banner stays short.
				_show_banner(tr("%s is out.") % view.player_name(view.eliminated_id), DANGER_COLOR)
	if new_spotlight:
		_show_banner(tr("%s's meme") % view.player_name(view.spotlight_id), TEXT_COLOR)
	elif previous != null and view.phase == GameMatch.Phase.SPOTLIGHT:
		for shooter: int in view.shooters:
			if not previous.shooters.has(shooter):
				_show_toast(tr("%s shot %s!") % [view.player_name(shooter), view.player_name(view.spotlight_id)])


func _fill_results(view: MatchView) -> void:
	for child: Node in _results_list.get_children():
		child.queue_free()
	var rows: Array[Dictionary] = view.results.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	for row: Dictionary in rows:
		var id: int = int(row.get("player_id", 0))
		var line := Label.new()
		var details: String = tr("no meme") if not bool(row.get("submitted", false)) else \
			tr("%d good, %d bad") % [int(row.get("upvotes", 0)), int(row.get("downvotes", 0))]
		var shots: int = int(row.get("bullets", 0))
		if shots > 0:
			details += tr(", shot %dx") % shots
		line.text = "%+d   %s   (%s)" % [int(row.get("score", 0)), view.player_name(id), details]
		line.add_theme_color_override("font_color", DANGER_COLOR if id == view.eliminated_id else TEXT_COLOR)
		_results_list.add_child(line)


func _fill_win(view: MatchView) -> void:
	if view.winner_id == Session.local_peer_id():
		_win_title.text = tr("YOU SURVIVED")
	elif view.winner_id != 0:
		_win_title.text = tr("%s SURVIVED") % view.player_name(view.winner_id).to_upper()
	else:
		_win_title.text = tr("NOBODY SURVIVED")
	for child: Node in _standings.get_children():
		child.queue_free()
	var place: int = 1
	for player: PlayerState in view.standings():
		var line := Label.new()
		var fate: String = tr("winner") if player.id == view.winner_id else \
			(tr("walked out in round %d") if player.status == PlayerState.Status.LEFT else tr("died in round %d")) % player.out_in_round
		line.text = "%d.  %s   %s" % [place, player.name, fate]
		line.add_theme_color_override("font_color", WINNER_COLOR if player.id == view.winner_id else TEXT_COLOR)
		_standings.add_child(line)
		place += 1
	_lobby_button.visible = Session.is_host()
	_wait_label.visible = not Session.is_host()


func _vote(value: int) -> void:
	if _view == null or not _view.can_vote(Session.local_peer_id(), Session.eliminated_can_vote()):
		return
	# Pressing your current vote again takes it back.
	Session.cast_vote(0 if _view.my_vote == value else value)


func _shoot() -> void:
	if _view != null and _view.can_shoot(Session.local_peer_id()):
		Session.shoot()


func _count_submitted(view: MatchView) -> int:
	var count: int = 0
	for id: int in view.living_ids():
		if view.submitted.has(id):
			count += 1
	return count


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _hide_label(label: Label, tween: Tween) -> void:
	if tween != null:
		tween.kill()
	label.modulate.a = 0.0


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


## Dark translucent panels and outlined text, readable over the dim room.
func _style() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.03, 0.03, 0.78)
	panel.border_color = Color(0.4, 0.3, 0.25, 0.8)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(12)
	var hud_theme := Theme.new()
	hud_theme.default_font_size = 22
	hud_theme.set_stylebox("panel", "PanelContainer", panel)
	hud_theme.set_color("font_color", "Label", TEXT_COLOR)
	hud_theme.set_color("font_outline_color", "Label", Color.BLACK)
	hud_theme.set_constant("outline_size", "Label", 6)
	(%Root as Control).theme = hud_theme
	_banner.add_theme_font_size_override("font_size", 40)
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", DANGER_COLOR)
	_win_title.add_theme_font_size_override("font_size", 44)
	_win_title.add_theme_color_override("font_color", WINNER_COLOR)
