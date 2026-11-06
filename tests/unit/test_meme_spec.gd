extends GutTest


func test_roundtrip() -> void:
	var spec := MemeSpec.new("sad_clown", "TOP", "BOTTOM")
	var copy: MemeSpec = MemeSpec.from_untrusted(spec.to_dict())
	assert_eq(copy.to_dict(), spec.to_dict())


func test_rejects_malformed_input() -> void:
	assert_null(MemeSpec.from_untrusted("not a dict"))
	assert_null(MemeSpec.from_untrusted({}))
	assert_null(MemeSpec.from_untrusted({"template_id": 42}))
	assert_null(MemeSpec.from_untrusted({"template_id": ""}))
	assert_null(MemeSpec.from_untrusted({"template_id": "../../etc/passwd"}))
	assert_null(MemeSpec.from_untrusted({"template_id": "Has Spaces"}))
	assert_null(MemeSpec.from_untrusted({"template_id": "giphy-abc/def"}))
	assert_not_null(MemeSpec.from_untrusted({"template_id": "giphy-3o7TKSjRrfIPjeiVyM"}), "GIPHY ids are mixed case")


func test_enforces_allowed_templates() -> void:
	var allowed := PackedStringArray(["sad_clown", "office_fire"])
	assert_not_null(MemeSpec.from_untrusted({"template_id": "office_fire"}, allowed))
	assert_null(MemeSpec.from_untrusted({"template_id": "made_up"}, allowed))


func test_captions_are_cleaned_not_rejected() -> void:
	var long_text: String = "A".repeat(500)
	var spec: MemeSpec = MemeSpec.from_untrusted({
		"template_id": "sad_clown",
		"top_text": "  line one\nline   two\t ",
		"bottom_text": long_text,
	})
	assert_eq(spec.top_text, "line one line two")
	assert_eq(spec.bottom_text.length(), MemeSpec.CAPTION_MAX_LENGTH)


func test_non_string_captions_become_empty() -> void:
	var spec: MemeSpec = MemeSpec.from_untrusted({"template_id": "sad_clown", "top_text": 5, "bottom_text": null})
	assert_eq(spec.top_text, "")
	assert_eq(spec.bottom_text, "")


func test_blank_meme() -> void:
	assert_true(MemeSpec.new().is_blank())
	assert_false(MemeSpec.new("sad_clown").is_blank())
