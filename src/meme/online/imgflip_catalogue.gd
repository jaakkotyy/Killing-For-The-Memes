class_name ImgflipCatalogue
extends RefCounted
## Meme templates from Imgflip: the popular list from its API
## (https://api.imgflip.com/get_memes, 100 templates), its browsable template pages and its
## search, read into catalogue entries {id, name, url, thumb_url, width, height}.
##
## The id names the image file itself ("imgflip-30b1gx", or "imgflip-1ur9b0-png" for a
## PNG), so any client can draw a template from its id alone, even one a friend found with
## a search a moment ago. URLs are always rebuilt from the id, never taken from data, so a
## host can't make clients download from anywhere but Imgflip's image server.
##
## These images are third-party and copyrighted by their owners. They are fetched at run
## time and never shipped with the game (see CREDITS.md).

const API_URL: String = "https://api.imgflip.com/get_memes"
const SEARCH_URL: String = "https://imgflip.com/memesearch?q=%s"
## Pages of 40 templates, most popular first; page 1 is roughly the API's list.
const TEMPLATES_URL: String = "https://imgflip.com/memetemplates?page=%d"
const ID_PREFIX: String = "imgflip-"
const MAX_ENTRIES: int = 200
const MIN_SIDE: int = 16
const MAX_SIDE: int = 4096
## The image file's name on i.imgflip.com.
const _NAME_PATTERN: String = "^[A-Za-z0-9]{1,16}$"
const _IMAGE_URL: String = "https://i.imgflip.com/%s.%s"
## Imgflip's 150 px thumbnails, always JPG.
const _THUMB_URL: String = "https://i.imgflip.com/4/%s.jpg"
## A template in Imgflip's HTML: its thumbnail's size, alt text and file name.
const _HTML_PATTERN: String = "<img[^>]*?style=\"width:([0-9.]+)px;height:([0-9.]+)px\"[^>]*?alt=\"([^\"]*)\"[^>]*?src=\"//i\\.imgflip\\.com/4/([A-Za-z0-9]{1,16})\\.jpg\""


## The id of the template whose image is i.imgflip.com/<name>.<extension>.
static func id_for(file_name: String, extension: String = "jpg") -> String:
	return ID_PREFIX + file_name + ("-png" if extension.to_lower() == "png" else "")


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
			if not meme is Dictionary:
				continue
			var m: Dictionary = meme
			var url: String = str(m.get("url", ""))
			var found: RegExMatch = RegEx.create_from_string(
				"^https://i\\.imgflip\\.com/([A-Za-z0-9]{1,16})\\.(jpg|png)$").search(url)
			if found == null:
				continue
			raw.append({
				"id": id_for(found.get_string(1), found.get_string(2)),
				"name": m.get("name", ""),
				"width": m.get("width", 0),
				"height": m.get("height", 0),
			})
	return sanitize(raw, limit)


## Parses an Imgflip HTML page that lists templates (search results or a template page).
## The thumbnails are what the page shows, so their size gives the aspect, and the full
## image is assumed to be a JPG (Imgflip's usual format; a PNG one shows as unavailable).
static func parse_html(html: String, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var raw: Array = []
	for found: RegExMatch in RegEx.create_from_string(_HTML_PATTERN).search_all(html):
		var label: String = _unescape(found.get_string(3)).trim_suffix(" Meme Template").trim_suffix(" Template")
		raw.append({
			"id": id_for(found.get_string(4)),
			"name": label,
			# Thumbnails are at most 150 px; keep the ratio at a size sanitize() accepts.
			"width": roundi(found.get_string(1).to_float() * 4.0),
			"height": roundi(found.get_string(2).to_float() * 4.0),
		})
	return sanitize(raw, limit)


static func search_url(query: String) -> String:
	return SEARCH_URL % query.uri_encode()


static func templates_url(page: int) -> String:
	return TEMPLATES_URL % maxi(1, page)


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
		var clean: Dictionary = sanitize_entry(entry)
		if clean.is_empty() or seen.has(clean["id"]):
			continue
		seen[clean["id"]] = true
		result.append(clean)
	return result


static func is_online_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


## The minimal entry for a template id (no name or size), or {} if it isn't a valid one.
## This is how a client draws a template it has never seen in a catalogue.
static func resolve(id: String) -> Dictionary:
	if not is_online_id(id) or not MemeSpec.is_valid_template_id(id):
		return {}
	var rest: String = id.trim_prefix(ID_PREFIX)
	var extension: String = "jpg"
	if rest.ends_with("-png"):
		extension = "png"
		rest = rest.trim_suffix("-png")
	if RegEx.create_from_string(_NAME_PATTERN).search(rest) == null:
		return {}
	return {"id": id, "name": id, "url": _IMAGE_URL % [rest, extension], "thumb_url": _THUMB_URL % rest,
		"width": 0, "height": 0}


## One entry from an untrusted source, or {} if it is not acceptable. Size is required.
static func sanitize_entry(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var e: Dictionary = entry
	var id: Variant = e.get("id")
	if typeof(id) != TYPE_STRING:
		return {}
	var clean: Dictionary = resolve(id)
	if clean.is_empty():
		return {}
	var width: int = _side(e.get("width"))
	var height: int = _side(e.get("height"))
	if width == 0 or height == 0:
		return {}
	var label: String = MemeSpec.sanitize_caption(e.get("name", "")).substr(0, MemeTemplateLibrary.NAME_MAX_LENGTH)
	clean["name"] = label if not label.is_empty() else id
	clean["width"] = width
	clean["height"] = height
	return clean


static func _side(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var side: int = int(value)
	return side if side >= MIN_SIDE and side <= MAX_SIDE else 0


## The few HTML entities Imgflip uses in alt text.
static func _unescape(text: String) -> String:
	return text.replace("&#039;", "'").replace("&quot;", "\"").replace("&lt;", "<").replace("&gt;", ">") \
		.replace("&amp;", "&")
