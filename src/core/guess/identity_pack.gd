class_name IdentityPack
extends RefCounted
## A pack of identities for guess mode: the database a player searches on their terminal
## and the server deals from. Packs are JSON files in data/identities/:
##
##   {"id": "musicians", "name": "Musicians", "version": 1, "source": "Wikidata (CC0)",
##    "fields": [{"id": "born", "name": "Born", "type": "year"}, ...],
##    "questions": [{"text": "Was I born before 1980?",
##                   "filter": {"field": "born", "op": "before", "value": 1980}}, ...],
##    "entries": [{"id": "Q1299", "name": "The Beatles", "fame": 210,
##                 "fields": {"born": 1960, "genres": ["rock"]}, "image": "Beatles.jpg"}, ...]}
##
## Field types: "enum" (one string), "year" (an int), "bool", "tags" (strings). An entry
## may leave a field out: unknown. Everything is validated on load and bad parts are
## dropped, so a hand-written pack with a typo still loads what it can.

const TYPES: PackedStringArray = ["enum", "year", "bool", "tags"]
const NAME_MAX_LENGTH: int = 80
const VALUE_MAX_LENGTH: int = 48
const QUESTION_MAX_LENGTH: int = 120
const MAX_FIELDS: int = 16
const MAX_TAGS: int = 12
const MAX_QUESTIONS: int = 60
const MAX_ENTRIES: int = 20000
const MIN_YEAR: int = -5000
const MAX_YEAR: int = 3000
const _ID_PATTERN: String = "^[A-Za-z0-9_-]{1,32}$"

static var _id_regex: RegEx = RegEx.create_from_string(_ID_PATTERN)
static var _space_regex: RegEx = RegEx.create_from_string("\\s+")


## One searchable property of the entries.
class Field:
	extends RefCounted
	var id: String
	var name: String
	var type: String

	func _init(p_id: String, p_name: String, p_type: String) -> void:
		id = p_id
		name = p_name
		type = p_type


## One identity.
class Entry:
	extends RefCounted
	var id: String
	var name: String
	## How well known (Wikidata sitelinks); the deck deals the best known ones.
	var fame: int
	## Field id -> value (String, int, bool or PackedStringArray). Missing = unknown.
	var values: Dictionary
	## Wikimedia Commons file name, or "".
	var image: String

	func _init(p_id: String, p_name: String, p_fame: int, p_values: Dictionary, p_image: String) -> void:
		id = p_id
		name = p_name
		fame = p_fame
		values = p_values
		image = p_image

	func has_value(field_id: String) -> bool:
		return values.has(field_id)

	func value(field_id: String) -> Variant:
		return values.get(field_id)


## A ready-made question; [member filter] is what a "Yes" means.
class StockQuestion:
	extends RefCounted
	var text: String
	var filter: IdentityFilter

	func _init(p_text: String, p_filter: IdentityFilter) -> void:
		text = p_text
		filter = p_filter


var id: String = ""
var name: String = ""
var source: String = ""

var _fields: Array[Field] = []
var _fields_by_id: Dictionary = {}  # field id -> Field
var _entries: Array[Entry] = []
var _entries_by_id: Dictionary = {}  # entry id -> Entry
var _questions: Array[StockQuestion] = []


## Loads a pack file. Returns null when it is missing or not a valid pack.
static func load_file(path: String) -> IdentityPack:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


## Parses a pack. Returns null unless it has at least one valid entry.
static func from_json(json_text: String) -> IdentityPack:
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return null
	return from_dict(json.data)


static func from_dict(data: Dictionary) -> IdentityPack:
	var pack := IdentityPack.new()
	pack.id = _clean_text(data.get("id", ""), NAME_MAX_LENGTH)
	pack.name = _clean_text(data.get("name", ""), NAME_MAX_LENGTH)
	pack.source = _clean_text(data.get("source", ""), NAME_MAX_LENGTH)
	var fields: Variant = data.get("fields")
	if fields is Array:
		for raw: Variant in fields:
			pack._add_field(raw)
	var entries: Variant = data.get("entries")
	if entries is Array:
		for raw: Variant in entries:
			if pack._entries.size() >= MAX_ENTRIES:
				break
			pack._add_entry(raw)
	var questions: Variant = data.get("questions")
	if questions is Array:
		for raw: Variant in questions:
			if pack._questions.size() >= MAX_QUESTIONS:
				break
			pack._add_question(raw)
	if pack._entries.is_empty():
		return null
	if pack.name.is_empty():
		pack.name = pack.id
	return pack


## Where the shipped packs live: <PACK_DIR><id>.json.
const PACK_DIR: String = "res://data/identities/"


## The shipped pack ids, sorted.
static func available_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for file: String in DirAccess.get_files_at(PACK_DIR):
		if file.get_extension() == "json" and is_valid_id(file.get_basename()):
			ids.append(file.get_basename())
	ids.sort()
	return ids


## Whether [param pack_id] (untrusted) names a shipped pack.
static func exists(pack_id: Variant) -> bool:
	return typeof(pack_id) == TYPE_STRING and is_valid_id(pack_id) and available_ids().has(pack_id)


static var _loaded: Dictionary = {}  # pack id -> IdentityPack


## A shipped pack by id, loaded once per run (they are big). Null if there is none.
static func load_pack(pack_id: String) -> IdentityPack:
	if not exists(pack_id):
		return null
	if not _loaded.has(pack_id):
		_loaded[pack_id] = load_file(PACK_DIR + pack_id + ".json")
	return _loaded[pack_id]


