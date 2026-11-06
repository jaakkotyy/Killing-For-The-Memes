class_name GifDecoder
extends RefCounted
## Decodes GIF87a/GIF89a files into fully composited RGBA frames. Godot has no GIF loader,
## and GIF templates (GIPHY) need one.
##
## Handles global and local colour tables, transparency, the disposal methods (none, keep,
## restore to background = transparent, restore to previous), interlacing and frames
## smaller than the screen. Pure and node-free; it is slow-ish GDScript, so call it from a
## worker thread (TemplateImageCache does).
##
## Untrusted input: every size is bounded and broken data ends the decode with the frames
## read so far instead of crashing.

const MAX_SIDE: int = 1024
## Stop adding frames once this many pixels have been decoded (memory and time bound).
const MAX_TOTAL_PIXELS: int = 16_000_000
const MAX_FRAMES: int = 200
## Browsers play delays under 20 ms at 100 ms; so do we.
const MIN_DELAY: float = 0.02
const DEFAULT_DELAY: float = 0.1
const _INTERLACE_STARTS: Array[int] = [0, 4, 2, 1]
const _INTERLACE_STEPS: Array[int] = [8, 8, 4, 2]

var width: int = 0
var height: int = 0
var frames: Array[Image] = []
## Seconds each frame stays on screen.
var delays: PackedFloat32Array = []
## Why decoding stopped early or failed ("" when the whole file was read).
var error: String = ""

var _bytes: PackedByteArray
var _pos: int = 0


## Decodes [param bytes]. Check frames.is_empty() (and error) for failure.
## [param max_frames] 1 reads just the first frame, e.g. for a thumbnail.
static func decode(bytes: PackedByteArray, max_frames: int = MAX_FRAMES) -> GifDecoder:
	var gif := GifDecoder.new()
	gif._bytes = bytes
	gif._run(clampi(max_frames, 1, MAX_FRAMES))
	gif._bytes = PackedByteArray()
	return gif


static func is_gif(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 6 and bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46 \
		and bytes[3] == 0x38 and (bytes[4] == 0x37 or bytes[4] == 0x39) and bytes[5] == 0x61


func total_duration() -> float:
	var total: float = 0.0
	for delay: float in delays:
		total += delay
	return total


func _run(max_frames: int) -> void:
	if not is_gif(_bytes) or _bytes.size() < 13:
		error = "not a GIF"
		return
	width = _u16(6)
	height = _u16(8)
	if width <= 0 or height <= 0 or width > MAX_SIDE or height > MAX_SIDE:
		error = "bad size %dx%d" % [width, height]
		return
	var packed: int = _bytes[10]
	_pos = 13
	var global_palette := PackedByteArray()
	if packed & 0x80:
		global_palette = _read_palette(packed & 7)
		if global_palette.is_empty():
			return
	var canvas := PackedByteArray()
	canvas.resize(width * height * 4)
	canvas.fill(0)
	var pixels_decoded: int = 0
	# Graphic control of the next image.
	var disposal: int = 0
	var delay: float = DEFAULT_DELAY
	var transparent_index: int = -1
	# What to undo before drawing the next frame.
	var undo_disposal: int = 0
	var undo_rect := Rect2i()
	var saved_canvas := PackedByteArray()

	while _pos < _bytes.size() and frames.size() < max_frames:
		var block: int = _bytes[_pos]
		_pos += 1
		if block == 0x3B:  # trailer
			return
		if block == 0x21:  # extension
			if _pos >= _bytes.size():
				error = "truncated extension"
				return
			var label: int = _bytes[_pos]
			_pos += 1
			if label == 0xF9 and _pos + 5 <= _bytes.size() and _bytes[_pos] == 4:
				var gce: int = _bytes[_pos + 1]
				disposal = (gce >> 2) & 7
				var centiseconds: int = _u16(_pos + 2)
				delay = centiseconds / 100.0 if centiseconds / 100.0 >= MIN_DELAY else DEFAULT_DELAY
				transparent_index = _bytes[_pos + 4] if gce & 1 else -1
			if not _skip_sub_blocks():
				return
			continue
		if block != 0x2C:
			error = "unknown block 0x%02x" % block
			return
		# Image descriptor.
		if _pos + 9 > _bytes.size():
			error = "truncated image descriptor"
			return
		var rect := Rect2i(_u16(_pos), _u16(_pos + 2), _u16(_pos + 4), _u16(_pos + 6))
		var image_packed: int = _bytes[_pos + 8]
		_pos += 9
		var palette: PackedByteArray = global_palette
		if image_packed & 0x80:
			palette = _read_palette(image_packed & 7)
			if palette.is_empty():
				return
		if _pos >= _bytes.size():
			error = "truncated image data"
			return
		var min_code_size: int = _bytes[_pos]
		_pos += 1
		var data: PackedByteArray = _read_sub_blocks()
		if min_code_size < 2 or min_code_size > 8 or rect.size.x <= 0 or rect.size.y <= 0 \
				or rect.size.x > MAX_SIDE or rect.size.y > MAX_SIDE or palette.is_empty():
			error = "bad image block"
			return
		pixels_decoded += width * height
		if pixels_decoded > MAX_TOTAL_PIXELS:
			error = "too many pixels"
			return

		# Undo the previous frame as its disposal asks.
		if undo_disposal == 2:
			_clear(canvas, undo_rect)
		elif undo_disposal == 3 and not saved_canvas.is_empty():
			canvas = saved_canvas
		saved_canvas = canvas.duplicate() if disposal == 3 else PackedByteArray()

		var indices: PackedByteArray = _lzw(data, min_code_size, rect.size.x * rect.size.y)
		_draw(canvas, rect, indices, palette, transparent_index, image_packed & 0x40 != 0)
		frames.append(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, canvas))
		delays.append(delay)
		undo_disposal = disposal
		undo_rect = rect
		disposal = 0
		delay = DEFAULT_DELAY
		transparent_index = -1


