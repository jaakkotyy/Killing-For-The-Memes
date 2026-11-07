class_name MemeEditor
extends Control
## The 2D meme editor shown on the player's CRT (800x600, inside a SubViewport): pick a
## template, type top and bottom captions, press Done. It only edits a local draft and
## reports it; the round loop (M5) sends it to the server.
##
## The template list can be narrowed to one source (Imgflip, GIFs, Reddit, ours) or show a
## search: the editor emits search_requested and whoever runs the editor answers with
## show_search_results() (MatchPresenter, through the host).
##
## Players may resubmit until time runs out. When time runs out the current draft is
## submitted automatically, so forgetting to press Done never costs a round.

signal submitted(spec: MemeSpec)
signal draft_changed(spec: MemeSpec)
## The player searched for templates; answer with show_search_results().
signal search_requested(query: String)
## Emitted once when the countdown reaches zero, after the automatic submit.
signal time_ran_out

const PHOSPHOR: Color = CrtTheme.PHOSPHOR
const PHOSPHOR_DIM: Color = CrtTheme.PHOSPHOR_DIM
const SCREEN_BG: Color = CrtTheme.SCREEN_BG
const THUMB_SIZE: Vector2i = Vector2i(104, 78)

## Which templates the list shows.
enum Source { ALL, IMGFLIP, GIFS, REDDIT, OURS, FOUND }
const SOURCE_LABELS: Dictionary = {
	Source.ALL: "All", Source.IMGFLIP: "Imgflip", Source.GIFS: "GIFs", Source.REDDIT: "Reddit",
	Source.OURS: "Ours", Source.FOUND: "Found",
}

var library: MemeTemplateLibrary

var _time_left: float = -1.0
var _template_id: String = ""
var _has_submitted: bool = false
var _submitted_spec: MemeSpec
## The ids in the list, in its order (the list never indexes library.ids() directly, so a
## catalogue that changes under it can't mix up names and pictures).
var _list_ids: PackedStringArray = []
var _source: Source = Source.ALL
var _source_buttons: Dictionary = {}  # Source -> Button
var _found_ids: PackedStringArray = []
var _found_query: String = ""
## The search waiting for an answer ("" when none).
var _pending_query: String = ""

@onready var _prompt_label: Label = %PromptLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _preview: MemeRenderer = %Preview
@onready var _top_edit: LineEdit = %TopEdit
@onready var _bottom_edit: LineEdit = %BottomEdit
@onready var _done_button: Button = %DoneButton
@onready var _status_label: Label = %StatusLabel
@onready var _template_list: ItemList = %TemplateList
@onready var _hint: Label = %Hint
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _source_bar: HFlowContainer = %SourceBar
@onready var _list_status: Label = %ListStatus


func _ready() -> void:
	if library == null:
		library = MemeTemplateLibrary.get_default()
	theme = _build_theme()
	_preview.library = library
	for edit: LineEdit in [_top_edit, _bottom_edit]:
		edit.max_length = MemeSpec.CAPTION_MAX_LENGTH
		edit.text_changed.connect(_on_text_changed.unbind(1))
	_top_edit.text_submitted.connect(func(_t: String) -> void: _bottom_edit.grab_focus())
	_bottom_edit.text_submitted.connect(func(_t: String) -> void: submit())
	_done_button.pressed.connect(submit)
	_template_list.item_selected.connect(_on_template_selected)
	_template_list.fixed_icon_size = THUMB_SIZE
	_search_edit.max_length = TemplateSearch.MAX_QUERY_LENGTH
	_search_edit.text_submitted.connect(search)
	_build_source_bar()
	library.image_updated.connect(_on_image_updated)
	library.templates_changed.connect(_on_templates_changed)
	_on_templates_changed()
	_update_status()
	set_time_left(-1.0)


func set_prompt(prompt: String) -> void:
	_prompt_label.text = prompt


## Seconds until creation ends; negative hides the timer.
func set_time_left(seconds: float) -> void:
	_time_left = seconds
	_timer_label.visible = seconds >= 0.0
	_update_timer_label()


