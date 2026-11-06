class_name MemeEditor
extends Control
## The 2D meme editor shown on the player's CRT (800x600, inside a SubViewport): pick a
## template, type top and bottom captions, press Done. It only edits a local draft and
## reports it; the round loop (M5) sends it to the server.
##
## Players may resubmit until time runs out. When time runs out the current draft is
## submitted automatically, so forgetting to press Done never costs a round.

signal submitted(spec: MemeSpec)
signal draft_changed(spec: MemeSpec)
## Emitted once when the countdown reaches zero, after the automatic submit.
signal time_ran_out

const PHOSPHOR: Color = Color(0.45, 1.0, 0.62)
const PHOSPHOR_DIM: Color = Color(0.2, 0.5, 0.3)
const SCREEN_BG: Color = Color(0.02, 0.06, 0.04)
const THUMB_SIZE: Vector2i = Vector2i(112, 84)

var library: MemeTemplateLibrary

var _time_left: float = -1.0
var _template_id: String = ""
var _has_submitted: bool = false
var _submitted_spec: MemeSpec

@onready var _prompt_label: Label = %PromptLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _preview: MemeRenderer = %Preview
@onready var _top_edit: LineEdit = %TopEdit
@onready var _bottom_edit: LineEdit = %BottomEdit
@onready var _done_button: Button = %DoneButton
@onready var _status_label: Label = %StatusLabel
@onready var _template_list: ItemList = %TemplateList
@onready var _hint: Label = %Hint


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
	library.image_updated.connect(_on_image_updated)
	_fill_templates()
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


func select_template(id: String) -> void:
	var index: int = library.ids().find(id)
	if index == -1:
		return
	_template_list.select(index)
	# Deferred: before the first layout the list doesn't know its size and scrolls wrongly.
	_template_list.ensure_current_is_visible.call_deferred()
	_on_template_selected(index)


func set_captions(top: String, bottom: String) -> void:
	_top_edit.text = top
	_bottom_edit.text = bottom
	_on_text_changed()


## Stops typing and clicking (e.g. once creation is over or for spectators).
func set_locked(locked: bool) -> void:
	for control: Control in [_top_edit, _bottom_edit, _done_button, _template_list]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	_top_edit.editable = not locked
	_bottom_edit.editable = not locked
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
	if library.size() > 0:
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


func _fill_templates() -> void:
	_template_list.clear()
	_template_list.fixed_icon_size = THUMB_SIZE
	for id: String in library.ids():
		var label: String = library.display_name(id)
		_template_list.add_item(tr("GIF: %s") % label if library.is_animated(id) else label, library.texture(id))
	if library.size() > 0:
		select_template(library.ids()[0])
	# Online templates are other people's images; say where they come from. GIPHY's terms
	# require "Powered by GIPHY" wherever its results are shown.
	var credits: PackedStringArray = []
	for id: String in library.ids():
		if ImgflipCatalogue.is_online_id(id) and library.is_online(id):
			credits.append(tr("Popular templates via imgflip.com"))
			break
	if library.has_animated():
		credits.append(tr("Powered by GIPHY"))
	if not credits.is_empty():
		_hint.text += "   ·   " + "   ·   ".join(credits)


func _on_image_updated(id: String) -> void:
	var index: int = library.ids().find(id)
	if index >= 0 and index < _template_list.item_count:
		_template_list.set_item_icon(index, library.texture(id))


func _on_template_selected(index: int) -> void:
	_template_id = library.ids()[index]
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


## Green-phosphor terminal look; built in code so it stays in one place with the colours.
func _build_theme() -> Theme:
	var built := Theme.new()
	built.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = SCREEN_BG.lightened(0.04)
	panel.border_color = PHOSPHOR_DIM
	panel.set_border_width_all(2)
	panel.set_content_margin_all(8)
	var focus := panel.duplicate() as StyleBoxFlat
	focus.border_color = PHOSPHOR
	var button := panel.duplicate() as StyleBoxFlat
	button.bg_color = PHOSPHOR_DIM.darkened(0.3)
	var button_hover := button.duplicate() as StyleBoxFlat
	button_hover.bg_color = PHOSPHOR_DIM
	button_hover.border_color = PHOSPHOR
	var selected := panel.duplicate() as StyleBoxFlat
	selected.bg_color = PHOSPHOR_DIM.darkened(0.2)
	selected.border_color = PHOSPHOR
	for type: String in ["LineEdit", "ItemList"]:
		built.set_stylebox("normal", type, panel)
		built.set_stylebox("focus", type, focus)
		built.set_stylebox("panel", type, panel)
	built.set_stylebox("normal", "Button", button)
	built.set_stylebox("hover", "Button", button_hover)
	built.set_stylebox("pressed", "Button", selected)
	built.set_stylebox("focus", "Button", focus)
	built.set_stylebox("selected", "ItemList", selected)
	built.set_stylebox("selected_focus", "ItemList", selected)
	built.set_stylebox("hovered", "ItemList", button_hover)
	for type: String in ["Label", "LineEdit", "Button", "ItemList"]:
		built.set_color("font_color", type, PHOSPHOR)
	built.set_color("font_placeholder_color", "LineEdit", PHOSPHOR_DIM)
	built.set_color("caret_color", "LineEdit", PHOSPHOR)
	built.set_color("font_hover_color", "Button", Color.WHITE)
	built.set_color("font_selected_color", "ItemList", Color.WHITE)
	built.set_color("font_hovered_color", "ItemList", Color.WHITE)
	built.set_constant("icon_margin", "ItemList", 10)
	built.set_constant("v_separation", "ItemList", 6)
	built.set_font_size("font_size", "ItemList", 14)
	return built
