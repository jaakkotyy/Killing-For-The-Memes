class_name OnlineTemplateSource
extends Node
## Fetches the popular-template catalogue from Imgflip on the host. If Imgflip can't be
## reached, it falls back to the catalogue saved by the last successful fetch, and then to
## nothing (our original templates still work).
##
## A provider is just "something that emits fetched(entries)", so swapping Imgflip for a
## licensed source later only touches this class and ImgflipCatalogue.

signal fetched(entries: Array[Dictionary])

## How many popular templates to offer. Every client downloads these images once.
const DEFAULT_LIMIT: int = 40
const TIMEOUT_SECONDS: float = 8.0
const CATALOGUE_CACHE: String = TemplateImageCache.CACHE_DIR + "imgflip_catalogue.json"

var limit: int = DEFAULT_LIMIT
var _request: HTTPRequest


func fetch() -> void:
	if _request != null:
		return
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT_SECONDS
	_request.body_size_limit = 1024 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	if _request.request(ImgflipCatalogue.API_URL) != OK:
		_done(PackedByteArray())


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_done(body if result == HTTPRequest.RESULT_SUCCESS and code == 200 else PackedByteArray())


func _done(body: PackedByteArray) -> void:
	_request.queue_free()
	_request = null
	var entries: Array[Dictionary] = ImgflipCatalogue.parse_response(body.get_string_from_utf8(), limit)
	if not entries.is_empty():
		_save(body)
		print("[Templates] %d popular templates from Imgflip." % entries.size())
	else:
		entries = load_cached(limit)
		print("[Templates] Imgflip unreachable; %d templates from the saved catalogue." % entries.size())
	fetched.emit(entries)


## The catalogue saved by the last successful fetch, or nothing.
static func load_cached(max_entries: int = DEFAULT_LIMIT) -> Array[Dictionary]:
	if not FileAccess.file_exists(CATALOGUE_CACHE):
		return []
	return ImgflipCatalogue.parse_response(FileAccess.get_file_as_string(CATALOGUE_CACHE), max_entries)


func _save(body: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TemplateImageCache.CACHE_DIR))
	var file := FileAccess.open(CATALOGUE_CACHE, FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)