func _draw(canvas: PackedByteArray, rect: Rect2i, indices: PackedByteArray, palette: PackedByteArray,
		transparent_index: int, interlaced: bool) -> void:
	var colors: int = palette.size() / 3
	var w: int = rect.size.x
	var h: int = rect.size.y
	var x0: int = rect.position.x
	var y0: int = rect.position.y
	var x_end: int = mini(w, width - x0)
	var src_row: int = 0
	var passes: int = 4 if interlaced else 1
	for p: int in range(passes):
		var row: int = _INTERLACE_STARTS[p] if interlaced else 0
		var step: int = _INTERLACE_STEPS[p] if interlaced else 1
		while row < h:
			var y: int = y0 + row
			if y < height:
				var src: int = src_row * w
				var dst: int = (y * width + x0) * 4
				for x: int in range(x_end):
					var index: int = indices[src + x]
					if index != transparent_index and index < colors:
						var c: int = index * 3
						canvas[dst] = palette[c]
						canvas[dst + 1] = palette[c + 1]
						canvas[dst + 2] = palette[c + 2]
						canvas[dst + 3] = 255
					dst += 4
			src_row += 1
			row += step


func _clear(canvas: PackedByteArray, rect: Rect2i) -> void:
	var x_end: int = mini(rect.end.x, width)
	var y_end: int = mini(rect.end.y, height)
	for y: int in range(rect.position.y, y_end):
		var start: int = (y * width + rect.position.x) * 4
		for i: int in range(start, start + (x_end - rect.position.x) * 4):
			canvas[i] = 0


## GIF's variable-width LZW. Returns exactly [param pixel_count] colour indices (zeros
## where the data ends early).
func _lzw(data: PackedByteArray, min_size: int, pixel_count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pixel_count)
	out.fill(0)
	var clear: int = 1 << min_size
	var end_code: int = clear + 1
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	var first := PackedByteArray()
	first.resize(4096)
	for i: int in range(clear):
		suffix[i] = i
		first[i] = i
	var stack := PackedByteArray()
	stack.resize(4097)
	var code_size: int = min_size + 1
	var next_code: int = clear + 2
	var old: int = -1
	var bits: int = 0
	var bit_count: int = 0
	var pos: int = 0
	var size: int = data.size()
	var op: int = 0
	while op < pixel_count:
		while bit_count < code_size:
			if pos >= size:
				return out
			bits |= data[pos] << bit_count
			pos += 1
			bit_count += 8
		var code: int = bits & ((1 << code_size) - 1)
		bits >>= code_size
		bit_count -= code_size
		if code == clear:
			code_size = min_size + 1
			next_code = clear + 2
			old = -1
			continue
		if code == end_code:
			return out
		if old == -1:
			if code >= clear:
				return out  # broken: the first code after a clear must be a colour
			out[op] = code
			op += 1
			old = code
			continue
		var in_code: int = code
		var sp: int = 0
		if code >= next_code:
			if code > next_code:
				return out  # broken
			stack[sp] = first[old]  # the KwKwK case: old's string plus its own first byte
			sp += 1
			code = old
		while code >= clear:
			stack[sp] = suffix[code]
			sp += 1
			code = prefix[code]
		stack[sp] = code
		sp += 1
		while sp > 0 and op < pixel_count:
			sp -= 1
			out[op] = stack[sp]
			op += 1
		if next_code < 4096:
			prefix[next_code] = old
			suffix[next_code] = code
			first[next_code] = first[old]
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1
		old = in_code
	return out


func _read_palette(size_bits: int) -> PackedByteArray:
	var length: int = 3 * (2 << size_bits)
	if _pos + length > _bytes.size():
		error = "truncated colour table"
		return PackedByteArray()
	var palette: PackedByteArray = _bytes.slice(_pos, _pos + length)
	_pos += length
	return palette


func _read_sub_blocks() -> PackedByteArray:
	var data := PackedByteArray()
	while _pos < _bytes.size():
		var length: int = _bytes[_pos]
		_pos += 1
		if length == 0:
			return data
		data.append_array(_bytes.slice(_pos, mini(_pos + length, _bytes.size())))
		_pos += length
	error = "truncated data"
	return data


func _skip_sub_blocks() -> bool:
	while _pos < _bytes.size():
		var length: int = _bytes[_pos]
		_pos += 1
		if length == 0:
			return true
		_pos += length
	error = "truncated extension"
	return false


func _u16(at: int) -> int:
	return _bytes[at] | (_bytes[at + 1] << 8) if at + 1 < _bytes.size() else 0
