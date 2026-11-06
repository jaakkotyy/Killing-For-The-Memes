extends GutTest

const BOX: Vector2 = Vector2(400, 120)


func test_short_text_uses_the_largest_size() -> void:
	assert_eq(MemeRenderer.fit_font_size(MemeRenderer.meme_font(), "HI", BOX, 60, 12), 60)


func test_long_text_shrinks_to_fit() -> void:
	var font: Font = MemeRenderer.meme_font()
	var text: String = "WHEN YOU REALISE THE HOST HAS BEEN WATCHING YOU TYPE THIS WHOLE TIME"
	var size: int = MemeRenderer.fit_font_size(font, text, BOX, 60, 12)
	assert_lt(size, 60)
	var needed: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, BOX.x, size)
	assert_true(needed.y <= BOX.y, "fits the box at the chosen size")


func test_never_goes_below_the_minimum() -> void:
	var text: String = "A".repeat(MemeSpec.CAPTION_MAX_LENGTH)
	assert_eq(MemeRenderer.fit_font_size(MemeRenderer.meme_font(), text, Vector2(40, 10), 60, 12), 12)


func test_meme_rect_is_four_by_three_and_centred() -> void:
	var renderer: MemeRenderer = add_child_autofree(MemeRenderer.new())
	renderer.size = Vector2(1000, 600)
	var rect: Rect2 = renderer.meme_rect()
	assert_almost_eq(rect.size.x / rect.size.y, 4.0 / 3.0, 0.001)
	assert_almost_eq(rect.size.y, 600.0, 0.001)
	assert_almost_eq(rect.get_center().x, 500.0, 0.001)
