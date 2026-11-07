class_name GuessHud
extends CanvasLayer
## The overlay in the room: round, whose turn it is, the phase and round clocks, your
## score, the scoreboard, the question with Yes / No / I don't know (keys 1, 2, 3; press your answer again to change it), the round's reveal
## and the final standings. A view over GuessViews from [member source] (Session, or the
## preview's stand-in); every action goes through it.
##
## While the camera is zoomed into the CRT this layer is hidden under the screen, so the
## terminal offers the same answers itself.

const BANNER_SECONDS: float = 2.5
const TOAST_SECONDS: float = 2.2
const TEXT_COLOR: Color = Color(0.86, 0.92, 1.0)
const DIM_COLOR: Color = Color(0.55, 0.62, 0.72)
const GOOD_COLOR: Color = Color(0.45, 1.0, 0.62)
const BAD_COLOR: Color = Color(0.95, 0.3, 0.25)
const WINNER_COLOR: Color = Color(0.72, 0.94, 1.0)

## Session, or a stand-in with the same guess_updated signal and methods (GuessPresenter
## documents the list).
var source: Object

var _view: GuessView
var _banner_tween: Tween
var _toast_tween: Tween

var _root: Control
var _top_bar: PanelContainer
var _phase_label: Label
var _timer_label: Label
var _score_label: Label
var _board: PanelContainer
var _board_list: VBoxContainer
var _question_bar: PanelContainer
var _question_label: Label
var _question_status: Label
var _answer_row: HBoxContainer
var _answer_buttons: Dictionary = {}  # GuessMatch.Answer -> Button
var _banner: Label
var _toast: Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_list: VBoxContainer
var _end_buttons: HBoxContainer
var _wait_label: Label


func _init(p_source: Object = null) -> void:
	source = p_source


func _ready() -> void:
	layer = 3
	if source == null:
		source = Session
	_build()
	source.connect("guess_updated", _on_guess_updated)
	var current: GuessView = source.get("guess_view")
	if current != null:
		_on_guess_updated(current, null)


func _process(_delta: float) -> void:
	if _view == null:
		return
	var seconds: float = -1.0
	if _view.in_turns():
		seconds = float(source.call("guess_round_time_left"))
	elif _view.phase == GuessMatch.Phase.DEAL or _view.phase == GuessMatch.Phase.REVEAL:
		seconds = float(source.call("match_time_left"))
	_timer_label.visible = seconds >= 0.0
	var whole: int = ceili(maxf(0.0, seconds))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]
	if _view.phase == GuessMatch.Phase.ANSWER or _view.phase == GuessMatch.Phase.ASK:
		var turn: int = ceili(float(source.call("match_time_left")))
		_question_status.text = _turn_text(_view) + ("   %ds" % turn)


func _unhandled_input(event: InputEvent) -> void:
	if _view == null or not _view.can_answer(_me()):
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_KP_1:
			_answer(GuessMatch.Answer.YES)
		KEY_2, KEY_KP_2:
			_answer(GuessMatch.Answer.NO)
		KEY_3, KEY_KP_3:
			_answer(GuessMatch.Answer.UNSURE)
		_:
			return
	get_viewport().set_input_as_handled()


## The question bar's text ("" while it is hidden), for tests.
func get_question_text() -> String:
	return _question_label.text if _question_bar.visible else ""


func _on_guess_updated(view: GuessView, previous: GuessView) -> void:
	_view = view
	var entered: bool = previous == null or previous.phase != view.phase or previous.round_number != view.round_number
	_top_bar.visible = true
	_update_top_bar(view)
	_update_board(view)
	_update_question(view)
	_announce(view, previous, entered)
	var ended: bool = view.phase == GuessMatch.Phase.REVEAL or view.phase == GuessMatch.Phase.GAME_OVER
	_end_panel.visible = ended
	if ended and entered:
		_fill_end(view)


func _update_top_bar(view: GuessView) -> void:
	var text: String = tr("ROUND %d/%d") % [view.round_number, view.rounds]
	match view.phase:
		GuessMatch.Phase.DEAL:
			text += "   " + tr("Dealing identities")
		GuessMatch.Phase.ASK, GuessMatch.Phase.ANSWER, GuessMatch.Phase.RESULT:
			text += "   " + (tr("Your turn") if view.asker_id == _me() else tr("%s's turn") % view.player_name(view.asker_id))
		GuessMatch.Phase.REVEAL:
			text += "   " + tr("Reveal")
		GuessMatch.Phase.GAME_OVER:
			text = tr("Game over")
	_phase_label.text = text
	var mine: String = tr("SCORE %d") % view.score_of(_me())
	if view.is_solved(_me()):
		mine += "   " + tr("SOLVED")
	elif view.locked.has(_me()):
		mine += "   " + tr("LOCKED")
	_score_label.text = mine


