class_name GiphyCatalogue
extends RefCounted
## Reads GIPHY search results into animated catalogue entries:
## {id, name, url, still_url, width, height, animated: true}.
##
## GIPHY needs an API key (the host's own, see App) and its terms require a visible
## "Powered by GIPHY" where it is used: the meme editor shows it. Like ImgflipCatalogue,
## the same validation runs on the host and on every client. Image URLs are never taken
## from the data: they are rebuilt from the GIF id, so they can only point at GIPHY.

const SEARCH_URL: String = "https://api.giphy.com/v1/gifs/search"
const ID_PREFIX: String = "giphy-"
## What to search for: reaction GIFs make the best templates.
const DEFAULT_QUERY: String = "reaction"
const RATING: String = "pg-13"
const MAX_ENTRIES: int = 50
## "fixed_height": 200 px tall, small enough to decode quickly.
const _MEDIA_URL: String = "https://media.giphy.com/media/%s/200.gif"
const _STILL_URL: String = "https://media.giphy.com/media/%s/200_s.gif"
const _GIF_ID_PATTERN: String = "^[A-Za-z0-9]{1,34}$"


## The search request. The key is the caller's; never log this URL.
static func search_url(api_key: String, query: String = DEFAULT_QUERY, limit: int = 25) -> String:
	return "%s?api_key=%s&q=%s&limit=%d&rating=%s&lang=en" % [
		SEARCH_URL, api_key.uri_encode(), query.uri_encode(), clampi(limit, 1, MAX_ENTRIES), RATING]


## Parses a search answer, in GIPHY's order. Empty if it is malformed.
static func parse_response(json_text: String, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return []
	var data: Variant = (json.data as Dictionary).get("data")
	var raw: Array = []
	if data is Array:
		for gif: Variant in data:
			if not gif is Dictionary:
				continue
			var g: Dictionary = gif
			var images: Variant = g.get("images", {})
			var fixed: Variant = (images as Dictionary).get("fixed_height", {}) if images is Dictionary else {}
			if not fixed is Dictionary:
				continue
			raw.append({
				"id": ID_PREFIX + str(g.get("id", "")),
				"name": _short_title(str(g.get("title", ""))),
				"width": _number((fixed as Dictionary).get("width")),
				"height": _number((fixed as Dictionary).get("height")),
			})
	var result: Array[Dictionary] = []
	for entry: Variant in raw:
		if result.size() >= mini(limit, MAX_ENTRIES):
			break
		var clean: Dictionary = sanitize_entry(entry)
		if not clean.is_empty():
			result.append(clean)
	return result


static func is_online_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


## One entry from an untrusted source, or {} if it is not acceptable.
static func sanitize_entry(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var e: Dictionary = entry
	var id: Variant = e.get("id")
	if typeof(id) != TYPE_STRING or not is_online_id(id) or not MemeSpec.is_valid_template_id(id):
		return {}
	var gif_id: String = (id as String).trim_prefix(ID_PREFIX)
	if RegEx.create_from_string(_GIF_ID_PATTERN).search(gif_id) == null:
		return {}
	var width: int = _side(e.get("width"))
	var height: int = _side(e.get("height"))
	if width == 0 or height == 0:
		return {}
	var label: String = MemeSpec.sanitize_caption(e.get("name", "")).substr(0, MemeTemplateLibrary.NAME_MAX_LENGTH)
	return {
		"id": id,
		"name": label if not label.is_empty() else "GIF",
		"url": _MEDIA_URL % gif_id,
		"still_url": _STILL_URL % gif_id,
		"width": width,
		"height": height,
		"animated": true,
	}


## "Happy Dance GIF by Some Studio" -> "Happy Dance".
static func _short_title(title: String) -> String:
	var short: String = title
	var cut: int = short.find(" GIF")
	if cut >= 0:
		short = short.substr(0, cut)
	return short.strip_edges()


## GIPHY sends sizes as strings ("200").
static func _number(value: Variant) -> int:
	if typeof(value) == TYPE_STRING and (value as String).is_valid_int():
		return (value as String).to_int()
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0


static func _side(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var side: int = int(value)
	return side if side >= ImgflipCatalogue.MIN_SIDE and side <= GifDecoder.MAX_SIDE else 0
