extends GutTest
## GifDecoder against fixtures written and decoded by Pillow (tests/fixtures/gif/,
## regenerate with make_fixtures.py). Every pixel of every composited frame must match.

const DIR: String = "res://tests/fixtures/gif/"


func _gif(name: String) -> GifDecoder:
	return GifDecoder.decode(FileAccess.get_file_as_bytes(DIR + name + ".gif"))


func _expected(name: String, frame: int) -> Image:
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "%s_%d.png" % [name, frame]))
	image.convert(Image.FORMAT_RGBA8)
	return image


## Pixels that differ, ignoring the colour of fully transparent pixels.
func _differences(actual: Image, expected: Image) -> int:
	var count: int = 0
	for y: int in range(expected.get_height()):
		for x: int in range(expected.get_width()):
			var a: Color = actual.get_pixel(x, y)
			var e: Color = expected.get_pixel(x, y)
			if a.a8 == 0 and e.a8 == 0:
				continue
			if a.to_rgba32() != e.to_rgba32():
				count += 1
	return count


func _assert_matches(name: String, frame_count: int) -> GifDecoder:
	var gif: GifDecoder = _gif(name)
	assert_eq(gif.error, "", name)
	assert_eq(gif.frames.size(), frame_count, name)
	for i: int in range(mini(frame_count, gif.frames.size())):
		var expected: Image = _expected(name, i)
		assert_eq(gif.frames[i].get_size(), expected.get_size(), "%s frame %d size" % [name, i])
		assert_eq(_differences(gif.frames[i], expected), 0, "%s frame %d pixels" % [name, i])
	return gif


func test_simple_animation_and_delays() -> void:
	var gif: GifDecoder = _assert_matches("three_frames", 3)
	assert_eq(gif.width, 8)
	assert_eq(gif.height, 6)
	assert_almost_eq(gif.delays[0], 0.1, 0.001)
	assert_almost_eq(gif.delays[1], 0.2, 0.001)
	assert_almost_eq(gif.delays[2], 0.05, 0.001)
	assert_almost_eq(gif.total_duration(), 0.35, 0.001)


func test_full_palette_noise_and_partial_frames() -> void:
	_assert_matches("noise", 2)


func test_interlaced() -> void:
	_assert_matches("interlaced", 1)


func test_transparency_and_restore_to_background() -> void:
	var gif: GifDecoder = _assert_matches("transparent", 2)
	assert_eq(gif.frames[1].get_pixel(2, 2).a8, 0, "frame 0's red half was cleared")


func test_local_palettes() -> void:
	_assert_matches("local_palettes", 2)


func test_first_frame_only() -> void:
	var gif := GifDecoder.decode(FileAccess.get_file_as_bytes(DIR + "three_frames.gif"), 1)
	assert_eq(gif.frames.size(), 1)


func test_rejects_junk_without_crashing() -> void:
	assert_true(GifDecoder.decode(PackedByteArray()).frames.is_empty())
	assert_true(GifDecoder.decode("hello world, not a gif".to_utf8_buffer()).frames.is_empty())
	var huge := "GIF89a".to_ascii_buffer()
	huge.append_array(PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0]))
	assert_true(GifDecoder.decode(huge).frames.is_empty())
	assert_ne(GifDecoder.decode(huge).error, "")


func test_truncated_files_keep_what_was_read() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(DIR + "noise.gif")
	for cut: int in [20, 400, 3000, bytes.size() - 40, bytes.size() - 2]:
		var gif := GifDecoder.decode(bytes.slice(0, cut))
		assert_true(gif.frames.size() <= 2, "cut at %d" % cut)
	# Random corruption never crashes and never yields more frames than exist.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in range(30):
		var broken: PackedByteArray = bytes.duplicate()
		for j: int in range(8):
			broken[rng.randi_range(13, broken.size() - 1)] = rng.randi_range(0, 255)
		assert_true(GifDecoder.decode(broken).frames.size() <= 3)
