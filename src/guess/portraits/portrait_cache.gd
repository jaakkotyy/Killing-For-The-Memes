class_name PortraitCache
extends Node
## Downloads identity portraits (Wikimedia Commons thumbnails, Portrait.url_for) once and
## keeps them in user://portrait_cache/, so a portrait comes from the internet only the
## first time any game shows it. Loaded textures stay in memory. Every client downloads
## pictures itself, straight from Commons, so pictures never travel through the game's
## own network. The shared instance lives under the scene tree's root.

signal loaded(url: String, texture: Texture2D)
signal failed(url: String)

const CACHE_DIR: String = "user://portrait_cache/"
## Wikimedia's User-Agent policy wants a way to reach whoever runs the client; without
## it, Commons answers 429 to new thumbnails. The project's public repository is that contact.
const USER_AGENT: String = "KillingForTheMemes/0.1 (https://github.com/jaakkotyy/Killing-For-The-Memes) Godot/4.7"
const MAX_PARALLEL: int = 4
const TIMEOUT_SECONDS: float = 20.0
const MAX_BYTES: int = 4 * 1024 * 1024
## Portraits are thumbnails; anything much bigger is not what we asked for.
const MAX_SIDE: int = 2048
## "Too many requests" / "busy" answers are retried this often, waiting longer each time
## (or as long as the server's Retry-After says). Wikimedia answers 429 while it renders a
## thumbnail nobody asked for lately, and has it ready a few seconds later.
const MAX_RETRIES: int = 3
const RETRY_BASE_SECONDS: float = 4.0
const RETRY_MAX_SECONDS: float = 60.0

## Tests set this so nothing ever goes to the network; missing pictures then just fail.
static var offline: bool = false
static var _instance: PortraitCache

var _textures: Dictionary = {}  # url -> Texture2D
var _failed: Dictionary = {}  # url -> true
var _pending: Dictionary = {}  # url -> true while queued, downloading or decoding
var _queue: Array[String] = []  # urls waiting for a download slot
var _active: int = 0
var _retries: Dictionary = {}  # url -> retries so far


## The shared cache. It adds itself to the tree on the next idle frame and starts its
## downloads from there, so it can be asked for pictures from anywhere, even from _ready().
static func get_instance() -> PortraitCache:
	if _instance == null or not is_instance_valid(_instance):
		_instance = PortraitCache.new()
		_instance.name = "PortraitCache"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(_instance)
	return _instance


## Where [param url]'s file is cached on disk.
static func cache_path(url: String) -> String:
	return CACHE_DIR + url.md5_text() + "." + url.get_slice("?", 0).get_extension().to_lower()


## Decodes a JPG, PNG or WebP (whatever the extension claims). Returns null for anything
## that isn't a sane image.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return null
	# Check the signature first: Godot's decoders log engine errors on junk.
	var is_png: bool = bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47
	var is_jpg: bool = bytes.size() >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
	var is_webp: bool = bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
		and bytes.slice(8, 12).get_string_from_ascii() == "WEBP"
	if not is_png and not is_jpg and not is_webp:
		return null
	var image := Image.new()
	var err: Error
	if is_png:
		err = image.load_png_from_buffer(bytes)
	elif is_jpg:
		err = image.load_jpg_from_buffer(bytes)
	else:
		err = image.load_webp_from_buffer(bytes)
	if err != OK or image.is_empty() or maxi(image.get_width(), image.get_height()) > MAX_SIDE:
		return null
	return image


## The picture if it is ready. Otherwise starts loading it (from the disk cache, or else
## from the internet) and returns null; listen to [signal loaded] / [signal failed].
func get_texture(url: String) -> Texture2D:
	if _textures.has(url):
		return _textures[url]
	_request(url)
	return null


func has_failed(url: String) -> bool:
	return _failed.has(url)


func _process(_delta: float) -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		_download(_queue.pop_front())


func _request(url: String) -> void:
	if _failed.has(url) or _pending.has(url):
		return
	_pending[url] = true
	if FileAccess.file_exists(cache_path(url)):
		WorkerThreadPool.add_task(_decode_in_background.bind(url, PackedByteArray(), true))
	elif offline:
		_pending.erase(url)
		_failed[url] = true
	else:
		_queue.append(url)


func _download(url: String) -> void:
	_active += 1
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = MAX_BYTES
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(url, request))
	if request.request(url, PackedStringArray(["User-Agent: " + USER_AGENT])) != OK:
		_on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), url, request)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray,
		url: String, request: HTTPRequest) -> void:
	_active -= 1
	request.queue_free()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	if (code == 429 or code == 503) and int(_retries.get(url, 0)) < MAX_RETRIES:
		_retry_later(url, headers)
		return
	if not ok:
		print("[Portraits] Download failed (result %d, HTTP %d): %s" % [result, code, url])
	WorkerThreadPool.add_task(_decode_in_background.bind(url, body if ok else PackedByteArray(), false))


## Puts [param url] back in the queue after the server's Retry-After, or a growing wait.
func _retry_later(url: String, headers: PackedStringArray) -> void:
	var tries: int = int(_retries.get(url, 0)) + 1
	_retries[url] = tries
	var wait: float = RETRY_BASE_SECONDS * pow(2.0, tries - 1)
	for header: String in headers:
		if header.to_lower().begins_with("retry-after:"):
			var value: String = header.get_slice(":", 1).strip_edges()
			if value.is_valid_int():
				wait = float(value.to_int())
	wait = clampf(wait, 1.0, RETRY_MAX_SECONDS)
	print("[Portraits] Busy, retrying in %.0f s: %s" % [wait, url])
	get_tree().create_timer(wait).timeout.connect(func() -> void: _queue.append(url))


## Runs on a worker thread, so decoding never stalls a frame.
func _decode_in_background(url: String, body: PackedByteArray, from_disk: bool) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(cache_path(url)) if from_disk else body
	var image: Image = decode(bytes)
	if image != null and not from_disk:
		_save_cached(url, bytes)
	_on_decoded.call_deferred(url, image)


func _on_decoded(url: String, image: Image) -> void:
	_pending.erase(url)
	if image == null:
		print("[Portraits] Could not load %s" % url)
		_failed[url] = true
		failed.emit(url)
		return
	var texture := ImageTexture.create_from_image(image)
	_textures[url] = texture
	loaded.emit(url, texture)


## Worker thread. Each URL has its own file and is decoded once at a time, so writes never
## collide.
func _save_cached(url: String, body: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var file := FileAccess.open(cache_path(url), FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)
