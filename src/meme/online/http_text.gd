class_name HttpText
extends RefCounted
## Plain GET requests for the template sources on the host, all at once: the catalogue
## asks several providers and a search asks two, and waiting for them one after another
## would take seconds. Each body comes back as text, or "" on any failure.

signal _all_done

const USER_AGENT: String = "KillingForTheMemes/0.1 (private party game)"
const DEFAULT_TIMEOUT: float = 8.0
const MAX_BYTES: int = 2 * 1024 * 1024

var _bodies: PackedStringArray = []
var _left: int = 0


## Fetches every URL in parallel; the HTTPRequest nodes live under [param parent] while
## they run. Returns the bodies in the order of [param urls].
static func fetch_all(parent: Node, urls: PackedStringArray, timeout: float = DEFAULT_TIMEOUT) -> PackedStringArray:
	var batch := HttpText.new()
	batch._bodies.resize(urls.size())
	batch._left = urls.size()
	for i: int in range(urls.size()):
		var request := HTTPRequest.new()
		request.timeout = timeout
		request.body_size_limit = MAX_BYTES
		parent.add_child(request)
		request.request_completed.connect(batch._on_completed.bind(i, request))
		if request.request(urls[i], PackedStringArray(["User-Agent: " + USER_AGENT])) != OK:
			batch._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), i, request)
	if batch._left > 0:
		await batch._all_done
	return batch._bodies


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		index: int, request: HTTPRequest) -> void:
	request.queue_free()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	_bodies[index] = body.get_string_from_utf8() if ok else ""
	_left -= 1
	if _left == 0:
		_all_done.emit()
