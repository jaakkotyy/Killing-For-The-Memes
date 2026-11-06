class_name MemeTemplateLibrary
extends RefCounted
## The meme templates players can pick from, loaded from data/meme_templates.json.
##
## Every template is an original image in assets/meme_templates/<id>.jpg (rendered from the
## game's own room by tools/capture_templates.ps1). The server uses ids() to validate
## submitted memes; clients use texture() to render them.

const DEFAULT_PATH: String = "res://data/meme_templates.json"
const IMAGE_DIR: String = "res://assets/meme_templates/"
const NAME_MAX_LENGTH: int = 40

static var _default: MemeTemplateLibrary

var _ids: PackedStringArray = []
var _names: Dictionary = {}  # id -> display name
var _textures: Dictionary = {}  # id -> Texture2D (loaded lazily)


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
		if typeof(id) != TYPE_STRING or not MemeSpec.is_valid_template_id(id) or library._ids.has(id):
			continue
		library._ids.append(id)
		var label: String = str(display).strip_edges().substr(0, NAME_MAX_LENGTH)
		library._names[id] = label if not label.is_empty() else id
	return library


func ids() -> PackedStringArray:
	return _ids


func size() -> int:
	return _ids.size()


func is_empty() -> bool:
	return _ids.is_empty()


func has(id: String) -> bool:
	return _ids.has(id)


func display_name(id: String) -> String:
	return _names.get(id, id)


static func image_path(id: String) -> String:
	return IMAGE_DIR + id + ".jpg"


## The template image, or null if it is unknown or its image is missing.
func texture(id: String) -> Texture2D:
	if not has(id):
		return null
	if not _textures.has(id):
		var path: String = image_path(id)
		_textures[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[id]
