class_name SearchTerminal
extends Control
## Guess mode's database terminal on the player's CRT (800x600, inside a SubViewport, same
## phosphor look as the meme editor). Search the identity pack for who you might be:
##
## - FILTERS: pick a field, a value and an operator ("Born before 1970", "Genres: rock").
## - CLUES: the answers to your questions this round; a clear answer to a stock question
##   becomes a filter with one click (never by itself: people can answer wrong).
## - ASK: on your turn, type your own yes/no question or pick a stock question.
## - While someone else's question is on the TV, an answer bar: YES / NO / DON'T KNOW.
## - Results: best known first, with the count going down as you narrow it. Right-click
##   crosses a candidate out; everyone else's identities (on their placards) are crossed
##   out for you. Select one and press GUESS.
##
## The terminal is a view: it searches locally (the pack is public data) and only emits
## what the player wants to do. GuessPresenter sends that to Session and feeds the
## terminal every new GuessView.

signal ask_requested(text: String)
signal stock_requested(index: int)
signal guess_requested(entry_id: String)
## The player answered the question on the TV (a GuessMatch.Answer). The HUD is hidden
## while the camera is zoomed into the CRT, so the terminal offers the answers too.
signal answer_requested(value: int)

enum Pane { FILTERS, CLUES, ASK }

## The results list shows at most this many rows (the count still says how many match).
const MAX_ROWS: int = 150
const QUESTION_MAX_LENGTH: int = 80
## Facts shown next to a result's name.
const ROW_FACTS: int = 2
const TEXT_SMALL: int = 14
const TEXT_LIST: int = 15

var pack: IdentityPack
var query := IdentityQuery.new()
## Show the selected candidate's Commons portrait (fetched from the internet).
var portraits_enabled: bool = false

var _view: GuessView
var _me: int = 0
var _pane: Pane = Pane.FILTERS
var _field: IdentityPack.Field
## Each row of the value list: the value a filter would use (String, bool or decade int).
var _values: Array = []
## The ids shown in the results list, in its order.
var _row_ids: PackedStringArray = []
var _selected_id: String = ""
## Open-candidate counts after each change this round, for "1263 -> 37 -> 6".
var _counts: Array[int] = []
## Entry id -> name of the player whose placard shows it.
var _placards: Dictionary = {}
## Clue indexes (into this round's clue log) already turned into filters.
var _applied_clues: Dictionary = {}
var _seen_clues: int = 0
## How many clues the player has had the CLUES pane open for (the tab stars new ones).
var _clues_read: int = 0
var _last_guess: String = ""
var _round: int = -1
var _time_left: float = -1.0

var _title: Label
var _count_label: Label
var _timer_label: Label
var _pane_buttons: Dictionary = {}  # Pane -> Button
var _panes: Dictionary = {}  # Pane -> Control
var _chips: HFlowContainer
var _field_flow: HFlowContainer
var _field_buttons: Dictionary = {}  # field id -> Button
var _value_list: ItemList
var _op_row: HBoxContainer
var _clue_box: VBoxContainer
var _ask_status: Label
var _own_edit: LineEdit
var _ask_button: Button
var _stock_list: ItemList
var _stock_button: Button
var _search_edit: LineEdit
var _result_list: ItemList
var _detail_label: Label
var _portrait: TextureRect
## The portrait URL the detail pane is waiting for ("" when none).
var _portrait_url: String = ""
var _status_label: Label
var _guess_button: Button
var _answer_bar: Control
var _answer_label: Label
var _answer_buttons: Dictionary = {}  # GuessMatch.Answer -> Button


func _ready() -> void:
	theme = CrtTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inside a SubViewport the anchors have no parent Control to follow.
	if not get_parent() is Control:
		set_deferred("size", Vector2(get_viewport_rect().size))
	_build()
	show_pane(Pane.FILTERS)
	_refresh_all()


## Starts over with [param p_pack] (a new game or a new round).
func set_pack(p_pack: IdentityPack) -> void:
	pack = p_pack
	_field = null
	reset()


