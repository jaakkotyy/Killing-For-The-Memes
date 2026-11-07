class_name CrtTheme
extends RefCounted
## The green-phosphor terminal look shared by everything shown on a player's CRT (the meme
## editor, guess mode's search terminal). Built in code so the colours live in one place.

const PHOSPHOR: Color = Color(0.45, 1.0, 0.62)
const PHOSPHOR_DIM: Color = Color(0.2, 0.5, 0.3)
const SCREEN_BG: Color = Color(0.02, 0.06, 0.04)
## Warnings and "No" answers: amber, the other colour old terminals had.
const AMBER: Color = Color(1.0, 0.72, 0.3)


static func build() -> Theme:
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
	var disabled := panel.duplicate() as StyleBoxFlat
	disabled.bg_color = SCREEN_BG
	disabled.border_color = PHOSPHOR_DIM.darkened(0.4)
	for type: String in ["LineEdit", "ItemList"]:
		built.set_stylebox("normal", type, panel)
		built.set_stylebox("focus", type, focus)
		built.set_stylebox("panel", type, panel)
	built.set_stylebox("read_only", "LineEdit", disabled)
	built.set_stylebox("normal", "Button", button)
	built.set_stylebox("hover", "Button", button_hover)
	built.set_stylebox("pressed", "Button", selected)
	built.set_stylebox("hover_pressed", "Button", selected)
	built.set_stylebox("focus", "Button", focus)
	built.set_stylebox("disabled", "Button", disabled)
	built.set_stylebox("selected", "ItemList", selected)
	built.set_stylebox("selected_focus", "ItemList", selected)
	built.set_stylebox("hovered", "ItemList", button_hover)
	for type: String in ["Label", "LineEdit", "Button", "ItemList"]:
		built.set_color("font_color", type, PHOSPHOR)
	built.set_color("font_placeholder_color", "LineEdit", PHOSPHOR_DIM)
	built.set_color("font_uneditable_color", "LineEdit", PHOSPHOR_DIM)
	built.set_color("caret_color", "LineEdit", PHOSPHOR)
	built.set_color("font_hover_color", "Button", Color.WHITE)
	built.set_color("font_pressed_color", "Button", Color.WHITE)
	built.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	built.set_color("font_disabled_color", "Button", PHOSPHOR_DIM)
	built.set_color("font_selected_color", "ItemList", Color.WHITE)
	built.set_color("font_hovered_color", "ItemList", Color.WHITE)
	built.set_constant("icon_margin", "ItemList", 10)
	built.set_constant("v_separation", "ItemList", 6)
	built.set_font_size("font_size", "ItemList", 14)
	return built
