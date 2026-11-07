class_name MemeRenderer
extends Control
## Draws a MemeSpec: the template image with classic top/bottom captions (white, uppercase,
## thick black outline), shrinking the text until it fits. Every client renders memes from
## the spec locally; the editor preview and the wall TV both use this control.
##
## The meme is always a 4:3 frame. Templates of other shapes (most online ones) are
## letterboxed inside it on black, and the captions sit on the image itself. GIF templates
## play (looping) once their animation has loaded, showing their still until then.

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
var _watched: MemeTemplateLibrary
## When the current template started playing (Time.get_ticks_msec()).
var _started_msec: int = 0
var _animation: AnimatedTemplate
var _shown_frame: int = -1


## The caption font: the real Impact, from the player's own system (every Windows has
## it; nothing is shipped), then look-alikes. Without any of them, an emboldened default.
static func meme_font() -> Font:
	if _meme_font == null:
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 1.1
		bold.spacing_glyph = 1
		_meme_font = bold
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Anton", "Arial Black"])
		system.font_weight = 700
		# SystemFont falls back to some default font when none of the names exist; only use
		# it when one of them really is installed.
		var installed: PackedStringArray = OS.get_system_fonts()
		for wanted: String in system.font_names:
			if installed.has(wanted):
				system.fallbacks = [bold]
				_meme_font = system
				break
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
	var next: MemeSpec = spec if spec != null else MemeSpec.new()
	if next.template_id != _spec.template_id:
		_started_msec = Time.get_ticks_msec()
	_spec = next
	queue_redraw()


func _process(_delta: float) -> void:
	# Redraw only when the GIF moves on to another frame.
	if _animation != null and _animation.frame_index_at(_elapsed()) != _shown_frame:
		queue_redraw()


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _started_msec) / 1000.0


func get_meme() -> MemeSpec:
	return _spec


## The 4:3 area the meme is drawn in, centred in this control.
func meme_rect() -> Rect2:
	return fit_rect(Rect2(Vector2.ZERO, size), ASPECT)


## The largest rect of [param aspect] (width / height) centred in [param bounds].
static func fit_rect(bounds: Rect2, aspect: float) -> Rect2:
	var width: float = minf(bounds.size.x, bounds.size.y * aspect)
	var height: float = width / aspect
	return Rect2(bounds.position + (bounds.size - Vector2(width, height)) / 2.0, Vector2(width, height))


## Where the template image (and so the captions) go inside the meme frame.
func image_rect() -> Rect2:
	var frame: Rect2 = meme_rect()
	if library == null or _spec.is_blank():
		return frame
	return fit_rect(frame, library.aspect(_spec.template_id))


func _draw() -> void:
	var rect: Rect2 = meme_rect()
	draw_rect(rect, Color.BLACK)
	if _spec.is_blank():
		_animation = null
		set_process(false)
		_draw_caption(tr("NO MEME SUBMITTED"), rect, Rect2(0.1, 0.4, 0.8, 0.2), false, Color(0.55, 0.55, 0.55))
		return
	_watch(library)
	var image: Rect2 = image_rect()
	var texture: Texture2D = library.texture(_spec.template_id) if library != null else null
	_animation = library.animation(_spec.template_id) if library != null else null
	if _animation != null and _animation.frame_count() > 0:
		_shown_frame = _animation.frame_index_at(_elapsed())
		texture = _animation.textures[_shown_frame]
	set_process(_animation != null and _animation.frame_count() > 1)
	if texture != null:
		draw_texture_rect(texture, image, false)
	elif library != null and library.is_online(_spec.template_id):
		var waiting: String = tr("IMAGE UNAVAILABLE") if library.image_failed(_spec.template_id) else tr("LOADING...")
		draw_rect(image, Color(0.08, 0.08, 0.08))
		_draw_caption(waiting, image, Rect2(0.1, 0.42, 0.8, 0.16), false, Color(0.5, 0.5, 0.5))
	_draw_caption(_spec.top_text.to_upper(), image, TOP_BOX, true, Color.WHITE)
	_draw_caption(_spec.bottom_text.to_upper(), image, BOTTOM_BOX, false, Color.WHITE)


## Redraw when the image we are waiting for arrives.
func _watch(target: MemeTemplateLibrary) -> void:
	if target == _watched:
		return
	if _watched != null and _watched.image_updated.is_connected(_on_image_updated):
		_watched.image_updated.disconnect(_on_image_updated)
	_watched = target
	if _watched != null:
		_watched.image_updated.connect(_on_image_updated)


func _on_image_updated(id: String) -> void:
	if id == _spec.template_id:
		queue_redraw()


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
