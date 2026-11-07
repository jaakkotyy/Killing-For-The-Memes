extends GutTest
## Guess mode's database: loading and validating identity packs, filters, queries and
## the deck that deals identities.

const PACK: String = """{
	"id": "test", "name": "Test Pack", "version": 1,
	"fields": [
		{"id": "kind", "name": "Kind", "type": "enum"},
		{"id": "born", "name": "Born", "type": "year"},
		{"id": "alive", "name": "Alive", "type": "bool"},
		{"id": "genres", "name": "Genres", "type": "tags"},
		{"id": "kind", "name": "Duplicate", "type": "enum"},
		{"id": "bad id!", "type": "enum"},
		{"id": "odd", "type": "colour"}
	],
	"questions": [
		{"text": "Am I a band?", "filter": {"field": "kind", "op": "is", "value": "band"}},
		{"text": "Was I born before 1980?", "filter": {"field": "born", "op": "before", "value": 1980}},
		{"text": "Broken", "filter": {"field": "born", "op": "has", "value": 1980}},
		{"text": "", "filter": {"field": "kind", "op": "is", "value": "band"}}
	],
	"entries": [
		{"id": "Q1", "name": "Alpha Band", "fame": 90, "fields": {"kind": "band", "born": 1962, "alive": false, "genres": ["rock", "pop"]}},
		{"id": "Q2", "name": "Beta  Singer", "fame": 150, "fields": {"kind": "person", "born": 1985, "alive": true, "genres": ["pop"]}},
		{"id": "Q3", "name": "Gamma Mystery", "fame": 10, "fields": {"kind": "person"}},
		{"id": "Q4", "name": "Delta Duo", "fame": 60, "fields": {"kind": "band", "born": "1990", "alive": "yes", "genres": "rock"}},
		{"id": "Q1", "name": "Duplicate id"},
		{"id": "Q5", "name": ""},
		{"id": "../Q6", "name": "Bad id"},
		"not an entry"
	]
}"""

var pack: IdentityPack


func before_each() -> void:
	pack = IdentityPack.from_json(PACK)


func _filter(field: String, op: String, value: Variant) -> IdentityFilter:
	return IdentityFilter.from_untrusted({"field": field, "op": op, "value": value}, pack)


func _ids(entries: Array[IdentityPack.Entry]) -> Array[String]:
	var ids: Array[String] = []
	for entry: IdentityPack.Entry in entries:
		ids.append(entry.id)
	return ids


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Pack ---------------------------------------------------------------------------------

func test_loads_valid_parts_and_drops_the_rest() -> void:
	assert_not_null(pack)
	assert_eq(pack.name, "Test Pack")
	assert_eq(pack.fields().size(), 4, "duplicate, badly named and unknown-type fields are dropped")
	assert_eq(pack.size(), 4)
	assert_eq(pack.get_entry("Q2").name, "Beta Singer", "whitespace is cleaned")
	assert_eq(pack.get_entry("Q1").name, "Alpha Band", "the first of a duplicate id wins")
	assert_false(pack.has_entry("../Q6"))
	assert_eq(pack.stock_questions().size(), 2, "questions with a bad filter or no text are dropped")


func test_values_of_the_wrong_type_become_unknown() -> void:
	var delta: IdentityPack.Entry = pack.get_entry("Q4")
	assert_true(delta.has_value("kind"))
	assert_false(delta.has_value("born"), "a year as a string is not a year")
	assert_false(delta.has_value("alive"))
	assert_false(delta.has_value("genres"), "tags must be a list")
	assert_eq(pack.get_entry("Q1").value("genres"), PackedStringArray(["rock", "pop"]))


func test_broken_packs_give_null() -> void:
	assert_null(IdentityPack.from_json("not json"))
	assert_null(IdentityPack.from_json("[]"))
	assert_null(IdentityPack.from_json('{"id": "x", "entries": []}'))
	assert_null(IdentityPack.load_file("res://data/identities/does_not_exist.json"))


func test_pickers_list_every_value() -> void:
	assert_eq(pack.values_of("kind"), PackedStringArray(["band", "person"]))
	assert_eq(pack.values_of("genres"), PackedStringArray(["pop", "rock"]))
	assert_eq(pack.values_of("born"), PackedStringArray(), "years have no picker list")
	assert_eq(pack.year_range("born"), Vector2i(1962, 1985))
	assert_eq(pack.year_range("kind"), Vector2i.ZERO)


func test_stock_questions_from_the_network_are_checked() -> void:
	assert_eq(pack.stock_question(0).text, "Am I a band?")
	assert_null(pack.stock_question(2))
	assert_null(pack.stock_question(-1))
	assert_null(pack.stock_question("0"))


# --- Filters ------------------------------------------------------------------------------

func test_filters_are_validated_against_the_field() -> void:
	assert_not_null(_filter("born", "before", 1980))
	assert_not_null(_filter("born", "between", [1990, 1960]))
	assert_null(_filter("born", "is", 1980), "years have no 'is'")
	assert_null(_filter("born", "before", "1980"))
	assert_null(_filter("kind", "is", 3))
	assert_null(_filter("nope", "is", "band"))
	assert_null(_filter("genres", "has", ["rock"]))
	assert_null(_filter("born", "between", [1990]))
	assert_null(IdentityFilter.from_untrusted("born < 1980", pack))
	assert_eq(_filter("born", "between", [1990, 1960]).value, Vector2i(1960, 1990), "range is put in order")


