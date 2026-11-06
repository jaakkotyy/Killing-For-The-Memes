extends GutTest


func test_parses_templates_in_order() -> void:
	var library: MemeTemplateLibrary = MemeTemplateLibrary.from_json(
		'{"templates": [{"id": "b_one", "name": "One"}, {"id": "a_two", "name": "Two"}]}')
	assert_eq(library.ids(), PackedStringArray(["b_one", "a_two"]))
	assert_eq(library.display_name("a_two"), "Two")


func test_skips_bad_and_duplicate_entries() -> void:
	var library: MemeTemplateLibrary = MemeTemplateLibrary.from_json(JSON.stringify({"templates": [
		{"id": "ok_one", "name": "Fine"},
		{"id": "Bad Id"},
		{"id": 7},
		"not a dict",
		{"id": "ok_one", "name": "Duplicate"},
		{"id": "no_name"},
	]}))
	assert_eq(library.ids(), PackedStringArray(["ok_one", "no_name"]))
	assert_eq(library.display_name("ok_one"), "Fine", "the first entry wins")
	assert_eq(library.display_name("no_name"), "no_name", "the id is the fallback name")


func test_broken_json_gives_an_empty_library() -> void:
	assert_true(MemeTemplateLibrary.from_json("{nope").is_empty())
	assert_true(MemeTemplateLibrary.from_json('{"templates": 3}').is_empty())


func test_unknown_template_has_no_texture() -> void:
	assert_null(MemeTemplateLibrary.get_default().texture("does_not_exist"))


func test_every_default_template_has_an_image() -> void:
	var library: MemeTemplateLibrary = MemeTemplateLibrary.get_default()
	assert_gte(library.size(), 5, "a decent choice of templates")
	for id: String in library.ids():
		assert_not_null(library.texture(id), "image for %s" % id)


func test_default_ids_pass_meme_validation() -> void:
	var library: MemeTemplateLibrary = MemeTemplateLibrary.get_default()
	for id: String in library.ids():
		assert_not_null(MemeSpec.from_untrusted({"template_id": id}, library.ids()))
