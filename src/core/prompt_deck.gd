class_name PromptDeck
extends RefCounted
## A shuffled deck of meme prompts. Draws never repeat until the whole deck has been used,
## then it reshuffles (avoiding an immediate repeat of the last prompt).
##
## Prompt packs are JSON files in data/prompts/:
##   {"id": "default", "name": "Default Pack", "version": 1, "prompts": ["...", "..."]}

const PROMPT_MAX_LENGTH: int = 140

var pack_id: String = ""
var pack_name: String = ""

var _prompts: PackedStringArray = []
var _order: PackedStringArray = []
var _last_drawn: String = ""
var _rng: RandomNumberGenerator


func _init(prompts: PackedStringArray = PackedStringArray(), rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	for prompt: String in prompts:
		var cleaned: String = prompt.strip_edges().substr(0, PROMPT_MAX_LENGTH)
		if not cleaned.is_empty() and not _prompts.has(cleaned):
			_prompts.append(cleaned)


## Parses a prompt pack. Returns null when the JSON is not a valid pack with at least one prompt.
static func from_json(json_text: String, rng: RandomNumberGenerator = null) -> PromptDeck:
	# JSON.parse() reports errors through its return value; parse_string() would also
	# log an engine error for every malformed pack.
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return null
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var raw_prompts: Variant = (data as Dictionary).get("prompts")
	if typeof(raw_prompts) != TYPE_ARRAY:
		return null
	var prompts: PackedStringArray = []
	for entry: Variant in raw_prompts:
		if typeof(entry) == TYPE_STRING:
			prompts.append(entry)
	var deck := PromptDeck.new(prompts, rng)
	if deck.size() == 0:
		return null
	deck.pack_id = str((data as Dictionary).get("id", ""))
	deck.pack_name = str((data as Dictionary).get("name", ""))
	return deck


func size() -> int:
	return _prompts.size()


func draw() -> String:
	if _prompts.is_empty():
		return ""
	if _order.is_empty():
		_reshuffle()
	var prompt: String = _order[_order.size() - 1]
	_order.remove_at(_order.size() - 1)
	_last_drawn = prompt
	return prompt


func _reshuffle() -> void:
	var shuffled: Array[String] = []
	shuffled.assign(_prompts)
	# Fisher-Yates with the injected RNG so matches are reproducible from a seed.
	for i: int in range(shuffled.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: String = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	# draw() takes from the end; don't let the new deck start with the previous prompt.
	if shuffled.size() > 1 and shuffled[shuffled.size() - 1] == _last_drawn:
		var tmp_last: String = shuffled[0]
		shuffled[0] = shuffled[shuffled.size() - 1]
		shuffled[shuffled.size() - 1] = tmp_last
	_order = PackedStringArray(shuffled)
