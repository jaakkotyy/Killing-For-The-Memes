class_name TemplateImageCache
extends Node
## Downloads online template images once and keeps them in user://template_cache/, so a
## template is fetched from the internet only the first time any game shows it.
##
## Stills (JPG, PNG, or a GIF's first frame) are kept in memory once loaded. Animations
## (whole GIFs) are big when decoded, so only the last MAX_ANIMATIONS stay in memory; the
## file stays on disk. Every client downloads images itself, straight from the image host,
## so images never travel through the game's own network. Only URLs that a catalogue class
## accepts get here. The shared instance lives under the scene tree's root.

signal loaded(url: String, texture: Texture2D)
signal failed(url: String)
signal animation_loaded(url: String, animation: AnimatedTemplate)
signal animation_failed(url: String)

const CACHE_DIR: String = "user://template_cache/"
const MAX_PARALLEL: int = 4
const TIMEOUT_SECONDS: float = 20.0
const MAX_BYTES: int = 8 * 1024 * 1024
## Bigger stills are scaled down; the meme is never shown larger than the wall TV.
const MAX_TEXTURE_SIDE: int = 1024
## Decoded animations kept in memory (a 200 px GIF is a few MB per second of animation).
const MAX_ANIMATIONS: int = 4

## Tests set this so nothing ever goes to the network; missing images then just fail.
static var offline: bool = false
static var _instance: TemplateImageCache

var _textures: Dictionary = {}  # url -> Texture2D
var _animations: Dictionary = {}  # url -> AnimatedTemplate
var _animation_order: Array[String] = []  # least recently used first
var _failed: Dictionary = {}  # job key -> true
var _pending: Dictionary = {}  # job key -> true while queued, downloading or decoding
var _queue: Array[String] = []  # job keys waiting for a download slot
var _active: int = 0


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


## Where [param url]'s file is cached on disk.
static func cache_path(url: String) -> String:
	return CACHE_DIR + url.md5_text() + "." + url.get_extension().to_lower()


## Decodes a still: JPG, PNG or the first frame of a GIF (whatever the extension claims),
## scaled down to MAX_TEXTURE_SIDE. Returns null for anything that isn't a sane image.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return null
	if GifDecoder.is_gif(bytes):
		var gif := GifDecoder.decode(bytes, 1)
		return gif.frames[0] if not gif.frames.is_empty() else null
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


## The still if it is ready. Otherwise starts loading it (from the disk cache, or else
## from the internet) and returns null; listen to [signal loaded] / [signal failed].
func get_texture(url: String) -> Texture2D:
	if _textures.has(url):
		return _textures[url]
	_request(_key(url, false))
	return null


## The whole animation of a GIF if it is decoded; otherwise starts loading it and returns
## null. Listen to [signal animation_loaded] / [signal animation_failed].
func get_animation(url: String) -> AnimatedTemplate:
	if _animations.has(url):
		_animation_order.erase(url)
		_animation_order.append(url)
		return _animations[url]
	_request(_key(url, true))
	return null


func has_failed(url: String) -> bool:
	return _failed.has(_key(url, false))


func animation_failed_for(url: String) -> bool:
	return _failed.has(_key(url, true))


func _process(_delta: float) -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		_download(_queue.pop_front())


static func _key(url: String, animated: bool) -> String:
	return ("anim|" if animated else "still|") + url


static func _url_of(key: String) -> String:
	return key.get_slice("|", 1)


func _request(key: String) -> void:
	if _failed.has(key) or _pending.has(key):
		return
	_pending[key] = true
	var url: String = _url_of(key)
	if FileAccess.file_exists(cache_path(url)):
		WorkerThreadPool.add_task(_decode_in_background.bind(key, PackedByteArray(), true))
	elif offline:
		_pending.erase(key)
		_failed[key] = true
	else:
		_queue.append(key)


func _download(key: String) -> void:
	_active += 1
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.body_size_limit = MAX_BYTES
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(key, request))
	if request.request(_url_of(key)) != OK:
		_on_request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), key, request)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		key: String, request: HTTPRequest) -> void:
	_active -= 1
	request.queue_free()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	WorkerThreadPool.add_task(_decode_in_background.bind(key, body if ok else PackedByteArray(), false))


## Runs on a worker thread: decoding a big JPG, let alone a whole GIF, would stall frames.
func _decode_in_background(key: String, body: PackedByteArray, from_disk: bool) -> void:
	var url: String = _url_of(key)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(cache_path(url)) if from_disk else body
	if key.begins_with("anim|"):
		var gif: GifDecoder = GifDecoder.decode(bytes) if GifDecoder.is_gif(bytes) else null
		var good: bool = gif != null and not gif.frames.is_empty()
		if good and not from_disk:
			_save_cached(url, bytes)
		_on_animation_decoded.call_deferred(key, gif.frames if good else ([] as Array[Image]),
			gif.delays if good else PackedFloat32Array())
		return
	var image: Image = decode(bytes)
	if image != null and not from_disk:
		_save_cached(url, bytes)
	_on_still_decoded.call_deferred(key, image)


func _on_still_decoded(key: String, image: Image) -> void:
	_pending.erase(key)
	var url: String = _url_of(key)
	if image == null:
		print("[Templates] Could not load %s" % url)
		_failed[key] = true
		failed.emit(url)
		return
	var texture := ImageTexture.create_from_image(image)
	_textures[url] = texture
	loaded.emit(url, texture)


func _on_animation_decoded(key: String, frames: Array[Image], delays: PackedFloat32Array) -> void:
	_pending.erase(key)
	var url: String = _url_of(key)
	if frames.is_empty():
		print("[Templates] Could not load animation %s" % url)
		_failed[key] = true
		animation_failed.emit(url)
		return
	var animation: AnimatedTemplate = AnimatedTemplate.from_frames(frames, delays)
	_animations[url] = animation
	_animation_order.append(url)
	while _animation_order.size() > MAX_ANIMATIONS:
		_animations.erase(_animation_order.pop_front())
	animation_loaded.emit(url, animation)


## Worker thread. Each URL has its own file and is decoded once at a time, so writes never
## collide.
func _save_cached(url: String, body: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var file := FileAccess.open(cache_path(url), FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)