## The current draft (what would be submitted now).
func get_draft() -> MemeSpec:
	return MemeSpec.new(_template_id, MemeSpec.sanitize_caption(_top_edit.text),
		MemeSpec.sanitize_caption(_bottom_edit.text))


func has_submitted() -> bool:
	return _has_submitted


## Makes [param id] the draft's template, showing it in the list if it can.
func select_template(id: String) -> void:
	if not library.has(id) and not _found_ids.has(id) and not library.accepts(id):
		return
	if not _list_ids.has(id) and _source != Source.ALL and library.has(id):
		show_source(Source.ALL)
	var index: int = _list_ids.find(id)
	if index >= 0:
		_template_list.select(index)
		# Deferred: before the first layout the list doesn't know its size and scrolls wrongly.
		_template_list.ensure_current_is_visible.call_deferred()
	else:
		_template_list.deselect_all()
	_template_id = id
	_on_text_changed()


## The ids the list shows right now, in order.
func listed_ids() -> PackedStringArray:
	return _list_ids


## Narrows the list to one source.
func show_source(source: Source) -> void:
	_source = source
	for key: Source in _source_buttons:
		(_source_buttons[key] as Button).set_pressed_no_signal(key == source)
	_refresh_list()


## Asks for templates matching [param query] ("r/<subreddit>" for a subreddit's memes).
## An empty query goes back to the whole catalogue.
func search(query: String) -> void:
	var clean: String = TemplateSearch.clean_query(query)
	if clean.is_empty():
		_pending_query = ""
		_found_ids = []
		_found_query = ""
		show_source(Source.ALL)
		return
	_pending_query = clean
	_list_status.text = tr("Searching for \"%s\"...") % clean
	search_requested.emit(clean)


## The answer to search_requested: the ids found (already added to the library). Answers
## to an older search than the latest are ignored.
func show_search_results(query: String, ids: PackedStringArray) -> void:
	if query != _pending_query:
		return
	_pending_query = ""
	_found_ids = ids
	_found_query = query
	show_source(Source.FOUND)


func set_captions(top: String, bottom: String) -> void:
	_top_edit.text = top
	_bottom_edit.text = bottom
	_on_text_changed()


## Stops typing and clicking (e.g. once creation is over or for spectators).
func set_locked(locked: bool) -> void:
	var controls: Array[Control] = [_top_edit, _bottom_edit, _done_button, _template_list, _search_edit]
	for button: Button in _source_buttons.values():
		controls.append(button)
	for control: Control in controls:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	_top_edit.editable = not locked
	_bottom_edit.editable = not locked
	_search_edit.editable = not locked
	_done_button.disabled = locked
	if locked:
		_status_label.text = tr("Time's up.") if _has_submitted else tr("Waiting for the next round.")
	else:
		_update_status()


## A fresh draft for a new round: first template, empty captions, nothing submitted.
func reset() -> void:
	_has_submitted = false
	_submitted_spec = null
	set_time_left(-1.0)
	_top_edit.text = ""
	_bottom_edit.text = ""
	if not _list_ids.is_empty():
		select_template(_list_ids[0])
	elif library.size() > 0:
		select_template(library.ids()[0])
	_update_status()


## Puts the keyboard focus in the first caption field (called after zooming in).
func focus_first_field() -> void:
	_top_edit.grab_focus()


func submit() -> void:
	var draft: MemeSpec = get_draft()
	if draft.is_blank():
		_status_label.text = tr("Pick a template first.")
		return
	_has_submitted = true
	_submitted_spec = draft
	_update_status()
	submitted.emit(draft)


func _process(delta: float) -> void:
	if _time_left < 0.0:
		return
	var before: float = _time_left
	_time_left = maxf(_time_left - delta, 0.0)
	_update_timer_label()
	if before > 0.0 and _time_left == 0.0:
		var draft: MemeSpec = get_draft()
		if not draft.is_blank() and (not _has_submitted or draft.to_dict() != _submitted_spec.to_dict()):
			submit()
		time_ran_out.emit()


func _update_timer_label() -> void:
	var seconds: int = ceili(maxf(_time_left, 0.0))
	_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_timer_label.modulate = Color(1.0, 0.35, 0.3) if _time_left <= 10.0 else Color.WHITE


