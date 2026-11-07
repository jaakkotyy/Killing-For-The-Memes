class_name MemeTemplateLibrary
extends RefCounted
## The meme templates players can pick from.
##
## Two kinds:
## - Our originals, from data/meme_templates.json: images in assets/meme_templates/<id>.jpg,
##   rendered from the game's own room by tools/capture_templates.ps1. Always available.
## - Online templates (Imgflip stills, GIPHY GIFs, Reddit memes). The game's catalogue is
##   set with set_online() and comes first in ids(); search results join with add_found().
##   Any valid online id works even if neither listed it: its id names its image
##   (TemplateCatalogue.resolve), so a meme on a template only one player searched for
##   still draws everywhere. Images download in the background (TemplateImageCache);
##   texture() returns null until then and image_updated fires when one arrives (or fails).
##   Animated ones have a still (texture(), for thumbnails) and the whole GIF
##   (animation(), decoded only when a meme on it is shown). The editor's list uses
##   thumbnail(), a small preview where the provider has one.
##
## The server uses accepts() to validate submitted memes; clients use texture() to render them.

## An online template's still, thumbnail or animation finished loading, or failed to.
signal image_updated(id: String)
## The catalogue (ids()) changed.
signal templates_changed

const DEFAULT_PATH: String = "res://data/meme_templates.json"
const IMAGE_DIR: String = "res://assets/meme_templates/"
const NAME_MAX_LENGTH: int = 40
const ORIGINAL_ASPECT: float = 4.0 / 3.0

static var _default: MemeTemplateLibrary

var _original_ids: PackedStringArray = []
var _online_ids: PackedStringArray = []
var _names: Dictionary = {}  # original id -> display name
var _textures: Dictionary = {}  # original id -> Texture2D (loaded lazily)
## Online id -> catalogue entry: the catalogue's, search results and resolved ids.
var _entries: Dictionary = {}
var _ids_by_url: Dictionary = {}  # image URL -> Array of online ids using it
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


## Replaces the online catalogue with [param entries] (already validated catalogue
## entries; pass them through TemplateCatalogue.sanitize() when they come from the
## network). Search results from before are forgotten too.
func set_online(entries: Array[Dictionary]) -> void:
	_online_ids.clear()
	_entries.clear()
	_ids_by_url.clear()
	for entry: Dictionary in entries:
		var id: String = entry["id"]
		if _entries.has(id) or _original_ids.has(id):
			continue
		_online_ids.append(id)
		_remember(entry)
	templates_changed.emit()


## Adds search results (validated entries). Returns their ids, in order. They don't join
## ids(); they are known from now on (names, sizes, thumbnails).
func add_found(entries: Array[Dictionary]) -> PackedStringArray:
	var found: PackedStringArray = []
	for entry: Dictionary in entries:
		var id: String = entry["id"]
		if _original_ids.has(id) or found.has(id):
			continue
		if not _online_ids.has(id):
			_remember(entry)
		found.append(id)
	return found


## The catalogue entries set_online() was given, in order (what the host sends clients).
func online_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in _online_ids:
		entries.append(_entries[id])
	return entries


## The catalogue first (the online templates of this game), then our originals.
func ids() -> PackedStringArray:
	return _online_ids + _original_ids


func original_ids() -> PackedStringArray:
	return _original_ids


func online_ids() -> PackedStringArray:
	return _online_ids


func size() -> int:
	return _online_ids.size() + _original_ids.size()


func is_empty() -> bool:
	return size() == 0


## True for a template of this library: an original or one of the catalogue's.
func has(id: String) -> bool:
	return _online_ids.has(id) or _original_ids.has(id)


## Whether a meme may use [param id]: one of our originals, or any valid online id (the
## image host is fixed by the id, so any of them is safe to draw).
func accepts(id: String) -> bool:
	return _original_ids.has(id) or not TemplateCatalogue.resolve(id).is_empty()


func has_online() -> bool:
	return not _online_ids.is_empty()


## True for a valid online id (catalogue, search result or not).
func is_online(id: String) -> bool:
	return not _entry(id).is_empty()


func is_animated(id: String) -> bool:
	return bool(_entry(id).get("animated", false))


## True when any catalogue template is a GIF (the editor then credits GIPHY).
func has_animated() -> bool:
	for id: String in _online_ids:
		if is_animated(id):
			return true
	return false


func display_name(id: String) -> String:
	if _names.has(id):
		return _names[id]
	return str(_entry(id).get("name", id))


## Width / height of the template image. Online entries without a size (Reddit, or an id
## no list described) use the image once it has loaded, and 4:3 until then.
func aspect(id: String) -> float:
	var entry: Dictionary = _entry(id)
	if entry.is_empty():
		return ORIGINAL_ASPECT
	if int(entry.get("width", 0)) > 0 and int(entry.get("height", 0)) > 0:
		return float(entry["width"]) / float(entry["height"])
	var loaded: Texture2D = texture(id)
	if loaded != null and loaded.get_height() > 0:
		return float(loaded.get_width()) / float(loaded.get_height())
	return ORIGINAL_ASPECT


static func image_path(id: String) -> String:
	return IMAGE_DIR + id + ".jpg"


## The template image, or null if it is unknown, missing, or still downloading.
func texture(id: String) -> Texture2D:
	var entry: Dictionary = _entry(id)
	if not entry.is_empty():
		_connect_cache()
		return TemplateImageCache.get_instance().get_texture(_still_url(entry))
	if not _original_ids.has(id):
		return null
	if not _textures.has(id):
		var path: String = image_path(id)
		_textures[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[id]


## A small picture for lists: the provider's thumbnail when it has one (much less to
## download than the full image), else the still.
func thumbnail(id: String) -> Texture2D:
	var entry: Dictionary = _entry(id)
	var thumb: String = str(entry.get("thumb_url", ""))
	if thumb.is_empty() or TemplateImageCache.get_instance().has_failed(thumb):
		return texture(id)
	_connect_cache()
	return TemplateImageCache.get_instance().get_texture(thumb)


## The decoded GIF of an animated template, or null while it loads (or for stills).
func animation(id: String) -> AnimatedTemplate:
	if not is_animated(id):
		return null
	_connect_cache()
	return TemplateImageCache.get_instance().get_animation(_entry(id)["url"])


## True when an online template's still could not be loaded.
func image_failed(id: String) -> bool:
	var entry: Dictionary = _entry(id)
	return not entry.is_empty() and TemplateImageCache.get_instance().has_failed(_still_url(entry))


## The entry for an online id: from the catalogue or a search, else built from the id.
func _entry(id: String) -> Dictionary:
	if _entries.has(id):
		return _entries[id]
	var resolved: Dictionary = TemplateCatalogue.resolve(id)
	if not resolved.is_empty():
		_remember(resolved)
	return resolved


func _remember(entry: Dictionary) -> void:
	var id: String = entry["id"]
	_entries[id] = entry
	for key: String in ["url", "still_url", "thumb_url"]:
		var url: String = str(entry.get(key, ""))
		if url.is_empty():
			continue
		if not _ids_by_url.has(url):
			_ids_by_url[url] = []
		if not (_ids_by_url[url] as Array).has(id):
			(_ids_by_url[url] as Array).append(id)


static func _still_url(entry: Dictionary) -> String:
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
	for id: String in _ids_by_url.get(url, []):
		image_updated.emit(id)
