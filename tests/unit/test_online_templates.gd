extends GutTest
## Online (Imgflip) templates: parsing and validating the catalogue, the library's online
## half, image decoding and the disk cache. Nothing here touches the network.

const RESPONSE: String = """{"success": true, "data": {"memes": [
	{"id": "181913649", "name": "Drake Hotline Bling", "url": "https://i.imgflip.com/30b1gx.jpg", "width": 1200, "height": 1200, "box_count": 2},
	{"id": "87743020", "name": "Two Buttons", "url": "https://i.imgflip.com/1g8my4.jpg", "width": 600, "height": 908, "box_count": 3},
	{"id": "112126428", "name": "Distracted Boyfriend", "url": "https://i.imgflip.com/1ur9b0.png", "width": 1200, "height": 800, "box_count": 3}
]}}"""
const TEST_URL: String = "https://i.imgflip.com/guttest1.png"


func before_all() -> void:
	TemplateImageCache.offline = true


func after_all() -> void:
	TemplateImageCache.offline = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TemplateImageCache.cache_path(TEST_URL)))


func _entry(id: String, url: String, width: Variant = 400, height: Variant = 300, name: Variant = "Meme") -> Dictionary:
	return {"id": id, "name": name, "url": url, "width": width, "height": height}


func _library() -> MemeTemplateLibrary:
	return MemeTemplateLibrary.from_json('{"templates": [{"id": "crt_static", "name": "Grin"}, {"id": "empty_chair"}]}')


# --- Catalogue ----------------------------------------------------------------------------

func test_parses_an_api_answer_in_popularity_order() -> void:
	var entries: Array[Dictionary] = ImgflipCatalogue.parse_response(RESPONSE)
	assert_eq(entries.size(), 3)
	assert_eq(entries[0]["id"], "imgflip-181913649")
	assert_eq(entries[0]["name"], "Drake Hotline Bling")
	assert_eq(entries[1]["width"], 600)
	assert_eq(entries[1]["height"], 908)
	assert_true(MemeSpec.is_valid_template_id(entries[2]["id"]), "online ids must pass the meme id check")


func test_limit_keeps_the_most_popular() -> void:
	var entries: Array[Dictionary] = ImgflipCatalogue.parse_response(RESPONSE, 2)
	assert_eq(entries.size(), 2)
	assert_eq(entries[1]["name"], "Two Buttons")


func test_unsuccessful_or_broken_answers_give_nothing() -> void:
	assert_eq(ImgflipCatalogue.parse_response('{"success": false, "error_message": "nope"}').size(), 0)
	assert_eq(ImgflipCatalogue.parse_response("not json").size(), 0)
	assert_eq(ImgflipCatalogue.parse_response('{"success": true, "data": {"memes": "x"}}').size(), 0)
	assert_eq(ImgflipCatalogue.parse_response("").size(), 0)


func test_only_imgflip_image_urls_are_accepted() -> void:
	assert_true(ImgflipCatalogue.is_valid_url("https://i.imgflip.com/30b1gx.jpg"))
	assert_true(ImgflipCatalogue.is_valid_url("https://i.imgflip.com/1ur9b0.png"))
	for bad: String in [
		"http://i.imgflip.com/30b1gx.jpg",  # not https
		"https://evil.example/30b1gx.jpg",
		"https://i.imgflip.com.evil.example/30b1gx.jpg",
		"https://i.imgflip.com/../secret.jpg",
		"https://i.imgflip.com/a/b.jpg",
		"https://i.imgflip.com/30b1gx.gif",  # GIFs come later
		"https://i.imgflip.com/30b1gx.jpg?x=1",
		"file:///C:/Windows/win.ini",
	]:
		assert_false(ImgflipCatalogue.is_valid_url(bad), bad)


