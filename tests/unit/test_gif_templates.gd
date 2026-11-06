extends GutTest
## GIF templates: GIPHY search results, the combined catalogue, animations in the library,
## the cache and the renderer. Nothing here touches the network.

const SEARCH: String = """{"data": [
	{"type": "gif", "id": "3o7TKSjRrfIPjeiVyM", "title": "Happy Dance GIF by Some Studio",
		"images": {"fixed_height": {"url": "https://media2.giphy.com/media/v1.Y2lk/3o7TKSjRrfIPjeiVyM/200.gif?cid=x&ct=g", "width": "356", "height": "200"},
			"fixed_height_still": {"url": "https://media2.giphy.com/media/3o7TKSjRrfIPjeiVyM/200_s.gif", "width": "356", "height": "200"}}},
	{"type": "gif", "id": "l0MYt5jPR6QX5pnqM", "title": "",
		"images": {"fixed_height": {"width": "267", "height": "200"}}},
	{"type": "gif", "id": "bad/id", "title": "Nope", "images": {"fixed_height": {"width": "200", "height": "200"}}},
	{"type": "gif", "id": "NoImages", "title": "Nope"}
], "pagination": {"count": 4}, "meta": {"status": 200, "msg": "OK"}}"""
const FIXTURE: String = "res://tests/fixtures/gif/three_frames.gif"
const TEST_GIF_URL: String = "https://media.giphy.com/media/GutTestGif1/200.gif"


func before_all() -> void:
	TemplateImageCache.offline = true


func after_all() -> void:
	TemplateImageCache.offline = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TemplateImageCache.cache_path(TEST_GIF_URL)))


func _library_with(entries: Array[Dictionary]) -> MemeTemplateLibrary:
	var library := MemeTemplateLibrary.from_json('{"templates": [{"id": "host_grin"}]}')
	library.set_online(entries)
	return library


# --- GIPHY catalogue ----------------------------------------------------------------------

func test_parses_search_results() -> void:
	var entries: Array[Dictionary] = GiphyCatalogue.parse_response(SEARCH)
	assert_eq(entries.size(), 2)
	var first: Dictionary = entries[0]
	assert_eq(first["id"], "giphy-3o7TKSjRrfIPjeiVyM")
	assert_eq(first["name"], "Happy Dance")
	assert_eq(first["width"], 356)
	assert_eq(first["height"], 200)
	assert_true(first["animated"])
	assert_eq(first["url"], "https://media.giphy.com/media/3o7TKSjRrfIPjeiVyM/200.gif", "rebuilt from the id, no tracking query")
	assert_eq(first["still_url"], "https://media.giphy.com/media/3o7TKSjRrfIPjeiVyM/200_s.gif")
	assert_eq(entries[1]["name"], "GIF", "an empty title gets a name")


func test_broken_answers_give_nothing() -> void:
	assert_eq(GiphyCatalogue.parse_response("").size(), 0)
	assert_eq(GiphyCatalogue.parse_response('{"meta": {"status": 401, "msg": "Unauthorized"}}').size(), 0)
	assert_eq(GiphyCatalogue.parse_response('{"data": "x"}').size(), 0)


func test_host_cannot_point_clients_elsewhere() -> void:
	var clean: Dictionary = GiphyCatalogue.sanitize_entry({
		"id": "giphy-abc123", "name": "x", "width": 200, "height": 200,
		"url": "https://evil.example/steal.gif", "still_url": "file:///C:/secret",
	})
	assert_eq(clean["url"], "https://media.giphy.com/media/abc123/200.gif")
	assert_eq(clean["still_url"], "https://media.giphy.com/media/abc123/200_s.gif")
	assert_eq(GiphyCatalogue.sanitize_entry({"id": "giphy-a.b", "width": 200, "height": 200}), {})
	assert_eq(GiphyCatalogue.sanitize_entry({"id": "giphy-ok", "width": 5000, "height": 200}), {})


func test_search_url_encodes_the_query_and_caps_the_limit() -> void:
	var url: String = GiphyCatalogue.search_url("KEY", "so tired", 500)
	assert_true(url.begins_with(GiphyCatalogue.SEARCH_URL + "?api_key=KEY&q=so%20tired&limit=50&rating=pg-13"))


# --- Combined catalogue -------------------------------------------------------------------