## A pack's display name without loading it all ("Musicians").
static func display_name(pack_id: String) -> String:
	var pack: IdentityPack = load_pack(pack_id)
	return pack.name if pack != null else pack_id.capitalize()


static func is_valid_id(value: String) -> bool:
	return _id_regex.search(value) != null


func fields() -> Array[Field]:
	return _fields


func get_field(field_id: String) -> Field:
	return _fields_by_id.get(field_id)


func entries() -> Array[Entry]:
	return _entries


func get_entry(entry_id: String) -> Entry:
	return _entries_by_id.get(entry_id)


func has_entry(entry_id: String) -> bool:
	return _entries_by_id.has(entry_id)


func size() -> int:
	return _entries.size()


func stock_questions() -> Array[StockQuestion]:
	return _questions


## The stock question at [param index], or null (for indices from the network).
func stock_question(index: Variant) -> StockQuestion:
	if typeof(index) != TYPE_INT or int(index) < 0 or int(index) >= _questions.size():
		return null
	return _questions[int(index)]


## Every value an enum or tags field takes, sorted, for the terminal's pickers.
func values_of(field_id: String) -> PackedStringArray:
	var field: Field = get_field(field_id)
	var seen: Dictionary = {}
	if field == null or not field.type in ["enum", "tags"]:
		return PackedStringArray()
	for entry: Entry in _entries:
		if not entry.has_value(field_id):
			continue
		if field.type == "enum":
			seen[entry.value(field_id)] = true
		else:
			for tag: String in entry.value(field_id):
				seen[tag] = true
	var result: PackedStringArray = PackedStringArray(seen.keys())
	result.sort()
	return result


## The lowest and highest year of a year field (Vector2i.ZERO when it has none).
func year_range(field_id: String) -> Vector2i:
	var low: int = MAX_YEAR
	var high: int = MIN_YEAR
	for entry: Entry in _entries:
		if entry.has_value(field_id):
			low = mini(low, int(entry.value(field_id)))
			high = maxi(high, int(entry.value(field_id)))
	return Vector2i(low, high) if low <= high else Vector2i.ZERO


func _add_field(raw: Variant) -> void:
	if not raw is Dictionary or _fields.size() >= MAX_FIELDS:
		return
	var d: Dictionary = raw
	var field_id: String = str(d.get("id", "")) if typeof(d.get("id")) == TYPE_STRING else ""
	var type: String = str(d.get("type", "")) if typeof(d.get("type")) == TYPE_STRING else ""
	if not is_valid_id(field_id) or _fields_by_id.has(field_id) or not TYPES.has(type):
		return
	var label: String = _clean_text(d.get("name", ""), NAME_MAX_LENGTH)
	var field := Field.new(field_id, label if not label.is_empty() else field_id, type)
	_fields.append(field)
	_fields_by_id[field_id] = field


func _add_entry(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var d: Dictionary = raw
	var entry_id: String = str(d.get("id", "")) if typeof(d.get("id")) == TYPE_STRING else ""
	var label: String = _clean_text(d.get("name", ""), NAME_MAX_LENGTH)
	if not is_valid_id(entry_id) or _entries_by_id.has(entry_id) or label.is_empty():
		return
	var values: Dictionary = {}
	var raw_values: Variant = d.get("fields")
	if raw_values is Dictionary:
		for field: Field in _fields:
			var clean: Variant = clean_value(field.type, (raw_values as Dictionary).get(field.id))
			if clean != null:
				values[field.id] = clean
	var fame_value: Variant = d.get("fame", 0)
	var fame: int = maxi(0, int(fame_value)) if typeof(fame_value) in [TYPE_INT, TYPE_FLOAT] else 0
	var image: String = _clean_text(d.get("image", ""), 200)
	var entry := Entry.new(entry_id, label, fame, values, image)
	_entries.append(entry)
	_entries_by_id[entry_id] = entry


func _add_question(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var d: Dictionary = raw
	var text: String = _clean_text(d.get("text", ""), QUESTION_MAX_LENGTH)
	var filter: IdentityFilter = IdentityFilter.from_untrusted(d.get("filter"), self)
	if text.is_empty() or filter == null:
		return
	_questions.append(StockQuestion.new(text, filter))


## A value of [param type] from untrusted data, or null if it doesn't fit.
static func clean_value(type: String, value: Variant) -> Variant:
	match type:
		"enum":
			var text: String = _clean_text(value, VALUE_MAX_LENGTH)
			return text if not text.is_empty() else null
		"year":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			var year: int = int(value)
			return year if year >= MIN_YEAR and year <= MAX_YEAR else null
		"bool":
			return value if typeof(value) == TYPE_BOOL else null
		"tags":
			if not value is Array:
				return null
			var tags: PackedStringArray = []
			for tag: Variant in value:
				var text: String = _clean_text(tag, VALUE_MAX_LENGTH)
				if not text.is_empty() and not tags.has(text) and tags.size() < MAX_TAGS:
					tags.append(text)
			return tags if not tags.is_empty() else null
	return null


## One line of plain text: non-strings become "", whitespace runs become one space.
static func _clean_text(value: Variant, max_length: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text: String = _space_regex.sub(value as String, " ", true)
	return text.strip_edges().substr(0, max_length)
