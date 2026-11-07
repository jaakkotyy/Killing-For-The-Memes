extends GutTest
## The newer template sources: Reddit through meme-api.com, Imgflip's HTML template and
## search pages, the host's template search and the templates it finds. No network.

const REDDIT: String = """{"count": 5, "memes": [
	{"title": "Me at 3am", "url": "https://i.redd.it/abc123xyz.jpg", "nsfw": false, "spoiler": false,
		"preview": ["https://preview.redd.it/abc123xyz.jpg?width=108&crop=smart&auto=webp&s=0123456789abcdef0123456789abcdef01234567",
			"https://preview.redd.it/abc123xyz.jpg?width=216&crop=smart&auto=webp&s=0123456789abcdef0123456789abcdef01234567"]},
	{"title": "Spicy", "url": "https://i.redd.it/nsfw1.png", "nsfw": true, "spoiler": false},
	{"title": "Moving", "url": "https://i.redd.it/gif1.gif", "nsfw": false, "spoiler": false},
	{"title": "Elsewhere", "url": "https://imgur.com/x.jpg", "nsfw": false, "spoiler": false},
	{"title": "Big PNG", "url": "https://i.redd.it/pngone.png", "nsfw": false, "spoiler": false,
		"preview": ["x", "https://evil.example/thumb.jpg"]}
]}"""

const HTML: String = """<div class="mt-box"><a href="/meme/Drake"><img class="shadow" style="width:150px;height:150px" alt="Drake Hotline Bling Meme Template" src="//i.imgflip.com/4/30b1gx.jpg"/></a></div>
<div class="mt-box"><img style="width:150px;height:113.5px" alt="Tom&#039;s &quot;Plan&quot; Template" src="//i.imgflip.com/4/1g8my4.jpg"/></div>
<div><img style="width:150px;height:150px" alt="Elsewhere" src="//evil.example/4/zzz.jpg"/></div>"""


# --- Reddit -------------------------------------------------------------------------------

func test_reddit_keeps_safe_stills_on_i_redd_it() -> void:
	var entries: Array[Dictionary] = RedditCatalogue.parse_response(REDDIT)
	assert_eq(entries.size(), 2, "no NSFW, no GIFs, nothing off i.redd.it")
	assert_eq(entries[0]["id"], "reddit-abc123xyz-jpg")
	assert_eq(entries[0]["name"], "Me at 3am")
	assert_eq(entries[0]["url"], "https://i.redd.it/abc123xyz.jpg")
	assert_true((entries[0]["thumb_url"] as String).contains("width=216"))
	assert_eq(entries[1]["id"], "reddit-pngone-png")
	assert_false(entries[1].has("thumb_url"), "a thumbnail off Reddit's previews is dropped")
	assert_eq(RedditCatalogue.parse_response("nope").size(), 0)
	assert_eq(RedditCatalogue.parse_response('{"memes": 3}').size(), 0)


func test_reddit_ids_name_their_image() -> void:
	assert_eq(RedditCatalogue.resolve("reddit-abc-jpeg")["url"], "https://i.redd.it/abc.jpeg")
	for bad: String in ["reddit-abc", "reddit-abc-gif", "reddit-a.b-jpg", "reddit--png", "imgflip-abc"]:
		assert_eq(RedditCatalogue.resolve(bad), {}, bad)
	var clean: Dictionary = TemplateCatalogue.sanitize_entry({"id": "reddit-abc-png", "url": "https://evil.example/x.png"})
	assert_eq(clean["url"], "https://i.redd.it/abc.png")
	assert_true(MemeSpec.is_valid_template_id(RedditCatalogue.id_for("a".repeat(24), "jpeg")), "the longest id fits")


func test_subreddit_queries() -> void:
	assert_eq(RedditCatalogue.subreddit_in("r/memes"), "memes")
	assert_eq(RedditCatalogue.subreddit_in(" /r/me_irl/ "), "me_irl")
	assert_eq(RedditCatalogue.subreddit_in("R/Dank"), "Dank")
	assert_eq(RedditCatalogue.subreddit_in("memes"), "")
	assert_eq(RedditCatalogue.subreddit_in("r/../etc"), "")
	assert_eq(RedditCatalogue.subreddit_in("r/a"), "", "too short")
	assert_eq(RedditCatalogue.api_url("memes", 500), "https://meme-api.com/gimme/memes/50")


# --- Imgflip pages ------------------------------------------------------------------------

func test_imgflip_html_pages_parse_into_entries() -> void:
	var entries: Array[Dictionary] = ImgflipCatalogue.parse_html(HTML)
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["id"], "imgflip-30b1gx")
	assert_eq(entries[0]["name"], "Drake Hotline Bling")
	assert_eq(entries[1]["name"], "Tom's \"Plan\"")
	assert_almost_eq(float(entries[1]["width"]) / float(entries[1]["height"]), 150.0 / 113.5, 0.01)
	assert_eq(ImgflipCatalogue.parse_html("").size(), 0)
	assert_eq(ImgflipCatalogue.search_url("so tired"), "https://imgflip.com/memesearch?q=so%20tired")
	assert_eq(ImgflipCatalogue.templates_url(0), "https://imgflip.com/memetemplates?page=1")


# --- Search -------------------------------------------------------------------------------

func test_queries_are_cleaned_and_capped() -> void:
	assert_eq(TemplateSearch.clean_query("  sad\tcat \n"), "sad cat")
	assert_eq(TemplateSearch.clean_query(42), "")
	assert_eq(TemplateSearch.clean_query("x".repeat(500)).length(), TemplateSearch.MAX_QUERY_LENGTH)


func test_results_take_turns() -> void:
	var a: Array[Dictionary] = [{"id": "a1"}, {"id": "a2"}, {"id": "a3"}]
	var b: Array[Dictionary] = [{"id": "b1"}]
	var ids: Array[String] = []
	for entry: Dictionary in TemplateSearch.interleave(a, b, 3):
		ids.append(entry["id"])
	assert_eq(ids, ["a1", "b1", "a2"] as Array[String])


func test_a_refused_search_still_answers() -> void:
	var search := TemplateSearch.new()
	add_child_autofree(search)
	watch_signals(search)
	search.request(5, "   ")
	assert_signal_emitted_with_parameters(search, "finished", [5, "", [] as Array[Dictionary]])


func test_found_templates_are_known_but_not_listed() -> void:
	var library := MemeTemplateLibrary.from_json('{"templates": [{"id": "crt_static"}]}')
	watch_signals(library)
	var entries: Array[Dictionary] = ImgflipCatalogue.parse_html(HTML)
	entries.append({"id": "crt_static"})  # an original is never "found"
	var found: PackedStringArray = library.add_found(entries)
	assert_eq(found, PackedStringArray(["imgflip-30b1gx", "imgflip-1g8my4"]))
	assert_eq(library.display_name("imgflip-30b1gx"), "Drake Hotline Bling")
	assert_false(library.has("imgflip-30b1gx"))
	assert_eq(library.ids(), PackedStringArray(["crt_static"]))
	assert_signal_not_emitted(library, "templates_changed")