## Forgets this round's search: filters, crossed-out candidates, clues, counts.
func reset() -> void:
	query = IdentityQuery.new()
	_counts.clear()
	_placards.clear()
	_applied_clues.clear()
	_seen_clues = 0
	_clues_read = 0
	_last_guess = ""
	_selected_id = ""
	if _search_edit != null:
		_search_edit.text = ""
	if is_node_ready():
		_build_field_buttons()
		_refresh_all()


## Feeds the terminal the latest state as [param me] sees it.
func apply_view(view: GuessView, me: int) -> void:
	var previous: GuessView = _view
	_view = view
	_me = me
	if view.round_number != _round:
		_round = view.round_number
		reset()
		previous = null
	# A wrong guess crosses that candidate out.
	if previous != null and int(view.wrong_guesses.get(me, 0)) > int(previous.wrong_guesses.get(me, 0)) \
			and not _last_guess.is_empty():
		query.struck[_last_guess] = true
	# Identities on the other players' placards aren't ours.
	var changed: bool = false
	for player_id: int in view.identities:
		var entry_id: String = view.identities[player_id]
		if player_id != me and not _placards.has(entry_id):
			_placards[entry_id] = view.player_name(player_id)
			query.struck[entry_id] = true
			changed = true
	var clues: Array = view.clues.get(me, [])
	var new_clue: bool = clues.size() > _seen_clues
	_seen_clues = clues.size()
	if view.can_ask(me) and (previous == null or not previous.can_ask(me)):
		show_pane(Pane.ASK)
		_own_edit.grab_focus.call_deferred()
	elif new_clue and _pane == Pane.ASK:
		show_pane(Pane.CLUES)
	elif _pane == Pane.ASK and previous != null and previous.can_ask(me) and not view.can_ask(me) \
			and view.phase == GuessMatch.Phase.ASK:
		show_pane(Pane.FILTERS)  # the turn ran out without a question
	if changed:
		_refresh_results()
	_refresh_clues()
	_refresh_ask()
	_refresh_answer_bar()
	_refresh_footer()


## Round clock in seconds; negative hides it.
func set_time_left(seconds: float) -> void:
	_time_left = seconds
	if _timer_label == null:
		return
	_timer_label.visible = seconds >= 0.0
	var whole: int = ceili(maxf(0.0, seconds))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]


func show_pane(pane: Pane) -> void:
	_pane = pane
	for key: Pane in _panes:
		(_panes[key] as Control).visible = key == pane
		(_pane_buttons[key] as Button).set_pressed_no_signal(key == pane)
	if pane == Pane.CLUES and _clue_box != null:
		_refresh_clues()


func get_pane() -> Pane:
	return _pane


## The keyboard goes to the name search when the camera zooms in (or the question box on
## your turn).
func focus_first_field() -> void:
	if _pane == Pane.ASK and _own_edit.editable:
		_own_edit.grab_focus()
	else:
		_search_edit.grab_focus()


func add_filter(filter: IdentityFilter) -> void:
	if filter == null:
		return
	for existing: IdentityFilter in query.filters:
		if existing.to_dict() == filter.to_dict():
			return
	query.add_filter(filter)
	_refresh_results()


func remove_filter(index: int) -> void:
	query.remove_filter(index)
	_refresh_results()


func set_search_text(text: String) -> void:
	_search_edit.text = text
	query.text = text
	_refresh_results()


func toggle_struck(entry_id: String) -> void:
	query.toggle_struck(entry_id)
	_refresh_results()


## Turns clue number [param index] of this round into a filter (stock questions with a
## clear Yes or No only).
func apply_clue(index: int) -> void:
	var filter: IdentityFilter = _clue_filter(index)
	if filter == null:
		return
	_applied_clues[index] = true
	add_filter(filter)
	_refresh_clues()


## Ids of the results list, in order (best known open candidates first).
func result_ids() -> PackedStringArray:
	return _row_ids


func open_count() -> int:
	return query.count_open(pack) if pack != null else 0


func select_entry(entry_id: String) -> void:
	_selected_id = entry_id
	var index: int = _row_ids.find(entry_id)
	if index >= 0:
		_result_list.select(index)
	else:
		_result_list.deselect_all()
	_refresh_detail()
	_refresh_footer()


func selected_entry() -> String:
	return _selected_id