func _build_source_bar() -> void:
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for source: Source in SOURCE_LABELS:
		var button := Button.new()
		button.text = tr(SOURCE_LABELS[source])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(show_source.bind(source))
		_source_bar.add_child(button)
		_source_buttons[source] = button
	(_source_buttons[_source] as Button).set_pressed_no_signal(true)


func _on_templates_changed() -> void:
	_refresh_list()
	if _template_id.is_empty() or not library.accepts(_template_id):
		if not _list_ids.is_empty():
			select_template(_list_ids[0])
	_update_credits()


## The ids of [param source], in catalogue order.
func _ids_of(source: Source) -> PackedStringArray:
	if source == Source.FOUND:
		return _found_ids
	if source == Source.OURS:
		return library.original_ids()
	if source == Source.ALL:
		return library.ids()
	var result: PackedStringArray = []
	for id: String in library.online_ids():
		var keep: bool = false
		match source:
			Source.IMGFLIP:
				keep = ImgflipCatalogue.is_online_id(id)
			Source.GIFS:
				keep = library.is_animated(id)
			Source.REDDIT:
				keep = RedditCatalogue.is_online_id(id)
		if keep:
			result.append(id)
	return result


func _refresh_list() -> void:
	_list_ids = _ids_of(_source)
	_template_list.clear()
	for id: String in _list_ids:
		var label: String = library.display_name(id)
		var index: int = _template_list.add_item(tr("GIF: %s") % label if library.is_animated(id) else label,
			library.thumbnail(id))
		_template_list.set_item_tooltip(index, label)
	var selected: int = _list_ids.find(_template_id)
	if selected >= 0:
		_template_list.select(selected)
		_template_list.ensure_current_is_visible.call_deferred()
	(_source_buttons[Source.FOUND] as Button).visible = not _found_query.is_empty()
	if _source == Source.FOUND:
		_list_status.text = tr("%d found for \"%s\"") % [_list_ids.size(), _found_query] if not _list_ids.is_empty() \
			else tr("Nothing found for \"%s\"") % _found_query
	else:
		_list_status.text = tr("%d templates") % _list_ids.size()


## Online templates are other people's images; say where they come from. GIPHY's terms
## require "Powered by GIPHY" wherever its results are shown.
func _update_credits() -> void:
	var credits: PackedStringArray = []
	var online: PackedStringArray = library.online_ids()
	for id: String in online:
		if ImgflipCatalogue.is_online_id(id):
			credits.append(tr("Templates via imgflip.com"))
			break
	for id: String in online:
		if RedditCatalogue.is_online_id(id):
			credits.append(tr("Reddit via meme-api.com"))
			break
	if library.has_animated():
		credits.append(tr("Powered by GIPHY"))
	_hint.text = tr("ESC: look up   ·   ENTER: next field / done")
	if not credits.is_empty():
		_hint.text += "   ·   " + "   ·   ".join(credits)


func _on_image_updated(id: String) -> void:
	var index: int = _list_ids.find(id)
	if index >= 0 and index < _template_list.item_count:
		_template_list.set_item_icon(index, library.thumbnail(id))
	if id == _template_id:
		_preview.queue_redraw()


func _on_template_selected(index: int) -> void:
	if index < 0 or index >= _list_ids.size():
		return
	_template_id = _list_ids[index]
	_on_text_changed()


func _on_text_changed() -> void:
	var draft: MemeSpec = get_draft()
	_preview.set_meme(draft)
	_update_status()
	draft_changed.emit(draft)


func _update_status() -> void:
	if not _has_submitted:
		_status_label.text = tr("Not submitted yet")
		_done_button.text = tr("DONE")
	elif get_draft().to_dict() == _submitted_spec.to_dict():
		_status_label.text = tr("Submitted. You can still change it.")
		_done_button.text = tr("RESUBMIT")
	else:
		_status_label.text = tr("Changed since you submitted.")
		_done_button.text = tr("RESUBMIT")


## Green-phosphor terminal look (shared with the guess terminal).
func _build_theme() -> Theme:
	return CrtTheme.build()