func _update_board(view: GuessView) -> void:
	_board.visible = view.phase != GuessMatch.Phase.WAITING and view.phase != GuessMatch.Phase.GAME_OVER
	for child: Node in _board_list.get_children():
		child.queue_free()
	for player: PlayerState in view.standings():
		var line := Label.new()
		var marks: String = ""
		if view.is_solved(player.id):
			marks = "  ✓"
		elif view.locked.has(player.id):
			marks = "  ✗"
		line.text = "%d  %s%s" % [view.score_of(player.id), player.name, marks]
		line.add_theme_font_size_override("font_size", 18)
		var color: Color = TEXT_COLOR
		if not player.is_present():
			color = DIM_COLOR
		elif view.is_solved(player.id):
			color = GOOD_COLOR
		elif player.id == view.asker_id and view.in_turns():
			color = WINNER_COLOR
		line.add_theme_color_override("font_color", color)
		_board_list.add_child(line)


func _update_question(view: GuessView) -> void:
	var asking: bool = view.phase == GuessMatch.Phase.ASK
	var answering: bool = view.phase == GuessMatch.Phase.ANSWER
	var result: bool = view.phase == GuessMatch.Phase.RESULT
	_question_bar.visible = asking or answering or result
	if not _question_bar.visible:
		return
	_answer_row.visible = answering and view.can_answer(_me())
	if asking:
		_question_label.text = tr("Your turn: ask on your terminal (E).") if view.asker_id == _me() \
			else tr("%s is thinking of a question...") % view.player_name(view.asker_id)
	elif answering:
		_question_label.text = "%s: %s" % [view.player_name(view.asker_id), view.question_text]
	else:
		_question_label.text = "%s  →  %s" % [view.question_text, SearchTerminal.answer_text(view.result)]
	_question_status.text = _turn_text(view)
	for value: int in _answer_buttons:
		(_answer_buttons[value] as Button).set_pressed_no_signal(view.my_answered and view.my_answer == value)


func _turn_text(view: GuessView) -> String:
	match view.phase:
		GuessMatch.Phase.ANSWER:
			if view.asker_id == _me():
				return tr("Your question is on the TV. %d/%d answered.") % [view.answered, view.answerers]
			if view.my_answered:
				return tr("You answered. %d/%d. Press another key to change it.") % [view.answered, view.answerers]
			return tr("1 Yes   2 No   3 Don't know   (%d/%d answered)") % [view.answered, view.answerers]
		GuessMatch.Phase.RESULT:
			return tr("%d yes · %d no · %d don't know") % [view.yes_count, view.no_count, view.unsure_count]
	return ""


## Big text when a phase starts; toasts for guesses.
func _announce(view: GuessView, previous: GuessView, entered: bool) -> void:
	if entered:
		match view.phase:
			GuessMatch.Phase.DEAL:
				_show_banner(tr("Round %d. Who are you?") % view.round_number, TEXT_COLOR)
			GuessMatch.Phase.ASK:
				if view.asker_id == _me():
					_show_banner(tr("Your turn to ask"), WINNER_COLOR)
			GuessMatch.Phase.REVEAL:
				_show_banner(tr("Round over"), TEXT_COLOR)
	elif view.phase == GuessMatch.Phase.ASK and previous.asker_id != view.asker_id and view.asker_id == _me():
		_show_banner(tr("Your turn to ask"), WINNER_COLOR)
	if previous == null or previous.round_number != view.round_number:
		return
	for id: int in view.solved:
		if not previous.solved.has(id):
			_show_toast(tr("You got it!") if id == _me() else tr("%s solved theirs!") % view.player_name(id), GOOD_COLOR)
	for id: int in view.wrong_guesses:
		if int(view.wrong_guesses[id]) > int(previous.wrong_guesses.get(id, 0)):
			_show_toast(tr("Wrong guess. Locked until your next turn.") if id == _me() \
				else tr("%s guessed wrong.") % view.player_name(id), BAD_COLOR)


func _fill_end(view: GuessView) -> void:
	for child: Node in _end_list.get_children():
		child.queue_free()
	var pack: IdentityPack = source.call("guess_pack")
	var over: bool = view.phase == GuessMatch.Phase.GAME_OVER
	if over:
		var names: PackedStringArray = []
		for id: int in view.winner_ids:
			names.append(tr("YOU") if id == _me() else view.player_name(id).to_upper())
		if names.is_empty():
			_end_title.text = tr("GAME OVER")
		elif names.size() == 1 and not view.winner_ids.has(_me()):
			_end_title.text = tr("%s WINS") % names[0]
		else:
			_end_title.text = tr("%s WIN") % " & ".join(names)
	else:
		_end_title.text = tr("ROUND %d OVER") % view.round_number
	var place: int = 1
	for player: PlayerState in view.standings():
		var line := Label.new()
		var entry: IdentityPack.Entry = pack.get_entry(view.identity_of(player.id)) if pack != null and not over else null
		if over:
			line.text = "%d.  %s   %d" % [place, player.name, view.score_of(player.id)]
		else:
			var solved: String = tr("solved") if view.is_solved(player.id) else tr("not solved")
			line.text = "%s was %s   (%s, %+d)" % [player.name, entry.name if entry != null else "?", solved,
				int(view.round_points.get(player.id, 0))]
		var winner: bool = over and view.winner_ids.has(player.id)
		line.add_theme_color_override("font_color", WINNER_COLOR if winner else (GOOD_COLOR if view.is_solved(player.id) and not over else TEXT_COLOR))
		_end_list.add_child(line)
		place += 1
	var host: bool = bool(source.call("is_host"))
	_end_buttons.visible = over
	(_end_buttons.get_node("LobbyButton") as Button).visible = host
	_wait_label.visible = over and not host