## Picks a field for the filter builder.
func select_field(field_id: String) -> void:
	_field = pack.get_field(field_id) if pack != null else null
	for id: String in _field_buttons:
		(_field_buttons[id] as Button).set_pressed_no_signal(id == field_id)
	_refresh_values()


## Builds a filter from the field builder: row [param value_index] of the value list with
## operator [param op] (an IdentityFilter op, or "decade"/"not_decade" for year fields).
func add_built_filter(value_index: int, op: String) -> void:
	if _field == null or value_index < 0 or value_index >= _values.size():
		return
	var value: Variant = _values[value_index]
	var data: Dictionary = {"field": _field.id, "op": op, "value": value}
	if op == "decade" or op == "not_decade":
		data["op"] = "between" if op == "decade" else "not_between"
		data["value"] = [int(value), int(value) + 9]
	add_filter(IdentityFilter.from_untrusted(data, pack))


func ask_own(text: String) -> void:
	var clean: String = MemeSpec.sanitize_caption(text).substr(0, QUESTION_MAX_LENGTH)
	if clean.is_empty() or _view == null or not _view.can_ask(_me):
		return
	_own_edit.text = ""
	ask_requested.emit(clean)


func ask_stock(index: int) -> void:
	if pack == null or pack.stock_question(index) == null or _view == null or not _view.can_ask(_me):
		return
	stock_requested.emit(index)


func guess_selected() -> void:
	if _selected_id.is_empty() or _view == null or not _view.can_guess(_me):
		return
	_last_guess = _selected_id
	guess_requested.emit(_selected_id)


# --- Refreshing ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_title.text = (tr("%s DATABASE") % pack.name.to_upper()) if pack != null else tr("DATABASE")
	_refresh_values()
	_refresh_results()
	_refresh_clues()
	_refresh_ask()
	_refresh_footer()


func _refresh_results() -> void:
	if pack == null or _result_list == null:
		return
	_refresh_chips()
	var results: Array[IdentityPack.Entry] = query.run(pack)
	var open: int = query.count_open(pack)
	if _counts.is_empty() or _counts[-1] != open:
		_counts.append(open)
	_result_list.clear()
	_row_ids.clear()
	for entry: IdentityPack.Entry in results.slice(0, MAX_ROWS):
		var struck: bool = query.is_struck(entry.id)
		var row: int = _result_list.add_item(("×  " if struck else "") + entry.name + _facts(entry))
		if struck:
			_result_list.set_item_custom_fg_color(row, CrtTheme.PHOSPHOR_DIM)
		_row_ids.append(entry.id)
	if _row_ids.has(_selected_id):
		_result_list.select(_row_ids.find(_selected_id))
	var history: Array[String] = []
	for count: int in _counts.slice(-4):
		history.append(str(count))
	_count_label.text = (tr("%s left") % "  →  ".join(history)) if open != pack.size() or _counts.size() > 1 \
		else tr("%d candidates") % open
	_refresh_values()
	_refresh_detail()
	_refresh_footer()


func _refresh_chips() -> void:
	for child: Node in _chips.get_children():
		child.queue_free()
	if query.filters.is_empty():
		var none := Label.new()
		none.text = tr("No filters yet.")
		none.add_theme_font_size_override("font_size", TEXT_SMALL)
		none.add_theme_color_override("font_color", CrtTheme.PHOSPHOR_DIM)
		_chips.add_child(none)
		return
	for i: int in query.filters.size():
		var chip := _button("×  " + query.filters[i].describe(), 13)
		chip.tooltip_text = tr("Remove this filter")
		chip.pressed.connect(remove_filter.bind(i))
		_chips.add_child(chip)


