class_name RedditCatalogue
extends RefCounted
## Fresh memes from Reddit as templates: whatever is on a subreddit right now, read through
## meme-api.com (a public service that relays Reddit's hot posts as JSON; Reddit itself
## refuses requests from apps without an OAuth login). Entries: {id, name, url, thumb_url?}.
##
## The id names the image on i.redd.it ("reddit-i1nvdxztc10i1-png"), so any client can
## draw it from the id alone, and the URL is always rebuilt from the id. Only stills (JPG,
## PNG): Reddit GIFs are often huge. NSFW and spoiler posts are skipped. Reddit doesn't
## say how big an image is, so these entries have no size until the image has loaded.

const API_URL: String = "https://meme-api.com/gimme/%s/%d"
const ID_PREFIX: String = "reddit-"
## meme-api.com returns at most 50 posts per request.
const MAX_PER_REQUEST: int = 50
const MAX_ENTRIES: int = 100
## Subreddits the catalogue draws from by default.
const DEFAULT_SUBREDDITS: PackedStringArray = ["memes", "dankmemes", "MemeTemplatesOfficial", "me_irl"]
const _NAME_PATTERN: String = "^[A-Za-z0-9]{1,24}$"
const _SUBREDDIT_PATTERN: String = "^[A-Za-z0-9_]{2,21}$"
const _IMAGE_PATTERN: String = "^https://i\\.redd\\.it/([A-Za-z0-9]{1,24})\\.(jpg|jpeg|png)$"
## Reddit's own small previews (signed, so they can't be rebuilt; only used in the list).
const _PREVIEW_PATTERN: String = "^https://preview\\.redd\\.it/[A-Za-z0-9]{1,24}\\.(jpg|jpeg|png)\\?width=(108|216|320)&crop=smart(&auto=webp)?&s=[0-9a-f]{40}$"
const _IMAGE_URL: String = "https://i.redd.it/%s.%s"


## True for a subreddit name ("memes", not "r/memes").
static func is_valid_subreddit(subreddit: String) -> bool:
	return RegEx.create_from_string(_SUBREDDIT_PATTERN).search(subreddit) != null


## "r/memes" or "/r/memes" -> "memes"; "" if [param query] doesn't name a subreddit.
static func subreddit_in(query: String) -> String:
	var text: String = query.strip_edges().trim_prefix("/")
	if not text.to_lower().begins_with("r/"):
		return ""
	var subreddit: String = text.substr(2).strip_edges().trim_suffix("/")
	return subreddit if is_valid_subreddit(subreddit) else ""


static func api_url(subreddit: String, count: int) -> String:
	return API_URL % [subreddit, clampi(count, 1, MAX_PER_REQUEST)]


## Parses a meme-api.com answer, in its order. Empty if it is malformed.
static func parse_response(json_text: String, limit: int = MAX_ENTRIES) -> Array[Dictionary]:
	var json := JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return []
	var memes: Variant = (json.data as Dictionary).get("memes")
	var result: Array[Dictionary] = []
	if not memes is Array:
		return result
	var seen: Dictionary = {}
	var image := RegEx.create_from_string(_IMAGE_PATTERN)
	for meme: Variant in memes:
		if result.size() >= mini(limit, MAX_ENTRIES):
			break
		if not meme is Dictionary:
			continue
		var m: Dictionary = meme
		if m.get("nsfw") != false or m.get("spoiler") == true:
			continue
		var found: RegExMatch = image.search(str(m.get("url", "")))
		if found == null:
			continue
		var raw: Dictionary = {"id": id_for(found.get_string(1), found.get_string(2)), "name": m.get("title", "")}
		var previews: Variant = m.get("preview")
		if previews is Array and (previews as Array).size() >= 2:
			raw["thumb_url"] = (previews as Array)[1]  # 216 px wide
		var clean: Dictionary = sanitize_entry(raw)
		if not clean.is_empty() and not seen.has(clean["id"]):
			seen[clean["id"]] = true
			result.append(clean)
	return result


static func id_for(file_name: String, extension: String) -> String:
	return ID_PREFIX + file_name + "-" + extension.to_lower()


static func is_online_id(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


## The minimal entry for a template id, or {} if it isn't a valid one.
static func resolve(id: String) -> Dictionary:
	if not is_online_id(id) or not MemeSpec.is_valid_template_id(id):
		return {}
	var rest: String = id.trim_prefix(ID_PREFIX)
	var dash: int = rest.rfind("-")
	if dash <= 0:
		return {}
	var file_name: String = rest.substr(0, dash)
	var extension: String = rest.substr(dash + 1)
	if not extension in ["jpg", "jpeg", "png"] or RegEx.create_from_string(_NAME_PATTERN).search(file_name) == null:
		return {}
	return {"id": id, "name": id, "url": _IMAGE_URL % [file_name, extension], "width": 0, "height": 0}


## One entry from an untrusted source, or {} if it is not acceptable.
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
	var label: String = MemeSpec.sanitize_caption(e.get("name", "")).substr(0, MemeTemplateLibrary.NAME_MAX_LENGTH)
	clean["name"] = label if not label.is_empty() else "Reddit meme"
	var thumb: Variant = e.get("thumb_url")
	if typeof(thumb) == TYPE_STRING and RegEx.create_from_string(_PREVIEW_PATTERN).search(thumb) != null:
		clean["thumb_url"] = thumb
	return clean
