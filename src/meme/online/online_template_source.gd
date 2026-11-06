class_name OnlineTemplateSource
extends Node
## Fetches the online template catalogue on the host: popular stills from Imgflip, then
## reaction GIFs from GIPHY when there is an API key. Whatever arrives is saved; if
## nothing can be reached, the catalogue saved last time is used, and then nothing (our
## original templates still work).
##
## A provider is just a URL plus a parser that returns validated entries, so swapping one
## for a licensed source only touches this class and that provider's catalogue class.

signal fetched(entries: Array[Dictionary])

## How many popular stills to offer. Every client downloads these images once.
const DEFAULT_LIMIT: int = 40
const DEFAULT_GIF_LIMIT: int = 25
const TIMEOUT_SECONDS: float = 8.0
const CATALOGUE_CACHE: String = TemplateImageCache.CACHE_DIR + "catalogue.json"

var limit: int = DEFAULT_LIMIT
var gif_limit: int = DEFAULT_GIF_LIMIT
## The host's GIPHY key; empty means no GIFs. Never logged.
var giphy_api_key: String = ""
var gif_query: String = GiphyCatalogue.DEFAULT_QUERY

var _busy: bool = false


func fetch() -> void:
	if _busy:
		return
	_busy = true
	var saved: Array[Dictionary] = load_cached()
	var entries: Array[Dictionary] = []
	var stills: Array[Dictionary] = ImgflipCatalogue.parse_response(await _fetch_text(ImgflipCatalogue.API_URL), limit)
	if stills.is_empty():
		stills = _from_provider(saved, ImgflipCatalogue.ID_PREFIX)
		print("[Templates] Imgflip unreachable; %d saved popular templates." % stills.size())
	else:
		print("[Templates] %d popular templates from Imgflip." % stills.size())
	entries.append_array(stills)
	if not giphy_api_key.is_empty():
		var gifs: Array[Dictionary] = GiphyCatalogue.parse_response(
			await _fetch_text(GiphyCatalogue.search_url(giphy_api_key, gif_query, gif_limit)), gif_limit)
		if gifs.is_empty():
			gifs = _from_provider(saved, GiphyCatalogue.ID_PREFIX)
			print("[Templates] GIPHY unreachable (or the key was refused); %d saved GIF templates." % gifs.size())
		else:
			print("[Templates] %d GIF templates from GIPHY." % gifs.size())
		entries.append_array(gifs)
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


static func _from_provider(entries: Array[Dictionary], prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if (entry["id"] as String).begins_with(prefix):
			result.append(entry)
	return result


## The body of a GET, or "" on any failure.
func _fetch_text(url: String) -> String:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = 2 * 1024 * 1024
	add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return ""
	var answer: Array = await request.request_completed
	request.queue_free()
	var ok: bool = answer[0] == HTTPRequest.RESULT_SUCCESS and answer[1] == 200
	return (answer[3] as PackedByteArray).get_string_from_utf8() if ok else ""


func _save(entries: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TemplateImageCache.CACHE_DIR))
	var file := FileAccess.open(CATALOGUE_CACHE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries))