func test_sanitize_drops_bad_entries_from_a_host() -> void:
	var entries: Array[Dictionary] = ImgflipCatalogue.sanitize([
		_entry("imgflip-1", "https://i.imgflip.com/aaa.jpg"),
		_entry("imgflip-1", "https://i.imgflip.com/bbb.jpg"),  # duplicate id
		_entry("crt_static", "https://i.imgflip.com/ccc.jpg"),  # not an online id
		_entry("imgflip-abc", "https://i.imgflip.com/ddd.jpg"),  # not a numeric Imgflip id
		_entry("imgflip-2", "https://evil.example/eee.jpg"),
		_entry("imgflip-3", "https://i.imgflip.com/fff.jpg", 99999, 300),
		_entry("imgflip-4", "https://i.imgflip.com/ggg.jpg", "400", 300),
		_entry("imgflip-5", "https://i.imgflip.com/hhh.jpg", 400, 300, {"evil": true}),
		"not a dictionary",
		_entry("imgflip-6", "https://i.imgflip.com/iii.jpg", 400.0, 300, "Line\nbreak  name"),
	])
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(entry["id"])
	assert_eq(ids, ["imgflip-1", "imgflip-5", "imgflip-6"] as Array[String])
	assert_eq(entries[1]["name"], "imgflip-5", "a non-string name falls back to the id")
	assert_eq(entries[2]["name"], "Line break name")
	assert_eq(ImgflipCatalogue.sanitize("nope").size(), 0)


func test_sanitize_caps_the_count() -> void:
	var many: Array = []
	for i: int in range(ImgflipCatalogue.MAX_ENTRIES + 20):
		many.append(_entry("imgflip-%d" % i, "https://i.imgflip.com/x%d.jpg" % i))
	assert_eq(ImgflipCatalogue.sanitize(many, 1000).size(), ImgflipCatalogue.MAX_ENTRIES)


# --- Library ------------------------------------------------------------------------------

func test_online_templates_come_first_and_can_be_replaced() -> void:
	var library: MemeTemplateLibrary = _library()
	assert_false(library.has_online())
	library.set_online(ImgflipCatalogue.parse_response(RESPONSE, 2))
	assert_eq(library.ids(), PackedStringArray(["imgflip-181913649", "imgflip-87743020", "crt_static", "empty_chair"]))
	assert_eq(library.original_ids(), PackedStringArray(["crt_static", "empty_chair"]))
	assert_true(library.is_online("imgflip-87743020"))
	assert_false(library.is_online("crt_static"))
	assert_eq(library.display_name("imgflip-87743020"), "Two Buttons")
	assert_almost_eq(library.aspect("imgflip-87743020"), 600.0 / 908.0, 0.0001)
	assert_almost_eq(library.aspect("crt_static"), 4.0 / 3.0, 0.0001)
	assert_eq(library.online_entries().size(), 2)
	library.set_online([] as Array[Dictionary])
	assert_eq(library.ids(), PackedStringArray(["crt_static", "empty_chair"]))
	assert_false(library.has("imgflip-181913649"))
	assert_eq(library.display_name("imgflip-181913649"), "imgflip-181913649")


func test_the_json_file_cannot_claim_online_ids() -> void:
	var library := MemeTemplateLibrary.from_json('{"templates": [{"id": "imgflip-5"}, {"id": "ok_one"}]}')
	assert_eq(library.ids(), PackedStringArray(["ok_one"]))


func test_server_accepts_online_ids_it_was_given() -> void:
	var library: MemeTemplateLibrary = _library()
	library.set_online(ImgflipCatalogue.parse_response(RESPONSE))
	var spec: MemeSpec = MemeSpec.from_untrusted({"template_id": "imgflip-112126428", "top_text": "me"}, library.ids())
	assert_not_null(spec)
	assert_null(MemeSpec.from_untrusted({"template_id": "imgflip-999"}, library.ids()))