## The value list for the chosen field, with how many open candidates have each value.
func _refresh_values() -> void:
	if _value_list == null:
		return
	_value_list.clear()
	_values.clear()
	for child: Node in _op_row.get_children():
		child.queue_free()
	if pack == null or _field == null:
		_value_list.add_item(tr("Pick a field above."))
		_value_list.set_item_disabled(0, true)
		return
	var counts: Dictionary = {}
	for entry: IdentityPack.Entry in pack.entries():
		if query.is_struck(entry.id) or not query.matches(entry) or not entry.has_value(_field.id):
			continue
		var value: Variant = entry.value(_field.id)
		match _field.type:
			"tags":
				for tag: String in value as PackedStringArray:
					counts[tag] = int(counts.get(tag, 0)) + 1
			"year":
				var decade: int = floori(int(value) / 10.0) * 10
				counts[decade] = int(counts.get(decade, 0)) + 1
			_:
				counts[value] = int(counts.get(value, 0)) + 1
	var keys: Array = counts.keys()
	if _field.type == "year" or _field.type == "bool":
		keys.sort()
		if _field.type == "bool":
			keys.reverse()  # yes first
	else:
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return counts[a] > counts[b] if counts[a] != counts[b] else str(a) < str(b))
	for key: Variant in keys:
		_values.append(key)
		_value_list.add_item("%s  (%d)" % [_value_text(key), counts[key]])
	if _values.is_empty():
		_value_list.add_item(tr("No candidate has this field."))
		_value_list.set_item_disabled(0, true)
	var ops: Array = []
	match _field.type:
		"enum":
			ops = [["is", tr("IS")], ["is_not", tr("IS NOT")]]
		"tags":
			ops = [["has", tr("HAS")], ["has_not", tr("HAS NOT")]]
		"bool":
			ops = [["is", tr("IS")]]
		"year":
			ops = [["decade", tr("IN")], ["not_decade", tr("NOT IN")], ["before", tr("BEFORE")], ["from", tr("FROM")]]
	for op: Array in ops:
		var button := _button(op[1], 13)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_op_pressed.bind(str(op[0])))
		_op_row.add_child(button)


func _refresh_detail() -> void:
	if _detail_label == null:
		return
	var entry: IdentityPack.Entry = pack.get_entry(_selected_id) if pack != null else null
	_show_portrait(entry)
	if entry == null:
		_detail_label.text = tr("Select a candidate. Right-click crosses one out.")
		return
	var facts: PackedStringArray = []
	for field: IdentityPack.Field in pack.fields():
		if entry.has_value(field.id):
			facts.append("%s: %s" % [field.name, _value_text(entry.value(field.id), field.type)])
	var text: String = entry.name + "\n" + "  ·  ".join(facts)
	if _placards.has(entry.id):
		text += "\n" + tr("On %s's placard, so not you.") % _placards[entry.id]
	_detail_label.text = text


func _show_portrait(entry: IdentityPack.Entry) -> void:
	var url: String = Portrait.url_for(entry.image) if entry != null and portraits_enabled else ""
	_portrait_url = url
	_portrait.texture = null
	_portrait.visible = not url.is_empty()
	if url.is_empty():
		return
	var cache: TemplateImageCache = TemplateImageCache.get_instance()
	if not cache.loaded.is_connected(_on_portrait_loaded):
		cache.loaded.connect(_on_portrait_loaded)
		cache.failed.connect(_on_portrait_failed)
	_portrait.texture = cache.get_texture(url)
	_portrait.visible = _portrait.texture != null or not cache.has_failed(url)


func _on_portrait_failed(url: String) -> void:
	if url == _portrait_url and _portrait != null:
		_portrait.visible = false


func _on_portrait_loaded(url: String, texture: Texture2D) -> void:
	if url == _portrait_url and _portrait != null:
		_portrait.texture = texture


