class_name MemeSpec
extends RefCounted
## A meme as data: which template and what captions. This is what travels over the network;
## every client renders it locally, so no images are ever sent.

const CAPTION_MAX_LENGTH: int = 80
## Template ids are short slugs, e.g. "sad_clown" or "office_fire_02".
const _TEMPLATE_ID_PATTERN: String = "^[a-z0-9_-]{1,40}$"

var template_id: String = ""
var top_text: String = ""
var bottom_text: String = ""


func _init(p_template_id: String = "", p_top_text: String = "", p_bottom_text: String = "") -> void:
	template_id = p_template_id
	top_text = p_top_text
	bottom_text = p_bottom_text


## True for the placeholder shown when a player submitted nothing.
func is_blank() -> bool:
	return template_id.is_empty()


func to_dict() -> Dictionary:
	return {"template_id": template_id, "top_text": top_text, "bottom_text": bottom_text}


## Builds a MemeSpec from untrusted input (e.g. an RPC argument).
## Returns null if the input is malformed. Captions are cleaned and trimmed rather than
## rejected, so a slightly-too-long caption never costs a player their round.
## When [param allowed_templates] is not empty, the template must be one of them.
static func from_untrusted(data: Variant, allowed_templates: PackedStringArray = PackedStringArray()) -> MemeSpec:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data
	var template: Variant = dict.get("template_id")
	if typeof(template) != TYPE_STRING:
		return null
	var template_text: String = template
	if RegEx.create_from_string(_TEMPLATE_ID_PATTERN).search(template_text) == null:
		return null
	if not allowed_templates.is_empty() and not allowed_templates.has(template_text):
		return null
	return MemeSpec.new(template_text, sanitize_caption(dict.get("top_text", "")), sanitize_caption(dict.get("bottom_text", "")))


## Trusted counterpart of to_dict(), for snapshots coming from the server.
static func from_dict(data: Dictionary) -> MemeSpec:
	return MemeSpec.new(str(data.get("template_id", "")), str(data.get("top_text", "")), str(data.get("bottom_text", "")))


## Removes control characters (newlines included: captions are single lines that the renderer
## wraps), collapses whitespace and limits the length.
static func sanitize_caption(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var text: String = raw
	var printable: String = ""
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		printable += text[i] if code >= 32 and code != 127 else " "
	var collapsed: String = " ".join(printable.split(" ", false))
	return collapsed.substr(0, CAPTION_MAX_LENGTH).strip_edges()
