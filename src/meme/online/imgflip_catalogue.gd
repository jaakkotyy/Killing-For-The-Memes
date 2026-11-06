class_name ImgflipCatalogue
extends RefCounted
## Reads Imgflip's list of popular meme templates (https://api.imgflip.com/get_memes) and
## turns it into catalogue entries: {id, name, url, width, height}.
##
## The same validation runs on the host (parsing Imgflip's answer) and on every client
## (checking the catalogue the host sends), so a modified host can't make clients download
## from anywhere but Imgflip's image server.
##
## These images are third-party and copyrighted by their owners. They are fetched at run
## time and never shipped with the game (see CREDITS.md).

const API_URL: String = "https://api.imgflip.com/get_memes"
## Prefix that keeps Imgflip ids apart from our own template ids.
const ID_PREFIX: String = "imgflip-"
## Imgflip returns 100; more than this from a host is refused.
const MAX_ENTRIES: int = 100
const MIN_SIDE: int = 16
const MAX_SIDE: int = 4096
## Still images only for now; GIF templates come later.
const _URL_PATTERN: String = "^https://i\\.imgflip\\.com/[A-Za-z0-9]{1,16}\\.(jpg|png)$"
const _IMGFLIP_ID_PATTERN: String = "^[0-9]{1,12}$"


## Parses the body of an API answer. Returns at most [param limit] entries, most popular
## first; an empty array if the answer is malformed or unsuccessful.
static func parse_response(json_text: String, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return []
	var body: Dictionary = json.data
	if body.get("success") != true or typeof(body.get("data")) != TYPE_DICTIONARY:
		return []
	var memes: Variant = (body["data"] as Dictionary).get("memes")
	var raw: Array = []
	if memes is Array:
		for meme: Variant in memes:
			if meme is Dictionary:
				var m: Dictionary = meme
				raw.append({
					"id": ID_PREFIX + str(m.get("id", "")),
					"name": m.get("name", ""),
					"url": m.get("url", ""),
					"width": m.get("width", 0),
					"height": m.get("height", 0),
				})
	return sanitize(raw, limit)


## Validates catalogue entries from an untrusted source (the API, or the host over the
## network). Bad entries and duplicate ids are dropped, never fatal.
static func sanitize(entries: Variant, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not entries is Array:
		return result
	var seen: Dictionary = {}
	for entry: Variant in entries:
		if result.size() >= mini(limit, MAX_ENTRIES):
			break
		var clean: Dictionary = _sanitize_entry(entry)
		if clean.is_empty() or seen.has(clean["id"]):
			continue
		seen[clean["id"]] = true
		result.append(clean)
	return result


static func is_valid_url(url: String) -> bool:
	return RegEx.create_from_string(_URL_PATTERN).search(url) != null


static func is_online_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


static func _sanitize_entry(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var e: Dictionary = entry
	var id: Variant = e.get("id")
	var url: Variant = e.get("url")
	if typeof(id) != TYPE_STRING or typeof(url) != TYPE_STRING:
		return {}
	var id_text: String = id
	if not is_online_id(id_text) or not MemeSpec.is_valid_template_id(id_text):
		return {}
	if RegEx.create_from_string(_IMGFLIP_ID_PATTERN).search(id_text.trim_prefix(ID_PREFIX)) == null:
		return {}
	if not is_valid_url(url):
		return {}
	var width: int = _side(e.get("width"))
	var height: int = _side(e.get("height"))
	if width == 0 or height == 0:
		return {}
	var label: String = MemeSpec.sanitize_caption(e.get("name", "")).substr(0, MemeTemplateLibrary.NAME_MAX_LENGTH)
	return {"id": id_text, "name": label if not label.is_empty() else id_text, "url": url, "width": width, "height": height}


static func _side(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var side: int = int(value)
	return side if side >= MIN_SIDE and side <= MAX_SIDE else 0