func _refresh_clues() -> void:
	if _clue_box == null:
		return
	for child: Node in _clue_box.get_children():
		child.queue_free()
	var clues: Array = _view.clues.get(_me, []) if _view != null else []
	if clues.is_empty():
		var empty := Label.new()
		empty.text = tr("Ask questions on your turn.\nThe answers land here.")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", TEXT_SMALL)
		empty.add_theme_color_override("font_color", CrtTheme.PHOSPHOR_DIM)
		_clue_box.add_child(empty)
	for i: int in clues.size():
		var clue: Dictionary = clues[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		var answer: int = int(clue.get("answer", GuessMatch.Answer.UNSURE))
		label.text = "%s\n→ %s" % [str(clue.get("text", "")), answer_text(answer)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", TEXT_SMALL)
		if answer == GuessMatch.Answer.NO:
			label.add_theme_color_override("font_color", CrtTheme.AMBER)
		elif answer == GuessMatch.Answer.UNSURE:
			label.add_theme_color_override("font_color", CrtTheme.PHOSPHOR_DIM)
		row.add_child(label)
		if _clue_filter(i) != null:
			var applied: bool = _applied_clues.has(i)
			var use := _button(tr("ADDED") if applied else tr("FILTER"), 12)
			use.disabled = applied
			use.tooltip_text = _clue_filter(i).describe()
			use.pressed.connect(apply_clue.bind(i))
			row.add_child(use)
		_clue_box.add_child(row)
	var label: String = tr("CLUES")
	if not clues.is_empty():
		label = tr("CLUES %d") % clues.size()
		if _pane == Pane.CLUES:
			_clues_read = clues.size()
		elif clues.size() > _clues_read:
			label += "*"
	(_pane_buttons[Pane.CLUES] as Button).text = label


func _refresh_ask() -> void:
	if _ask_status == null:
		return
	var my_turn: bool = _view != null and _view.can_ask(_me)
	_own_edit.editable = my_turn
	_ask_button.disabled = not my_turn
	_stock_button.disabled = not my_turn or _stock_list.get_selected_items().is_empty()
	if _stock_list.item_count == 0 and pack != null:
		for question: IdentityPack.StockQuestion in pack.stock_questions():
			_stock_list.add_item(question.text)
	if _view == null:
		_ask_status.text = tr("Waiting for the game.")
	elif my_turn:
		_ask_status.text = tr("YOUR TURN. Ask one yes/no question.")
	elif _view.is_solved(_me):
		_ask_status.text = tr("You solved yours. Help the others.")
	elif _view.asker_id != 0:
		_ask_status.text = tr("%s is asking.") % _view.player_name(_view.asker_id)
	else:
		_ask_status.text = tr("Wait for your turn.")
	var asked: Dictionary = {}
	var clues: Array = _view.clues.get(_me, []) if _view != null else []
	for clue: Variant in clues:
		asked[int((clue as Dictionary).get("stock", -1))] = true
	for i: int in _stock_list.item_count:
		_stock_list.set_item_custom_fg_color(i, CrtTheme.PHOSPHOR_DIM if asked.has(i) else CrtTheme.PHOSPHOR)


func _refresh_answer_bar() -> void:
	if _answer_bar == null:
		return
	_answer_bar.visible = _view != null and _view.can_answer(_me)
	if not _answer_bar.visible:
		return
	_answer_label.text = tr("%s asks: %s") % [_view.player_name(_view.asker_id), _view.question_text]
	for value: int in _answer_buttons:
		(_answer_buttons[value] as Button).set_pressed_no_signal(_view.my_answered and _view.my_answer == value)


func answer(value: int) -> void:
	if _view != null and _view.can_answer(_me):
		answer_requested.emit(value)


func _refresh_footer() -> void:
	if _guess_button == null:
		return
	var entry: IdentityPack.Entry = pack.get_entry(_selected_id) if pack != null else null
	var can: bool = _view != null and _view.can_guess(_me)
	_guess_button.disabled = not can or entry == null
	_guess_button.text = (tr("GUESS: %s") % _shorten(entry.name, 22)) if entry != null else tr("GUESS")
	if _view == null:
		_status_label.text = ""
	elif _view.is_solved(_me):
		var mine: IdentityPack.Entry = pack.get_entry(_view.identity_of(_me)) if pack != null else null
		_status_label.text = tr("SOLVED: you are %s.") % (mine.name if mine != null else "?")
	elif _view.locked.has(_me):
		_status_label.text = tr("Wrong guess. Locked until your next turn.")
	elif _view.in_turns():
		_status_label.text = tr("Narrow it down, then guess.")
	else:
		_status_label.text = tr("Guessing opens when the turns start.")


# --- Input --------------------------------------------------------------------------------

func _on_op_pressed(op: String) -> void:
	var selected: PackedInt32Array = _value_list.get_selected_items()
	if selected.is_empty():
		return
	add_built_filter(selected[0], op)


func _on_result_clicked(index: int, _at: Vector2, button: int) -> void:
	if index < 0 or index >= _row_ids.size():
		return
	if button == MOUSE_BUTTON_RIGHT:
		toggle_struck(_row_ids[index])
	else:
		select_entry(_row_ids[index])


# --- Building -----------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = CrtTheme.SCREEN_BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The barrel curve eats the edges of the glass.
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_title = _label("", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label = _label("", 16)
	_timer_label = _label("", 30)
	header.add_child(_title)
	header.add_child(_count_label)
	header.add_child(_timer_label)
	column.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_results())

	column.add_child(_build_answer_bar())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_status_label = _label("", 16)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guess_button = _button(tr("GUESS"), 20)
	_guess_button.name = "GuessButton"
	_guess_button.custom_minimum_size = Vector2(270, 46)
	_guess_button.pressed.connect(guess_selected)
	footer.add_child(_status_label)
	footer.add_child(_guess_button)
	column.add_child(footer)
	set_time_left(-1.0)


func _build_answer_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_answer_label = _label("", 16)
	_answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_answer_label.max_lines_visible = 2
	_answer_label.add_theme_color_override("font_color", Color.WHITE)
	bar.add_child(_answer_label)
	for pair: Array in [[GuessMatch.Answer.YES, tr("YES")], [GuessMatch.Answer.NO, tr("NO")], [GuessMatch.Answer.UNSURE, tr("DON'T KNOW")]]:
		var button := _button(pair[1], 15)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(70, 40)
		button.pressed.connect(answer.bind(int(pair[0])))
		bar.add_child(button)
		_answer_buttons[int(pair[0])] = button
	_answer_bar = bar
	bar.visible = false
	return bar


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(318, 0)
	left.add_theme_constant_override("separation", 6)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for pane: Pane in [Pane.FILTERS, Pane.CLUES, Pane.ASK]:
		var label: String = [tr("FILTERS"), tr("CLUES"), tr("ASK")][pane]
		var tab := _button(label, 15)
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_pane.bind(pane))
		tabs.add_child(tab)
		_pane_buttons[pane] = tab
	left.add_child(tabs)
	_panes[Pane.FILTERS] = _build_filters()
	_panes[Pane.CLUES] = _build_clues()
	_panes[Pane.ASK] = _build_ask()
	for pane: Pane in _panes:
		(_panes[pane] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(_panes[pane])
	return left


func _build_filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 4)
	_chips.add_theme_constant_override("v_separation", 4)
	box.add_child(_chips)
	_field_flow = HFlowContainer.new()
	_field_flow.add_theme_constant_override("h_separation", 4)
	_field_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_field_flow)
	_value_list = ItemList.new()
	_value_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_value_list.add_theme_font_size_override("font_size", TEXT_SMALL)
	_value_list.item_activated.connect(func(index: int) -> void: add_built_filter(index, _default_op()))
	box.add_child(_value_list)
	_op_row = HBoxContainer.new()
	_op_row.add_theme_constant_override("separation", 4)
	box.add_child(_op_row)
	_build_field_buttons()
	return box


