class_name OnlineTemplateSource
extends Node
## Fetches the online template catalogue on the host, from every provider at once:
## Imgflip's popular list plus two random pages of its deeper catalogue, fresh memes from
## a few subreddits, and (with a GIPHY key) GIFs for a couple of random moods. The mix is
## shuffled, so every game offers something different. Whatever arrives is saved; a
## provider that can't be reached falls back to its part of the catalogue saved last time
## (our original templates always work).
##
## A provider is a URL plus a parser that returns validated entries; adding one only
## touches this class and that provider's catalogue class.

signal fetched(entries: Array[Dictionary])

## Imgflip's template pages go this deep (40 templates a page) while still being memes
## people recognise.
const IMGFLIP_PAGES: Vector2i = Vector2i(2, 30)
const IMGFLIP_EXTRA_PAGES: int = 2
const REDDIT_PER_SUBREDDIT: int = 20
const GIPHY_QUERIES: int = 2
const GIPHY_PER_QUERY: int = 15
## Not past the first few hundred results: deeper ones are rarely good reactions.
const GIPHY_MAX_OFFSET: int = 200
## Version 2: ids name image files (catalogues saved before that are ignored).
const CATALOGUE_CACHE: String = TemplateImageCache.CACHE_DIR + "catalogue_v2.json"

## The host's GIPHY key; empty means no GIFs. Never logged.
var giphy_api_key: String = ""
var subreddits: PackedStringArray = RedditCatalogue.DEFAULT_SUBREDDITS
## Tests seed this for a repeatable mix.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _busy: bool = false


func _init() -> void:
	rng.randomize()


func fetch() -> void:
	if _busy:
		return
	_busy = true
	var urls: PackedStringArray = [ImgflipCatalogue.API_URL]
	for page: int in _distinct(IMGFLIP_EXTRA_PAGES, IMGFLIP_PAGES.x, IMGFLIP_PAGES.y):
		urls.append(ImgflipCatalogue.templates_url(page))
	var reddit_from: int = urls.size()
	for subreddit: String in subreddits:
		urls.append(RedditCatalogue.api_url(subreddit, REDDIT_PER_SUBREDDIT))
	var giphy_from: int = urls.size()
	if not giphy_api_key.is_empty():
		for index: int in _distinct(GIPHY_QUERIES, 0, GiphyCatalogue.CATALOGUE_QUERIES.size() - 1):
			urls.append(GiphyCatalogue.search_url(giphy_api_key, GiphyCatalogue.CATALOGUE_QUERIES[index],
				GIPHY_PER_QUERY, rng.randi_range(0, GIPHY_MAX_OFFSET)))
	var bodies: PackedStringArray = await HttpText.fetch_all(self, urls)

	var stills: Array[Dictionary] = ImgflipCatalogue.parse_response(bodies[0])
	for i: int in range(1, reddit_from):
		stills.append_array(ImgflipCatalogue.parse_html(bodies[i]))
	var reddit: Array[Dictionary] = []
	for i: int in range(reddit_from, giphy_from):
		reddit.append_array(RedditCatalogue.parse_response(bodies[i]))
	var gifs: Array[Dictionary] = []
	for i: int in range(giphy_from, urls.size()):
		gifs.append_array(GiphyCatalogue.parse_response(bodies[i]))

	var saved: Array[Dictionary] = load_cached()
	var entries: Array[Dictionary] = []
	entries.append_array(_or_saved(stills, saved, ImgflipCatalogue.ID_PREFIX, "Imgflip"))
	entries.append_array(_or_saved(reddit, saved, RedditCatalogue.ID_PREFIX, "Reddit"))
	if not giphy_api_key.is_empty():
		entries.append_array(_or_saved(gifs, saved, GiphyCatalogue.ID_PREFIX, "GIPHY"))
	entries = TemplateCatalogue.sanitize(entries)  # drops duplicates across pages
	_shuffle(entries)
	if not entries.is_empty():
		_save(entries)
	_busy = false
	fetched.emit(entries)


## The catalogue saved by the last successful fetch, or nothing.
static func load_cached() -> Array[Dictionary]:
	if not FileAccess.file_exists(CATALOGUE_CACHE):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CATALOGUE_CACHE)) != OK:
		return []
	return TemplateCatalogue.sanitize(json.data)


func _or_saved(fresh: Array[Dictionary], saved: Array[Dictionary], prefix: String, provider: String) -> Array[Dictionary]:
	if not fresh.is_empty():
		print("[Templates] %d templates from %s." % [fresh.size(), provider])
		return fresh
	var result: Array[Dictionary] = []
	for entry: Dictionary in saved:
		if (entry["id"] as String).begins_with(prefix):
			result.append(entry)
	print("[Templates] %s unreachable; %d saved templates." % [provider, result.size()])
	return result


## [param count] different numbers between [param low] and [param high] (inclusive).
func _distinct(count: int, low: int, high: int) -> Array[int]:
	var pool: Array[int] = []
	for n: int in range(low, high + 1):
		pool.append(n)
	_shuffle(pool)
	return pool.slice(0, mini(count, pool.size()))


func _shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


func _save(entries: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TemplateImageCache.CACHE_DIR))
	var file := FileAccess.open(CATALOGUE_CACHE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries))
