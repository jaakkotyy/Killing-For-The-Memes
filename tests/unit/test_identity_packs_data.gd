extends GutTest
## The identity packs we ship (data/identities/*.json) load completely and are playable.

const PACK_DIR: String = "res://data/identities/"
## Enough candidates that the terminal's search matters, and a full table can be dealt.
const MIN_ENTRIES: int = 300


func _pack_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	for file: String in DirAccess.get_files_at(PACK_DIR):
		if file.get_extension() == "json":
			paths.append(PACK_DIR + file)
	return paths


func test_there_are_packs() -> void:
	assert_gt(_pack_paths().size(), 0)


func test_every_pack_loads_without_losing_anything() -> void:
	for path: String in _pack_paths():
		var json := JSON.new()
		assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK, path)
		var raw: Dictionary = json.data
		var pack: IdentityPack = IdentityPack.load_file(path)
		assert_not_null(pack, path)
		assert_eq(pack.id, path.get_file().get_basename(), "the id matches the file name")
		assert_eq(pack.fields().size(), (raw["fields"] as Array).size(), "%s: every field is valid" % path)
		assert_eq(pack.size(), (raw["entries"] as Array).size(), "%s: every entry is valid" % path)
		assert_eq(pack.stock_questions().size(), (raw["questions"] as Array).size(), "%s: every stock question is valid" % path)
		assert_gte(pack.size(), MIN_ENTRIES, path)


func test_every_stock_question_has_both_answers_somewhere() -> void:
	for path: String in _pack_paths():
		var pack: IdentityPack = IdentityPack.load_file(path)
		for question: IdentityPack.StockQuestion in pack.stock_questions():
			var yes: int = 0
			var no: int = 0
			for entry: IdentityPack.Entry in pack.entries():
				if not entry.has_value(question.filter.field.id):
					continue
				if question.filter.matches(entry):
					yes += 1
				else:
					no += 1
			assert_true(yes > 0 and no > 0, "%s: \"%s\" splits the pack (%d yes, %d no)" % [path, question.text, yes, no])


func test_a_full_table_can_be_dealt() -> void:
	for path: String in _pack_paths():
		var deck := IdentityDeck.new(IdentityPack.load_file(path))
		assert_eq(deck.deal(Protocol.MAX_PLAYERS).size(), Protocol.MAX_PLAYERS, path)
