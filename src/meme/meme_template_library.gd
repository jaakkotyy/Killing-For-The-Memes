class_name MemeTemplateLibrary
extends RefCounted
## The meme templates players can pick from.
##
## Two kinds:
## - Our originals, from data/meme_templates.json: images in assets/meme_templates/<id>.jpg,
##   rendered from the game's own room by tools/capture_templates.ps1. Always available.
## - Online templates (popular stills from Imgflip, GIFs from GIPHY), added at run time with
##   set_online(). Their images download in the background (TemplateImageCache); texture()
##   returns null until then and image_updated fires when one arrives (or fails). They come
##   first in ids(). Animated ones have a still (texture(), for thumbnails) and the whole
##   GIF (animation(), decoded only when a meme on it is shown).
##
## The server uses ids() to validate submitted memes; clients use texture() to render them.

## An online template's still or animation finished loading, or failed to.
signal image_updated(id: String)

const DEFAULT_PATH: String = "res://data/meme_templates.json"
const IMAGE_DIR: String = "res://assets/meme_templates/"
const NAME_MAX_LENGTH: int = 40
const ORIGINAL_ASPECT: float = 4.0 / 3.0

static var _default: MemeTemplateLibrary

var _original_ids: PackedStringArray = []
var _online_ids: PackedStringArray = []
var _names: Dictionary = {}  # id -> display name
var _textures: Dictionary = {}  # original id -> Texture2D (loaded lazily)
var _online: Dictionary = {}  # online id -> catalogue entry (see TemplateCatalogue)
var _cache_connected: bool = false


## The shared library from data/meme_templates.json.
static func get_default() -> MemeTemplateLibrary:
	if _default == null:
		var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
		_default = from_json(file.get_as_text() if file != null else "")
		if _default.is_empty():
			push_error("No meme templates found in %s" % DEFAULT_PATH)
	return _default


## Parses a template list. Malformed entries and duplicate ids are skipped, never fatal.
static func from_json(json_text: String) -> MemeTemplateLibrary:
	var library := MemeTemplateLibrary.new()
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return library
	var entries: Variant = (json.data as Dictionary).get("templates")
	if typeof(entries) != TYPE_ARRAY:
		return library
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id: Variant = (entry as Dictionary).get("id")
		var display: Variant = (entry as Dictionary).get("name", "")
		if typeof(id) != TYPE_STRING or not MemeSpec.is_valid_template_id(id) or library._original_ids.has(id) \
				or TemplateCatalogue.is_online_id(id):
			continue
		library._original_ids.append(id)
		var label: String = str(display).strip_edges().substr(0, NAME_MAX_LENGTH)
		library._names[id] = label if not label.is_empty() else id
	return library


## Replaces the online templates with [param entries] (already validated catalogue
## entries; pass them through TemplateCatalogue.sanitize() when they come from the network).
func set_online(entries: Array[Dictionary]) -> void:
	for id: String in _online_ids:
		_names.erase(id)
	_online_ids.clear()
	_online.clear()
	for entry: Dictionary in entries:
		var id: String = entry["id"]
		if _online.has(id) or _original_ids.has(id):
			continue
		_online_ids.append(id)
		_online[id] = entry
		_names[id] = entry["name"]


## The catalogue entries set_online() was given, in order (what the host sends clients).
func online_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in _online_ids:
		entries.append(_online[id])
	return entries


## Online templates first (the popular ones players look for), then our originals.
func ids() -> PackedStringArray:
	return _online_ids + _original_ids


func original_ids() -> PackedStringArray:
	return _original_ids


func size() -> int:
	return _online_ids.size() + _original_ids.size()


func is_empty() -> bool:
	return size() == 0


func has(id: String) -> bool:
	return _online.has(id) or _original_ids.has(id)


func has_online() -> bool:
	return not _online_ids.is_empty()


func is_online(id: String) -> bool:
	return _online.has(id)


func is_animated(id: String) -> bool:
	return _online.has(id) and bool((_online[id] as Dictionary).get("animated", false))


## True when any online template is a GIF (the editor then credits GIPHY).
func has_animated() -> bool:
	for id: String in _online_ids:
		if is_animated(id):
			return true
	return false


func display_name(id: String) -> String:
	return _names.get(id, id)


## Width / height of the template image (known before an online image has downloaded).
func aspect(id: String) -> float:
	if _online.has(id):
		var entry: Dictionary = _online[id]
		return float(entry["width"]) / float(entry["height"])
	return ORIGINAL_ASPECT


static func image_path(id: String) -> String:
	return IMAGE_DIR + id + ".jpg"


## The template image, or null if it is unknown, missing, or still downloading.
func texture(id: String) -> Texture2D:
	if _online.has(id):
		_connect_cache()
		return TemplateImageCache.get_instance().get_texture(_still_url(id))
	if not _original_ids.has(id):
		return null
	if not _textures.has(id):
		var path: String = image_path(id)
		_textures[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[id]


## The decoded GIF of an animated template, or null while it loads (or for stills).
func animation(id: String) -> AnimatedTemplate:
	if not is_animated(id):
		return null
	_connect_cache()
	return TemplateImageCache.get_instance().get_animation(_online[id]["url"])


## True when an online template's still could not be loaded.
func image_failed(id: String) -> bool:
	return _online.has(id) and TemplateImageCache.get_instance().has_failed(_still_url(id))


func _still_url(id: String) -> String:
	var entry: Dictionary = _online[id]
	return entry.get("still_url", entry["url"])


func _connect_cache() -> void:
	if _cache_connected:
		return
	_cache_connected = true
	var cache: TemplateImageCache = TemplateImageCache.get_instance()
	# Named methods, not lambdas: Godot drops these connections when the library is freed.
	cache.loaded.connect(_on_image_loaded)
	cache.failed.connect(_on_image_updated)
	cache.animation_loaded.connect(_on_animation_loaded)
	cache.animation_failed.connect(_on_image_updated)


func _on_image_loaded(url: String, _texture: Texture2D) -> void:
	_on_image_updated(url)


func _on_animation_loaded(url: String, _animation: AnimatedTemplate) -> void:
	_on_image_updated(url)


func _on_image_updated(url: String) -> void:
	for id: String in _online_ids:
		var entry: Dictionary = _online[id]
		if entry["url"] == url or entry.get("still_url", "") == url:
			image_updated.emit(id)