func test_catalogue_dispatches_by_provider() -> void:
	var entries: Array[Dictionary] = TemplateCatalogue.sanitize([
		{"id": "imgflip-1", "name": "Still", "url": "https://i.imgflip.com/aaa.jpg", "width": 400, "height": 300},
		{"id": "giphy-Abc1", "name": "Gif", "width": 300, "height": 200},
		{"id": "giphy-Abc1", "name": "Duplicate", "width": 300, "height": 200},
		{"id": "tenor-1", "name": "Unknown provider", "width": 300, "height": 200},
		{"id": "host_grin", "name": "Not online", "width": 300, "height": 200},
		42,
	])
	assert_eq(entries.size(), 2)
	assert_false(entries[0].get("animated", false))
	assert_true(entries[1]["animated"])
	assert_eq(TemplateCatalogue.sanitize("nope").size(), 0)


func test_catalogue_survives_a_json_round_trip() -> void:
	var entries: Array[Dictionary] = GiphyCatalogue.parse_response(SEARCH)
	var json := JSON.new()
	json.parse(JSON.stringify(entries))  # numbers come back as floats, like the saved file
	assert_eq(TemplateCatalogue.sanitize(json.data), entries)


# --- Library, cache and renderer ----------------------------------------------------------

func test_library_knows_which_templates_move() -> void:
	var library: MemeTemplateLibrary = _library_with(GiphyCatalogue.parse_response(SEARCH))
	assert_true(library.has_animated())
	assert_true(library.is_animated("giphy-3o7TKSjRrfIPjeiVyM"))
	assert_false(library.is_animated("host_grin"))
	assert_null(library.animation("host_grin"))
	assert_almost_eq(library.aspect("giphy-3o7TKSjRrfIPjeiVyM"), 356.0 / 200.0, 0.0001)
	var stills := _library_with(ImgflipCatalogue.parse_response('{"success": true, "data": {"memes": [{"id": "1", "name": "a", "url": "https://i.imgflip.com/a.jpg", "width": 100, "height": 100}]}}'))
	assert_false(stills.has_animated())


func test_animation_timing_loops() -> void:
	var gif := GifDecoder.decode(FileAccess.get_file_as_bytes(FIXTURE))
	var animation := AnimatedTemplate.from_frames(gif.frames, gif.delays)
	assert_eq(animation.frame_count(), 3)
	assert_almost_eq(animation.duration, 0.35, 0.001)
	assert_eq(animation.frame_index_at(0.0), 0)
	assert_eq(animation.frame_index_at(0.15), 1)
	assert_eq(animation.frame_index_at(0.32), 2)
	assert_eq(animation.frame_index_at(0.36), 0, "loops")
	assert_eq(AnimatedTemplate.new().frame_index_at(1.0), 0)
	assert_null(AnimatedTemplate.new().frame_at(1.0))


func test_cached_gif_loads_as_still_and_animation() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TemplateImageCache.CACHE_DIR))
	var file := FileAccess.open(TemplateImageCache.cache_path(TEST_GIF_URL), FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE))
	file.close()
	var entry: Dictionary = {"id": "giphy-GutTestGif1", "name": "t", "url": TEST_GIF_URL,
		"still_url": TEST_GIF_URL, "width": 8, "height": 6, "animated": true}
	var library: MemeTemplateLibrary = _library_with([entry] as Array[Dictionary])
	assert_null(library.animation("giphy-GutTestGif1"), "decoded off the main thread")
	await wait_for_signal(library.image_updated, 5.0)
	var animation: AnimatedTemplate = library.animation("giphy-GutTestGif1")
	if animation == null:  # the still may have arrived first
		await wait_for_signal(library.image_updated, 5.0)
		animation = library.animation("giphy-GutTestGif1")
	assert_not_null(animation)
	assert_eq(animation.frame_count(), 3)

	var renderer := MemeRenderer.new()
	renderer.library = library
	renderer.size = Vector2(160, 120)
	add_child_autofree(renderer)
	renderer.set_meme(MemeSpec.new("giphy-GutTestGif1", "a", "b"))
	await wait_frames(2)
	assert_true(renderer.is_processing(), "an animated meme keeps redrawing")
	renderer.set_meme(MemeSpec.new("host_grin", "a", "b"))
	await wait_frames(2)
	assert_false(renderer.is_processing(), "a still meme does not")


func test_stills_decode_from_gif_first_frames() -> void:
	var image: Image = TemplateImageCache.decode(FileAccess.get_file_as_bytes(FIXTURE))
	assert_not_null(image)
	assert_eq(image.get_size(), Vector2i(8, 6))
	assert_eq(image.get_pixel(0, 0).to_rgba32(), Color.RED.to_rgba32())
