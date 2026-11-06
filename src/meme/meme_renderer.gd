class_name MemeRenderer
extends Control
## Draws a MemeSpec: the template image with classic top/bottom captions (white, uppercase,
## thick black outline), shrinking the text until it fits. Every client renders memes from
## the spec locally; the editor preview and the wall TV both use this control.

## Caption boxes as fractions of the meme's rect.
const TOP_BOX: Rect2 = Rect2(0.04, 0.025, 0.92, 0.25)
const BOTTOM_BOX: Rect2 = Rect2(0.04, 0.725, 0.92, 0.25)
const MAX_FONT_FRACTION: float = 0.12  # of the meme height
const MIN_FONT_FRACTION: float = 0.04
const OUTLINE_FRACTION: float = 0.14  # of the font size
const ASPECT: float = 4.0 / 3.0

static var _meme_font: Font

var library: MemeTemplateLibrary
var _spec: MemeSpec = MemeSpec.new()


## The bold caption font. A placeholder until the OFL meme font is added (see CREDITS.md).
static func meme_font() -> Font:
	if _meme_font == null:
		var variation := FontVariation.new()
		variation.base_font = ThemeDB.fallback_font
		variation.variation_embolden = 1.1
		variation.spacing_glyph = 1
		_meme_font = variation
	return _meme_font


## Largest font size (between min and max) at which `text` wraps into `box_size`.
static func fit_font_size(font: Font, text: String, box_size: Vector2, max_size: int, min_size: int) -> int:
	if text.is_empty():
		return max_size
	var size: int = max_size
	while size > min_size:
		var needed: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box_size.x, size)
		if needed.y <= box_size.y and needed.x <= box_size.x + 0.5:
			return size
		size -= maxi(1, size / 16)
	return min_size


func _ready() -> void:
	if library == null:
		library = MemeTemplateLibrary.get_default()
	resized.connect(queue_redraw)


func set_meme(spec: MemeSpec) -> void:
	_spec = spec if spec != null else MemeSpec.new()
	queue_redraw()


func get_meme() -> MemeSpec:
	return _spec


## The 4:3 area the meme is drawn in, centred in this control.
func meme_rect() -> Rect2:
	var width: float = minf(size.x, size.y * ASPECT)
	var height: float = width / ASPECT
	return Rect2((size - Vector2(width, height)) / 2.0, Vector2(width, height))


func _draw() -> void:
	var rect: Rect2 = meme_rect()
	draw_rect(rect, Color.BLACK)
	if _spec.is_blank():
		_draw_caption(tr("NO MEME SUBMITTED"), rect, Rect2(0.1, 0.4, 0.8, 0.2), false, Color(0.55, 0.55, 0.55))
		return
	var texture: Texture2D = library.texture(_spec.template_id) if library != null else null
	if texture != null:
		draw_texture_rect(texture, rect, false)
	_draw_caption(_spec.top_text.to_upper(), rect, TOP_BOX, true, Color.WHITE)
	_draw_caption(_spec.bottom_text.to_upper(), rect, BOTTOM_BOX, false, Color.WHITE)


func _draw_caption(text: String, rect: Rect2, box_fraction: Rect2, align_top: bool, color: Color) -> void:
	if text.is_empty():
		return
	var font: Font = meme_font()
	var box := Rect2(rect.position + box_fraction.position * rect.size, box_fraction.size * rect.size)
	var font_size: int = fit_font_size(font, text, box.size,
		maxi(8, roundi(rect.size.y * MAX_FONT_FRACTION)), maxi(6, roundi(rect.size.y * MIN_FONT_FRACTION)))
	var text_size: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size)
	var top: float = box.position.y if align_top else box.end.y - text_size.y
	var baseline := Vector2(box.position.x, top + font.get_ascent(font_size))
	var outline: int = maxi(2, roundi(font_size * OUTLINE_FRACTION))
	draw_multiline_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, -1, outline, Color.BLACK)
	draw_multiline_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, -1, color)
