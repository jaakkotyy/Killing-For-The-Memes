class_name TemplateCatalogue
extends RefCounted
## The online template catalogue as a whole: entries from every provider (Imgflip stills,
## GIPHY GIFs), validated by the provider their id prefix names. This is what the host
## sends with the game start and what clients check before using it.

## All providers together; a host sending more is cut off here.
const MAX_ENTRIES: int = 150


## Validates entries from an untrusted source. Unknown providers, bad entries and duplicate
## ids are dropped, never fatal. Order is kept.
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


static func sanitize_entry(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var id: Variant = (entry as Dictionary).get("id")
	if typeof(id) != TYPE_STRING:
		return {}
	if ImgflipCatalogue.is_online_id(id):
		return ImgflipCatalogue.sanitize_entry(entry)
	if GiphyCatalogue.is_online_id(id):
		return GiphyCatalogue.sanitize_entry(entry)
	return {}


## True for ids of any online provider (never allowed in data/meme_templates.json).
static func is_online_id(id: String) -> bool:
	return ImgflipCatalogue.is_online_id(id) or GiphyCatalogue.is_online_id(id)