func _build_field_buttons() -> void:
	if _field_flow == null:
		return
	for child: Node in _field_flow.get_children():
		child.queue_free()
	_field_buttons.clear()
	if pack == null:
		return
	for field: IdentityPack.Field in pack.fields():
		var button := _button(field.name, 13)
		button.toggle_mode = true
		button.pressed.connect(select_field.bind(field.id))
		_field_flow.add_child(button)
		_field_buttons[field.id] = button
	if _field == null and not pack.fields().is_empty():
		select_field(pack.fields()[0].id)
	elif _field != null:
		select_field(_field.id)


func _build_clues() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_clue_box = VBoxContainer.new()
	_clue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clue_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_clue_box)
	return scroll


func _build_ask() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_ask_status = _label("", 16)
	_ask_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ask_status)
	var own := HBoxContainer.new()
	_own_edit = LineEdit.new()
	_own_edit.placeholder_text = tr("Your own question")
	_own_edit.max_length = QUESTION_MAX_LENGTH
	_own_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_own_edit.add_theme_font_size_override("font_size", 16)
	_own_edit.text_submitted.connect(ask_own)
	_ask_button = _button(tr("ASK"), 15)
	_ask_button.pressed.connect(func() -> void: ask_own(_own_edit.text))
	own.add_child(_own_edit)
	own.add_child(_ask_button)
	box.add_child(own)
	box.add_child(_label(tr("Or a stock question:"), TEXT_SMALL))
	_stock_list = ItemList.new()
	_stock_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stock_list.add_theme_font_size_override("font_size", TEXT_SMALL)
	_stock_list.item_selected.connect(func(_i: int) -> void: _refresh_ask())
	_stock_list.item_activated.connect(ask_stock)
	box.add_child(_stock_list)
	_stock_button = _button(tr("ASK THIS ONE"), 15)
	_stock_button.pressed.connect(func() -> void:
		var selected: PackedInt32Array = _stock_list.get_selected_items()
		if not selected.is_empty():
			ask_stock(selected[0]))
	box.add_child(_stock_button)
	return box