func test_missing_image_offline_is_reported_as_failed() -> void:
	var library: MemeTemplateLibrary = _library()
	library.set_online([_entry("imgflip-77", "https://i.imgflip.com/nothere1.jpg")] as Array[Dictionary])
	assert_null(library.texture("imgflip-77"))
	assert_true(library.image_failed("imgflip-77"))
	assert_false(library.image_failed("crt_static"))


func test_cached_image_loads_without_the_network() -> void:
	var image := Image.create(40, 30, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TemplateImageCache.CACHE_DIR))
	var file := FileAccess.open(TemplateImageCache.cache_path(TEST_URL), FileAccess.WRITE)
	file.store_buffer(image.save_png_to_buffer())
	file.close()
	var library: MemeTemplateLibrary = _library()
	library.set_online([_entry("imgflip-78", TEST_URL, 40, 30)] as Array[Dictionary])
	watch_signals(library)
	assert_null(library.texture("imgflip-78"), "decoding happens off the main thread")
	await wait_for_signal(library.image_updated, 5.0)
	assert_signal_emitted_with_parameters(library, "image_updated", ["imgflip-78"])
	var texture: Texture2D = library.texture("imgflip-78")
	assert_not_null(texture)
	assert_eq(texture.get_size(), Vector2(40, 30))
	assert_false(library.image_failed("imgflip-78"))


# --- Images and layout --------------------------------------------------------------------

func test_decode_reads_png_and_jpg_and_rejects_junk() -> void:
	var image := Image.create(20, 10, false, Image.FORMAT_RGB8)
	assert_not_null(TemplateImageCache.decode(image.save_png_to_buffer()))
	assert_not_null(TemplateImageCache.decode(image.save_jpg_to_buffer()))
	assert_null(TemplateImageCache.decode(PackedByteArray([1, 2, 3, 4, 5])))
	assert_null(TemplateImageCache.decode(PackedByteArray()))


func test_decode_scales_big_images_down() -> void:
	var image := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	var decoded: Image = TemplateImageCache.decode(image.save_png_to_buffer())
	assert_eq(decoded.get_width(), TemplateImageCache.MAX_TEXTURE_SIDE)
	assert_eq(decoded.get_height(), TemplateImageCache.MAX_TEXTURE_SIDE / 2)


func test_cache_paths_are_flat_and_keep_the_extension() -> void:
	var path: String = TemplateImageCache.cache_path("https://i.imgflip.com/30b1gx.jpg")
	assert_true(path.begins_with(TemplateImageCache.CACHE_DIR))
	assert_eq(path.get_extension(), "jpg")
	assert_false(path.trim_prefix(TemplateImageCache.CACHE_DIR).contains("/"))


func test_tall_templates_are_letterboxed_in_the_frame() -> void:
	var frame := Rect2(0, 0, 400, 300)
	var tall: Rect2 = MemeRenderer.fit_rect(frame, 0.5)
	assert_eq(tall.size, Vector2(150, 300))
	assert_eq(tall.position, Vector2(125, 0))
	var wide: Rect2 = MemeRenderer.fit_rect(frame, 2.0)
	assert_eq(wide.size, Vector2(400, 200))
	assert_eq(wide.position, Vector2(0, 50))


func test_renderer_puts_captions_on_the_image() -> void:
	var library: MemeTemplateLibrary = _library()
	library.set_online(ImgflipCatalogue.parse_response(RESPONSE))
	var renderer := MemeRenderer.new()
	renderer.library = library
	renderer.size = Vector2(400, 300)
	add_child_autofree(renderer)
	renderer.set_meme(MemeSpec.new("imgflip-87743020", "top", "bottom"))
	var rect: Rect2 = renderer.image_rect()
	assert_almost_eq(rect.size.y, 300.0, 0.01)
	assert_almost_eq(rect.size.x, 300.0 * 600.0 / 908.0, 0.01)
	renderer.set_meme(MemeSpec.new("crt_static", "top", "bottom"))
	assert_eq(renderer.image_rect(), renderer.meme_rect())
