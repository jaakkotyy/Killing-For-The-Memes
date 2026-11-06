extends GutTest


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_draws_every_prompt_once_before_repeating() -> void:
	var prompts := PackedStringArray(["a", "b", "c", "d", "e"])
	var deck := PromptDeck.new(prompts, _rng(7))
	var drawn: Array[String] = []
	for i: int in range(prompts.size()):
		drawn.append(deck.draw())
	drawn.sort()
	assert_eq(drawn, ["a", "b", "c", "d", "e"] as Array[String])


func test_no_immediate_repeat_across_reshuffles() -> void:
	var deck := PromptDeck.new(PackedStringArray(["a", "b", "c"]), _rng(3))
	var previous: String = deck.draw()
	for i: int in range(60):
		var current: String = deck.draw()
		assert_ne(current, previous, "draw %d repeated the previous prompt" % i)
		previous = current


func test_same_seed_same_order() -> void:
	var prompts := PackedStringArray(["a", "b", "c", "d", "e", "f"])
	var first := PromptDeck.new(prompts, _rng(42))
	var second := PromptDeck.new(prompts, _rng(42))
	for i: int in range(12):
		assert_eq(first.draw(), second.draw())


func test_cleans_and_dedupes_prompts() -> void:
	var deck := PromptDeck.new(PackedStringArray(["  hello ", "hello", "", "   ", "x".repeat(500)]))
	assert_eq(deck.size(), 2)


func test_empty_deck_draws_empty_string() -> void:
	assert_eq(PromptDeck.new().draw(), "")


func test_from_json() -> void:
	var deck: PromptDeck = PromptDeck.from_json('{"id": "t", "name": "Test", "prompts": ["one", 2, "three"]}')
	assert_not_null(deck)
	assert_eq(deck.size(), 2, "non-string entries are skipped")
	assert_eq(deck.pack_id, "t")
	assert_eq(deck.pack_name, "Test")


func test_from_json_rejects_bad_packs() -> void:
	assert_null(PromptDeck.from_json("not json"))
	assert_null(PromptDeck.from_json("[]"))
	assert_null(PromptDeck.from_json('{"prompts": "nope"}'))
	assert_null(PromptDeck.from_json('{"prompts": []}'))


func test_default_pack_loads() -> void:
	var text: String = FileAccess.get_file_as_string("res://data/prompts/default.json")
	var deck: PromptDeck = PromptDeck.from_json(text)
	assert_not_null(deck, "default prompt pack must parse")
	assert_gte(deck.size(), 30)