func test_each_operator_matches() -> void:
	var alpha: IdentityPack.Entry = pack.get_entry("Q1")  # band, 1962, dead, rock+pop
	var beta: IdentityPack.Entry = pack.get_entry("Q2")  # person, 1985, alive, pop
	assert_true(_filter("kind", "is", "band").matches(alpha))
	assert_false(_filter("kind", "is", "band").matches(beta))
	assert_true(_filter("kind", "is_not", "band").matches(beta))
	assert_true(_filter("born", "before", 1980).matches(alpha))
	assert_false(_filter("born", "before", 1962).matches(alpha), "before is strict")
	assert_true(_filter("born", "from", 1962).matches(alpha))
	assert_true(_filter("born", "between", [1980, 1989]).matches(beta))
	assert_false(_filter("born", "not_between", [1980, 1989]).matches(beta))
	assert_true(_filter("alive", "is", true).matches(beta))
	assert_false(_filter("alive", "is", true).matches(alpha))
	assert_true(_filter("genres", "has", "rock").matches(alpha))
	assert_true(_filter("genres", "has_not", "rock").matches(beta))


func test_unknown_values_are_never_crossed_out() -> void:
	var gamma: IdentityPack.Entry = pack.get_entry("Q3")  # only kind is known
	for filter: IdentityFilter in [_filter("born", "before", 1900), _filter("born", "from", 1900),
			_filter("alive", "is", true), _filter("alive", "is", false), _filter("genres", "has", "jazz")]:
		assert_true(filter.matches(gamma), filter.describe())


func test_negation_is_the_exact_opposite_for_known_values() -> void:
	var filters: Array[IdentityFilter] = [_filter("kind", "is", "band"), _filter("kind", "is_not", "band"),
		_filter("born", "before", 1980), _filter("born", "from", 1980), _filter("born", "between", [1960, 1970]),
		_filter("born", "not_between", [1960, 1970]), _filter("alive", "is", true), _filter("genres", "has", "rock"),
		_filter("genres", "has_not", "rock")]
	for filter: IdentityFilter in filters:
		for id: String in ["Q1", "Q2"]:
			var entry: IdentityPack.Entry = pack.get_entry(id)
			assert_ne(filter.matches(entry), filter.negated().matches(entry), "%s on %s" % [filter.describe(), id])


func test_filters_round_trip_through_data() -> void:
	for filter: IdentityFilter in [_filter("born", "between", [1960, 1970]), _filter("alive", "is", false),
			_filter("genres", "has", "pop")]:
		var again: IdentityFilter = IdentityFilter.from_untrusted(filter.to_dict(), pack)
		assert_not_null(again)
		assert_eq(again.to_dict(), filter.to_dict())


func test_descriptions_read_like_chips() -> void:
	assert_eq(_filter("born", "before", 1980).describe(), "Born before 1980")
	assert_eq(_filter("alive", "is", false).describe(), "Alive: no")
	assert_eq(_filter("genres", "has_not", "rock").describe(), "Genres: not rock")


# --- Query --------------------------------------------------------------------------------

func test_query_combines_filters_and_sorts_by_fame() -> void:
	var query := IdentityQuery.new()
	assert_eq(_ids(query.run(pack)), ["Q2", "Q1", "Q4", "Q3"] as Array[String], "best known first")
	query.add_filter(_filter("genres", "has_not", "rock"))
	assert_eq(_ids(query.run(pack)), ["Q2", "Q4", "Q3"] as Array[String], "Q4's and Q3's genres are unknown")
	query.add_filter(_filter("kind", "is", "band"))
	assert_eq(_ids(query.run(pack)), ["Q4"] as Array[String])
	query.remove_filter(0)
	assert_eq(_ids(query.run(pack)), ["Q1", "Q4"] as Array[String])


func test_name_search_ignores_case() -> void:
	var query := IdentityQuery.new()
	query.text = "  band "
	assert_eq(_ids(query.run(pack)), ["Q1"] as Array[String])


func test_struck_candidates_sink_or_vanish() -> void:
	var query := IdentityQuery.new()
	query.toggle_struck("Q2")
	assert_eq(_ids(query.run(pack)), ["Q1", "Q4", "Q3", "Q2"] as Array[String])
	assert_eq(query.count_open(pack), 3)
	query.keep_struck = false
	assert_eq(_ids(query.run(pack)), ["Q1", "Q4", "Q3"] as Array[String])
	query.toggle_struck("Q2")
	assert_eq(query.count_open(pack), 4)


# --- Deck ---------------------------------------------------------------------------------

func test_deals_distinct_identities_from_the_best_known() -> void:
	var deck := IdentityDeck.new(pack, _rng(4), 3)
	assert_eq(deck.size(), 3)
	for i: int in range(20):
		var hand: PackedStringArray = deck.deal(3)
		assert_eq(hand.size(), 3)
		assert_false(hand.has("Q3"), "the least known entry is outside the pool")
		var sorted: Array = Array(hand)
		sorted.sort()
		assert_eq(sorted, ["Q1", "Q2", "Q4"])


func test_no_repeats_until_the_pool_runs_out() -> void:
	var deck := IdentityDeck.new(pack, _rng(9))
	var seen: Dictionary = {}
	for i: int in range(2):
		for id: String in deck.deal(2):
			assert_false(seen.has(id), "%s dealt twice" % id)
			seen[id] = true
	assert_eq(seen.size(), 4)


func test_a_small_pool_deals_what_it_has() -> void:
	assert_eq(IdentityDeck.new(pack, _rng(1)).deal(8).size(), 4)


func test_same_seed_same_deal() -> void:
	var a := IdentityDeck.new(pack, _rng(42))
	var b := IdentityDeck.new(pack, _rng(42))
	for i: int in range(5):
		assert_eq(a.deal(3), b.deal(3))