func _answer(value: int) -> void:
	if _view != null and _view.can_answer(_me()):
		source.call("answer_question", value)


func _me() -> int:
	return int(source.call("local_peer_id"))


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- Building -----------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _build_theme()
	add_child(_root)

	_top_bar = PanelContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top_bar.offset_top = 12
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	_phase_label = Label.new()
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 26)
	_score_label = Label.new()
	top.add_child(_phase_label)
	top.add_child(_timer_label)
	top.add_child(_score_label)
	_top_bar.add_child(top)
	_top_bar.visible = false
	_root.add_child(_top_bar)

	_board = PanelContainer.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_board.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board.offset_top = 80
	_board.offset_right = -16
	_board.custom_minimum_size = Vector2(220, 0)
	_board_list = VBoxContainer.new()
	_board.add_child(_board_list)
	_board.visible = false
	_root.add_child(_board)

	_question_bar = PanelContainer.new()
	_question_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_question_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_question_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_question_bar.offset_bottom = -64
	_question_bar.custom_minimum_size = Vector2(760, 0)
	var question := VBoxContainer.new()
	question.add_theme_constant_override("separation", 8)
	_question_label = Label.new()
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_label.add_theme_font_size_override("font_size", 28)
	_question_status = Label.new()
	_question_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_status.add_theme_color_override("font_color", DIM_COLOR)
	_answer_row = HBoxContainer.new()
	_answer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_answer_row.add_theme_constant_override("separation", 16)
	for pair: Array in [[GuessMatch.Answer.YES, tr("YES  [1]")], [GuessMatch.Answer.NO, tr("NO  [2]")],
			[GuessMatch.Answer.UNSURE, tr("DON'T KNOW  [3]")]]:
		var button := Button.new()
		button.text = pair[1]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(180, 52)
		button.pressed.connect(_answer.bind(int(pair[0])))
		_answer_row.add_child(button)
		_answer_buttons[int(pair[0])] = button
	question.add_child(_question_label)
	question.add_child(_answer_row)
	question.add_child(_question_status)
	_question_bar.add_child(question)
	_question_bar.visible = false
	_root.add_child(_question_bar)

	_banner = _overlay_label(40, 0.3)
	_toast = _overlay_label(30, 0.42)

	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.custom_minimum_size = Vector2(620, 0)
	var end := VBoxContainer.new()
	end.add_theme_constant_override("separation", 10)
	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 42)
	_end_title.add_theme_color_override("font_color", WINNER_COLOR)
	_end_list = VBoxContainer.new()
	_end_buttons = HBoxContainer.new()
	_end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_buttons.add_theme_constant_override("separation", 20)
	var lobby := Button.new()
	lobby.name = "LobbyButton"
	lobby.text = tr("Play again")
	lobby.custom_minimum_size = Vector2(220, 56)
	lobby.pressed.connect(func() -> void: source.call("return_to_lobby"))
	var menu := Button.new()
	menu.name = "MenuButton"
	menu.text = tr("Leave")
	menu.custom_minimum_size = Vector2(220, 56)
	menu.pressed.connect(func() -> void: source.call("leave"))
	_end_buttons.add_child(lobby)
	_end_buttons.add_child(menu)
	_wait_label = Label.new()
	_wait_label.text = tr("Waiting for the host...")
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_label.add_theme_color_override("font_color", DIM_COLOR)
	end.add_child(_end_title)
	end.add_child(_end_list)
	end.add_child(_end_buttons)
	end.add_child(_wait_label)
	_end_panel.add_child(end)
	_end_panel.visible = false
	_root.add_child(_end_panel)


func _overlay_label(size: int, height: float) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	label.anchor_top = height
	label.anchor_bottom = height
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.modulate.a = 0.0
	_root.add_child(label)
	return label


## Dark translucent panels, outlined text over the dim room.
func _build_theme() -> Theme:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.04, 0.08, 0.78)
	panel.border_color = Color(0.2, 0.36, 0.52, 0.85)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(12)
	var hud_theme := Theme.new()
	hud_theme.default_font_size = 22
	hud_theme.set_stylebox("panel", "PanelContainer", panel)
	hud_theme.set_color("font_color", "Label", TEXT_COLOR)
	hud_theme.set_color("font_outline_color", "Label", Color.BLACK)
	hud_theme.set_constant("outline_size", "Label", 6)
	return hud_theme
