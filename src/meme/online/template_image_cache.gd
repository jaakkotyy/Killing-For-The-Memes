class_name TemplateImageCache
extends Node
## Downloads online template images once and keeps them in user://template_cache/, so a
## template is fetched from the internet only the first time any game shows it.
##
## Every client downloads images itself, straight from the image host, so images never
## travel through the game's own network. Only URLs that ImgflipCatalogue accepts get
## here. The shared instance lives under the scene tree's root (see get_instance()).

signal loaded(url: String, texture: Texture2D)
signal failed(url: String)

const CACHE_DIR: String = "user://template_cache/"
const MAX_PARALLEL: int = 4
const TIMEOUT_SECONDS: float = 20.0
const MAX_BYTES: int = 4 * 1024 * 1024
## Bigger images are scaled down; the meme is never shown larger than the wall TV.
const MAX_TEXTURE_SIDE: int = 1024

## Tests set this so nothing ever goes to the network; missing images then just fail.
static var offline: bool = false
static var _instance: TemplateImageCache

var _textures: Dictionary = {}  # url -> Texture2D
var _failed: Dictionary = {}  # url -> true
var _queue: Array[String] = []
var _active: Dictionary = {}  # url -> HTTPRequest
var _pending: Dictionary = {}  # url -> true while queued, downloading or decoding


## The shared cache. It adds itself to the tree on the next idle frame and starts its
## downloads from there, so it can be asked for images from anywhere, even from _ready().
static func get_instance() -> TemplateImageCache:
	if _instance == null or not is_instance_valid(_instance):
		_instance = TemplateImageCache.new()
		_instance.name = "TemplateImageCache"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child.call_deferred(_instance)
	return _instance


## Where [param url]'s image is cached on disk.
static func cache_path(url: String) -> String:
	return CACHE_DIR + url.md5_text() + "." + url.get_extension().to_lower()


## Decodes a downloaded JPG or PNG (whatever the extension claims) and scales it down to
## MAX_TEXTURE_SIDE. Returns null for anything that isn't a sane image.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return null
	# Check the signature first: Godot's decoders log engine errors on junk.
	var is_png: bool = bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47
	var is_jpg: bool = bytes.size() >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
	if not is_png and not is_jpg:
		return null
	var image := Image.new()
	var err: Error = image.load_png_from_buffer(bytes) if is_png else image.load_jpg_from_buffer(bytes)
	if err != OK or image.is_empty():
		return null
	var longest: int = maxi(image.get_width(), image.get_height())
	if longest > ImgflipCatalogue.MAX_SIDE:
		return null
	if longest > MAX_TEXTURE_SIDE:
		var scale: float = float(MAX_TEXTURE_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return image


## The image if it is ready. Otherwise starts loading it (from the disk cache, or else from
## the internet) and returns null; listen to [signal loaded] / [signal failed].
func get_texture(url: String) -> Texture2D:
	if _textures.has(url):
		return _textures[url]
	if _failed.has(url) or _pending.has(url):
		return null
	_pending[url] = true
	if FileAccess.file_exists(cache_path(url)):
		WorkerThreadPool.add_task(_decode_in_background.bind(url, PackedByteArray(), true))
	elif offline:
		_pending.erase(url)
		_failed[url] = true
	else:
		_queue.append(url)
	return null


func has_failed(url: String) -> bool:
	return _failed.has(url)


func _process(_delta: float) -> void:
	while _active.size() < MAX_PARALLEL and not _queue.is_empty():
		_start(_queue.pop_front())


func _start(url: String) -> void:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = MAX_BYTES
	add_child(request)
	_active[url] = request
	request.request_completed.connect(_on_request_completed.bind(url, request))
	if request.request(url) != OK:
		_on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), url, request)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		url: String, request: HTTPRequest) -> void:
	_active.erase(url)
	request.queue_free()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	WorkerThreadPool.add_task(_decode_in_background.bind(url, body if ok else PackedByteArray(), false))


## Runs on a worker thread: decoding and scaling a big JPG would stall a frame.
func _decode_in_background(url: String, body: PackedByteArray, from_disk: bool) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(cache_path(url)) if from_disk else body
	var image: Image = decode(bytes)
	if image != null and not from_disk:
		_save_cached(url, bytes)
	_on_decoded.call_deferred(url, image)


func _on_decoded(url: String, image: Image) -> void:
	_pending.erase(url)
	if image == null:
		print("[Templates] Could not load %s" % url)
		_failed[url] = true
		failed.emit(url)
		return
	var texture := ImageTexture.create_from_image(image)
	_textures[url] = texture
	loaded.emit(url, texture)


## Worker thread. Each URL has its own file and is decoded once, so writes never collide.
func _save_cached(url: String, body: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var file := FileAccess.open(cache_path(url), FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)