func _build_results() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = tr("Search names")
	_search_edit.add_theme_font_size_override("font_size", 16)
	_search_edit.text_changed.connect(func(text: String) -> void:
		query.text = text
		_refresh_results())
	right.add_child(_search_edit)
	_result_list = ItemList.new()
	_result_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_list.add_theme_font_size_override("font_size", TEXT_LIST)
	_result_list.allow_rmb_select = true
	_result_list.item_clicked.connect(_on_result_clicked)
	_result_list.item_activated.connect(func(index: int) -> void: select_entry(_row_ids[index]))
	right.add_child(_result_list)
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(60, 72)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# A green tint keeps the photo on the phosphor screen's palette.
	_portrait.modulate = CrtTheme.PHOSPHOR.lerp(Color.WHITE, 0.45)
	_portrait.visible = false
	detail.add_child(_portrait)
	_detail_label = _label("", 13)
	_detail_label.custom_minimum_size = Vector2(0, 72)
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.max_lines_visible = 4
	detail.add_child(_detail_label)
	right.add_child(detail)
	return right


# --- Helpers ------------------------------------------------------------------------------

## A GuessMatch.Answer as the terminal and the TV say it.
static func answer_text(answer: int) -> String:
	match answer:
		GuessMatch.Answer.YES:
			return TranslationServer.translate("YES")
		GuessMatch.Answer.NO:
			return TranslationServer.translate("NO")
	return TranslationServer.translate("UNCLEAR")


func _clue_filter(index: int) -> IdentityFilter:
	var clues: Array = _view.clues.get(_me, []) if _view != null else []
	if pack == null or index < 0 or index >= clues.size():
		return null
	var clue: Dictionary = clues[index]
	var stock: IdentityPack.StockQuestion = pack.stock_question(int(clue.get("stock", -1)))
	var answer: int = int(clue.get("answer", GuessMatch.Answer.UNSURE))
	if stock == null or answer == GuessMatch.Answer.UNSURE:
		return null
	return stock.filter if answer == GuessMatch.Answer.YES else stock.filter.negated()


func _default_op() -> String:
	match _field.type if _field != null else "":
		"tags":
			return "has"
		"year":
			return "decade"
	return "is"


func _facts(entry: IdentityPack.Entry) -> String:
	var facts: PackedStringArray = []
	# The year first (it tells most), then the first enum fields.
	for type: String in ["year", "enum"]:
		for field: IdentityPack.Field in pack.fields():
			if facts.size() < ROW_FACTS and field.type == type and entry.has_value(field.id):
				facts.append(_shorten(str(entry.value(field.id)), 16))
	return ("   " + " · ".join(facts)) if not facts.is_empty() else ""


func _value_text(value: Variant, type: String = "") -> String:
	var kind: String = type if not type.is_empty() else (_field.type if _field != null else "")
	match kind:
		"bool":
			return tr("yes") if bool(value) else tr("no")
		"year":
			return ("%ds" % int(value)) if type.is_empty() else str(value)
		"tags":
			if value is PackedStringArray:
				return ", ".join(value as PackedStringArray)
	return str(value)


static func _shorten(text: String, length: int) -> String:
	return text if text.length() <= length else text.substr(0, length - 1) + "…"


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", size)
	return button
